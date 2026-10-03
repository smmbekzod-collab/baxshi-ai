import os, uuid
from pathlib import Path
from fastapi import FastAPI, Request
from sqlalchemy import text
from .db import connect, initialize
from .security import config
from . import auth, media, learning, admin


def create_app(database_url=None, media_root=None, settings=None, testing=False):
    app = FastAPI(
        title="Baxshi AI",
        version="0.2.0",
        docs_url="/docs" if testing else None,
        redoc_url=None,
        openapi_url="/openapi.json" if testing else None,
    )
    app.state.engine = connect(database_url or os.environ["DATABASE_URL"])
    app.state.settings = settings or config()
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
        return {"status": "ok"}

    for router in [auth.r, media.r, learning.r, admin.r]:
        app.include_router(router)
    return app
