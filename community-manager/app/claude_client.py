from anthropic import AsyncAnthropic

FLAG = "[FLAG FOR MANUAL REVIEW]"


class ReplyGenerator:
    """Wraps the Claude call. The system prompt is cached across requests."""

    def __init__(self, system_prompt: str, model: str, contact_email: str, client: AsyncAnthropic | None = None):
        self._system = system_prompt.replace("CONTACT_EMAIL", contact_email)
        self._model = model
        self._client = client or AsyncAnthropic()  # reads ANTHROPIC_API_KEY

    async def __call__(self, platform: str, action: str, content: str) -> str:
        # Strip the delimiter so a comment can't break out of [Content: '...'].
        safe = content.replace("'", "’").replace("]", ")").replace("[", "(")
        msg = await self._client.messages.create(
            model=self._model,
            max_tokens=300,
            system=[{"type": "text", "text": self._system, "cache_control": {"type": "ephemeral"}}],
            messages=[
                {"role": "user", "content": f"[Platform: {platform}] [Action: {action}] [Content: '{safe}']"}
            ],
        )
        text = "".join(b.text for b in msg.content if b.type == "text").strip()
        return text.strip("\"“”")
