import asyncio
import hmac
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import BackgroundTasks, FastAPI, Header, HTTPException, Request, Response

from .claude_client import ReplyGenerator
from .config import Settings
from .engine import Engine
from .meta import MetaClient, parse_webhook, valid_signature
from .store import Store

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("community")


def build_app(settings: Settings | None = None, engine: Engine | None = None, meta=None) -> FastAPI:
    s = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        store = Store(s.db_path)
        store.reset_pending()
        app.state.store = store
        app.state.meta = meta or MetaClient(s)
        if engine is None:
            gen = ReplyGenerator(Path(s.system_prompt_path).read_text(), s.anthropic_model, s.contact_email)
            app.state.engine = Engine(s, store, gen, app.state.meta)
        else:
            app.state.engine = engine
        log.info("starting; dry_run=%s", s.dry_run)
        task = asyncio.create_task(_poll_loop(app)) if s.poll_interval > 0 and s.page_token else None
        yield
        if task:
            task.cancel()

    async def _poll_loop(app: FastAPI):
        while True:
            try:
                for ev in await app.state.meta.poll():
                    await app.state.engine.handle(ev)
            except Exception:
                log.exception("poll failed")
            await asyncio.sleep(s.poll_interval)

    app = FastAPI(lifespan=lifespan)

    @app.get("/healthz")
    def healthz():
        return {"ok": True, "dry_run": s.dry_run}

    @app.get("/webhook")
    def verify(request: Request):
        q = request.query_params
        if q.get("hub.mode") == "subscribe" and s.verify_token and hmac.compare_digest(
            q.get("hub.verify_token", ""), s.verify_token
        ):
            return Response(q.get("hub.challenge", ""), media_type="text/plain")
        raise HTTPException(403)

    @app.post("/webhook")
    async def receive(request: Request, bg: BackgroundTasks):
        raw = await request.body()
        if not valid_signature(s.app_secret, raw, request.headers.get("X-Hub-Signature-256", "")):
            raise HTTPException(403)
        for ev in parse_webhook(await request.json()):
            bg.add_task(app.state.engine.handle, ev)  # return 200 fast; Meta retries slow endpoints
        return {"ok": True}

    @app.get("/admin/log")
    def admin_log(limit: int = 50, x_admin_token: str = Header("")):
        if not s.admin_token or not hmac.compare_digest(x_admin_token, s.admin_token):
            raise HTTPException(403)
        return app.state.store.recent(min(limit, 500))

    return app


app = build_app()
