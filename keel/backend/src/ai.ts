import Anthropic from "@anthropic-ai/sdk";
import type { Env } from "./index";

/**
 * Per-task model routing. Apple Intelligence handles high-volume work on the phone, so the cloud
 * only sees heavy or fallback requests. All routes use Claude Opus 5.5; `effort` keeps small jobs cheap.
 * Cost lever (your call): swap "triage"/"summarize" to "claude-haiku-5-5" for ~40x lower cost on
 * devices without Apple Intelligence.
 */
const ROUTES: Record<string, { model: string; effort: "low" | "medium" | "high"; maxTokens: number }> = {
  triage: { model: "claude-opus-5-5", effort: "low", maxTokens: 1024 },
  summarize: { model: "claude-opus-5-5", effort: "low", maxTokens: 1024 },
  draft_reply: { model: "claude-opus-5-5", effort: "medium", maxTokens: 4096 },
  promises: { model: "claude-opus-5-5", effort: "low", maxTokens: 1024 },
  break_down: { model: "claude-opus-5-5", effort: "medium", maxTokens: 2048 },
  plan_day: { model: "claude-opus-5-5", effort: "high", maxTokens: 8192 },
  checklist: { model: "claude-opus-5-5", effort: "low", maxTokens: 2048 },
  test: { model: "claude-opus-5-5", effort: "low", maxTokens: 256 },
  meeting_notes: { model: "claude-opus-5-5", effort: "medium", maxTokens: 8192 },
  answer: { model: "claude-opus-5-5", effort: "low", maxTokens: 1024 },
  reorganize_notes: { model: "claude-opus-5-5", effort: "medium", maxTokens: 16000 },
};
// Any newer app task the server doesn't know yet still works, on the cheap setting.
const DEFAULT_ROUTE = { model: "claude-opus-5-5", effort: "medium" as const, maxTokens: 4096 };

type AIRequest = { task: string; system: string; user: string; schema: Record<string, unknown> };

export async function handleAI(req: Request, env: Env): Promise<Response> {
  const body = (await req.json()) as AIRequest;
  if (!body || typeof body.task !== "string" || typeof body.user !== "string") return json({ error: "bad request" }, 400);
  const route = ROUTES[body.task] ?? DEFAULT_ROUTE;

  // Daily quota so a sync bug can never run up your bill.
  const key = `quota:${new Date().toISOString().slice(0, 10)}`;
  const used = Number((await env.KEEL.get(key)) ?? 0);
  if (used >= Number(env.DAILY_AI_LIMIT)) return json({ error: "daily AI limit reached" }, 429);
  await env.KEEL.put(key, String(used + 1), { expirationTtl: 60 * 60 * 48 });

  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
  try {
    const response = await client.beta.messages.create({
      model: route.model,
      max_tokens: route.maxTokens,
      // Server-side refusal fallback: if a safety classifier declines, the API re-runs on a suitable model.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: body.system,
      output_config: {
        effort: route.effort,
        format: { type: "json_schema", schema: body.schema },
      },
      messages: [{ role: "user", content: body.user }],
    });

    const stop = response.stop_reason ?? "unknown";
    if (stop === "refusal") return json({ stop_reason: stop, json: null });
    const text = response.content.find((b: { type: string }) => b.type === "text") as { text: string } | undefined;
    return json({ stop_reason: stop, json: text ? JSON.parse(text.text) : null });
  } catch (err) {
    if (err instanceof Anthropic.RateLimitError) return json({ error: "rate limited" }, 429);
    if (err instanceof Anthropic.APIError) return json({ error: err.message }, 502);
    throw err;
  }
}

export const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
