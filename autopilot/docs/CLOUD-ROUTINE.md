# Optional: write content with a Claude Code cloud routine (laptop can be closed)

By default the autopilot calls `claude -p` on your computer. If you'd rather have content written on Anthropic's
infrastructure, a Claude Code **routine** (a scheduled cloud task, included in your subscription, minimum every hour)
can write posts into this repository's `autopilot/inbox/` folder. Your computer still does the rendering, scheduling
and Instagram publishing. Meta needs your token and the files, which stay local.

1. In `config/settings.toml`, set `ai.provider = "inbox"` and `ai.inbox_dir = "inbox"`.
2. On your computer, keep the repository pulled. For example, add a cron or launchd job running
   `git -C <repo> pull --ff-only` every 30 minutes.
3. Create a routine at claude.ai/code (Routines → New), for this repository, running daily, with this prompt:

```
Read autopilot/config/brand.md. Write 7 new social posts for the next week as ONE JSON file at
autopilot/inbox/<YYYY-MM-DD>.json containing a list of objects with keys:
platform ("instagram"|"youtube"), format (image|carousel|reel|story|community_text|community_image|community_poll|community_quiz),
topic, pillar, hook, headline, caption, hashtags (list), cta, sources (list of {title,url}), claims (list of {claim,source_url}),
and per format: slides [{title,text}] | script [{text,seconds}] | frames [{text}] | poll {question,options} |
quiz {question,options,answer_index,explanation}.
Rules: brand voice, no statistics without a real source URL you checked, no duplicates of hooks in autopilot/inbox/imported/.
Commit the file and push.
```

The importer fills open slots of the matching platform/format, runs the full quality gate, renders assets and moves
processed files to `inbox/imported/`.
