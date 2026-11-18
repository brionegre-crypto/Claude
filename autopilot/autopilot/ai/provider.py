"""AI providers. Claude Code is the only reasoning engine; no other model is ever called.

- ClaudeCLIProvider: runs the official `claude` CLI in headless mode (`claude -p`) on this computer, authenticated
  with YOUR subscription (`claude /login` or a `claude setup-token` token in CLAUDE_CODE_OAUTH_TOKEN). It refuses to
  run if ANTHROPIC_API_KEY is set, because `claude -p` would then bill the API instead of the subscription.
- MockProvider: deterministic fake output for tests and simulation without spending usage.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import time

from autopilot import logs
from autopilot.db import DB, iso, utcnow

log = logs.get("ai")


class ProviderUnavailable(RuntimeError):
    """Temporary inability to call the AI (budget, usage limit, login expired). The queue buffer keeps publishing."""


class ProviderError(RuntimeError):
    pass


def extract_json(text: str):
    text = text.strip()
    fence = re.search(r"```(?:json)?\s*(.+?)```", text, re.S)
    if fence:
        text = fence.group(1).strip()
    for opener, closer in (("{", "}"), ("[", "]")):
        start = text.find(opener)
        end = text.rfind(closer)
        if start != -1 and end > start:
            try:
                return json.loads(text[start:end + 1])
            except json.JSONDecodeError:
                continue
    raise ProviderError("AI response did not contain valid JSON")


class BaseProvider:
    name = "base"

    def __init__(self, settings, db: DB):
        self.s, self.db = settings, db

    def calls_today(self) -> int:
        start = utcnow().astimezone(self.s.tz).replace(hour=0, minute=0, second=0)
        return self.db.one("SELECT COUNT(*) FROM ai_calls WHERE at >= ? AND provider=?", (iso(start), self.name))[0]

    def _record(self, purpose, ok, ms, err=None):
        self.db.x("INSERT INTO ai_calls(at,purpose,provider,ok,duration_ms,error) VALUES(?,?,?,?,?,?)",
                  (iso(), purpose, self.name, int(ok), ms, (err or "")[:500]))

    def complete_json(self, purpose: str, prompt: str, web: bool = False):
        budget = int(self.s.get("ai.max_calls_per_day", 25))
        # the budget protects your Claude subscription; the offline mock (wizard samples, tests) uses none of it
        if self.name != "mock" and self.calls_today() >= budget:
            raise ProviderUnavailable(f"daily AI budget reached ({budget} calls); resumes tomorrow")
        t = time.monotonic()
        try:
            out = self._complete(purpose, prompt, web)
            data = extract_json(out)
        except Exception as e:
            self._record(purpose, False, int((time.monotonic() - t) * 1000), str(e))
            raise
        self._record(purpose, True, int((time.monotonic() - t) * 1000))
        return data

    def _complete(self, purpose, prompt, web) -> str:  # pragma: no cover
        raise NotImplementedError

    def status(self) -> dict:
        return {"provider": self.name, "calls_today": self.calls_today(), "budget": self.s.get("ai.max_calls_per_day", 25)}


_UNAVAILABLE_MARKERS = ("usage limit", "rate limit", "login expired", "please run /login", "not logged in",
                        "invalid api key", "credit balance", "limit reached", "overloaded", "authentication")


class ClaudeCLIProvider(BaseProvider):
    name = "claude_cli"

    def binary(self) -> str | None:
        b = self.s.get("ai.claude_binary", "claude")
        return shutil.which(b) or (b if os.path.exists(b) else None)

    def _env(self) -> dict:
        env = dict(os.environ)
        if env.get("ANTHROPIC_API_KEY"):
            raise ProviderUnavailable("ANTHROPIC_API_KEY is set: refusing, because `claude -p` would bill the API "
                                      "instead of your subscription. Unset it for the autopilot service.")
        tok = None
        try:
            from autopilot.secrets import SecretStore
            tok = SecretStore(self.s.data_dir).get("claude_code_oauth_token")
        except Exception:
            pass
        if tok:
            env["CLAUDE_CODE_OAUTH_TOKEN"] = tok
        env.pop("CLAUDECODE", None)  # the service is never nested, but manual runs from a Claude session may be
        return env

    def _complete(self, purpose, prompt, web) -> str:
        b = self.binary()
        if not b:
            raise ProviderUnavailable("`claude` CLI not found on PATH")
        sandbox = self.s.data_dir / "ai-sandbox"     # empty working dir: Claude cannot read or edit project files
        sandbox.mkdir(exist_ok=True)
        allowed = ["WebSearch", "WebFetch"] if web and self.s.get("ai.allow_web_tools", True) else []
        cmd = [b, "-p", prompt, "--output-format", "json", "--max-turns", "12" if allowed else "2",
               "--disallowedTools", "Bash", "Edit", "Write", "NotebookEdit", "Task"]
        if allowed:
            cmd += ["--allowedTools", *allowed]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, cwd=sandbox, env=self._env(),
                                  timeout=int(self.s.get("ai.timeout_seconds", 300)), stdin=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            raise ProviderUnavailable("claude CLI timed out")
        blob = (proc.stdout or "") + (proc.stderr or "")
        try:
            env = json.loads(proc.stdout)
        except json.JSONDecodeError:
            env = None
        if env is None or proc.returncode != 0 or env.get("is_error"):
            msg = (env or {}).get("result") or blob[-400:]
            if any(m in str(msg).lower() for m in _UNAVAILABLE_MARKERS):
                raise ProviderUnavailable(f"Claude Code unavailable: {str(msg)[:200]}")
            raise ProviderError(f"claude CLI failed (exit {proc.returncode}): {str(msg)[:300]}")
        return env.get("result", "")

    def check(self) -> tuple[bool, str]:
        """Tiny live call used by the wizard/diagnostics to prove subscription auth works headlessly."""
        try:
            data = self.complete_json("healthcheck", 'Reply with exactly this JSON and nothing else: {"ok": true}')
            return bool(data.get("ok")), "Claude Code headless call succeeded"
        except Exception as e:
            return False, str(e)


class MockProvider(BaseProvider):
    """Deterministic stand-in. Marks everything it writes as generated_by=mock so it is never mistaken for AI output."""
    name = "mock"

    def _complete(self, purpose, prompt, web) -> str:
        h = int(hashlib.sha256(prompt.encode()).hexdigest()[:8], 16)
        if purpose == "healthcheck":
            return '{"ok": true}'
        if purpose == "research_eval":
            ids = [int(x) for x in re.findall(r'"id":\s*(\d+)', prompt)]
            return json.dumps({"items": [{"id": i, "relevance": 0.6 + (i % 4) / 10, "kind": "news",
                                          "pillar": "Discipline systems",
                                          "opportunities": [f"Angle {i}: what this means on an ordinary Tuesday"],
                                          "verification": "verified", "verification_notes": "mock"} for i in ids]})
        if purpose == "generate":
            fmt = re.search(r"FORMAT: (\w+)", prompt).group(1)
            topic = re.search(r"TOPIC: (.+)", prompt).group(1).strip()
            n = h % 1000
            base = {
                "topic": topic, "pillar": "Discipline systems",
                "hook": f"{topic}: the part nobody schedules (#{n})",
                "headline": f"{topic[:40]}",
                "caption": f"{topic}.\n\nMost men mean it. Few men write down the when. Variant {n}.\n\nWhat is one thing you'll do before Thursday?",
                "hashtags": ["#bethemansystem", "#christianmen", "#mensdiscipline"],
                "cta": "Comment STEP1 for the free worksheet.",
                "image_concept": "Dark background, amber headline, cream body text",
                "claims": [],
            }
            if fmt in ("image", "community_image"):
                base["slides"] = [{"title": f"{topic[:40]}", "text": f"Write down the when. Variant {n}."}]
            elif fmt == "carousel":
                base["slides"] = [{"title": f"Slide {i+1}: {topic[:30]}", "text": f"Point {i+1} for variant {n}."} for i in range(5)]
            elif fmt == "reel":
                base["script"] = [{"text": f"Beat {i+1}: {topic[:40]}", "seconds": 3} for i in range(5)]
            elif fmt == "story":
                base["frames"] = [{"text": f"{topic[:50]}", "sticker": "poll"}, {"text": "Step 1 is free. Link in bio."}]
            elif fmt == "community_poll":
                base["poll"] = {"question": f"Which is harder for you: {topic[:40]}?", "options": ["Starting", "Keeping it going", "Telling someone"]}
            elif fmt == "community_quiz":
                base["quiz"] = {"question": f"Quick check on {topic[:40]}", "options": ["A", "B", "C"], "answer_index": 1,
                                "explanation": "Because the when beats the why."}
            return json.dumps(base)
        if purpose == "research_verify":
            return json.dumps({"verification": "verified", "claim": "mock claim", "source_url": "https://example.org/a",
                               "corroborating_url": "https://example.org/b", "notes": "mock"})
        if purpose == "insights":
            return json.dumps({"summary": "Mock insight: not enough real data yet.", "recommendations": []})
        return "{}"


def get_provider(settings, db: DB) -> BaseProvider:
    p = settings.get("ai.provider", "claude_cli")
    if p == "mock" or (p == "claude_cli" and os.environ.get("AUTOPILOT_FORCE_MOCK_AI")):
        return MockProvider(settings, db)
    if p == "inbox":
        # Inbox mode: content arrives as files from a Claude Code cloud routine; local calls are not made.
        return InboxOnlyProvider(settings, db)
    return ClaudeCLIProvider(settings, db)


class InboxOnlyProvider(BaseProvider):
    name = "inbox"

    def _complete(self, purpose, prompt, web):
        raise ProviderUnavailable("AI provider is 'inbox': content is imported from the inbox folder, not generated locally")
