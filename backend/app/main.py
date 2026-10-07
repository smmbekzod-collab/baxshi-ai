import os, uuid, threading, asyncio
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI, Request
from sqlalchemy import text
from .db import connect, initialize
from .security import config
from . import auth, media, learning, admin, social, education, ai
from .runtime import worker_loop, status
from .seed import seed_demo


def create_app(database_url=None, media_root=None, settings=None, testing=False):
    @asynccontextmanager
    async def lifespan(app):
        initialize(app.state.engine)  # Additive v0.3 tables, existing rows preserved.
        if os.environ.get("SEED_DEMO_CONTENT", "true").lower() == "true":
            seed_demo(app.state.engine, app.state.media)
        stop = threading.Event()
        thread = None
        if not testing and os.environ.get("EMBEDDED_WORKER", "true").lower() == "true":
            thread = threading.Thread(
                target=worker_loop,
                args=(app.state.engine, app.state.media, stop),
                daemon=True,
            )
            thread.start()
        try:
            yield
        finally:
            stop.set()
            if thread:
                await asyncio.to_thread(thread.join, 5)

    app = FastAPI(
        lifespan=lifespan,
        title="Baxshi AI",
        version="0.3.1",
        docs_url="/docs" if testing else None,
        redoc_url=None,
        openapi_url="/openapi.json" if testing else None,
    )
    app.state.engine = connect(database_url or os.environ["DATABASE_URL"])
    app.state.settings = settings or config()
    app.state.testing = testing
    app.state.media = Path(
        media_root or os.environ.get("MEDIA_ROOT", "./media")
    ).resolve()
    app.state.media.mkdir(parents=True, exist_ok=True)
    if testing:
        initialize(app.state.engine)

    @app.middleware("http")
    async def headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Request-ID"] = uuid.uuid4().hex
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/healthz")
    def health():
        with app.state.engine.connect() as c:
            c.execute(text("SELECT 1"))
        return {
            "status": "ok",
            "version": "0.3.1",
            "analysis": status(app.state.engine),
        }

    for router in [auth.r, media.r, learning.r, admin.r, social.r, education.r, ai.r]:
        app.include_router(router)
    return app
