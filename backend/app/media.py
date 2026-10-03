import hashlib, os, tempfile
from pathlib import Path
from fastapi import APIRouter, Depends, Request, HTTPException, Header
from fastapi.responses import FileResponse
from sqlalchemy import select, func
from .db import users, objects, uploads, one, obj, add, audit, now, uid
from .security import db, current
from . import schemas as S

r = APIRouter(prefix="/v1")


def require(x):
    if x is None:
        raise HTTPException(404, "not_found")
    return x


def own_upload(c, id, u, lock=False):
    x = require(one(c, uploads, uploads.c.id == id, lock))
    if x["owner"] != u["id"]:
        raise HTTPException(404, "not_found")
    if x["created"] + 604800 < now() and not x["asset_id"]:
        raise HTTPException(410, "upload_expired")
    return x


@r.post("/uploads", status_code=201)
def start(b: S.Upload, u=Depends(current), c=Depends(db)):
    one(c, users, users.c.id == u["id"], True)
    x = one(
        c,
        uploads,
        (uploads.c.owner == u["id"]) & (uploads.c.recording_id == b.recording_id),
    )
    if x:
        if (x["size"], x["sha256"], x["mime"]) != (b.size, b.sha256, b.mime):
            raise HTTPException(409, "idempotency_mismatch")
        return {"id": x["id"]}
    total = c.execute(
        select(func.coalesce(func.sum(uploads.c.size), 0)).where(
            uploads.c.owner == u["id"]
        )
    ).scalar_one()
    if total + b.size > 1024**3:
        raise HTTPException(413, "storage_quota")
    id = uid()
    c.execute(uploads.insert().values(id=id, owner=u["id"], **b.model_dump()))
    return {"id": id}


@r.get("/uploads/{id}")
def status(id: str, u=Depends(current), c=Depends(db)):
    return {"offset": own_upload(c, id, u)["offset"]}


async def chunk_bytes(request: Request, u=Depends(current)):
    data = bytearray()
    async for block in request.stream():
        data.extend(block)
        if len(data) > 1024**2:
            raise HTTPException(413, "chunk_too_large")
    return bytes(data)


@r.put(
    "/uploads/{id}/chunks/{offset}",
    status_code=204,
    openapi_extra={
        "requestBody": {
            "required": True,
            "content": {
                "application/octet-stream": {
                    "schema": {"type": "string", "format": "binary"}
                }
            },
        }
    },
)
def chunk(
    id: str,
    offset: int,
    request: Request,
    content_range: str = Header(),
    x_chunk_sha256: str = Header(),
    data: bytes = Depends(chunk_bytes),
    u=Depends(current),
    c=Depends(db),
):
    if not data or offset < 0:
        raise HTTPException(422, "invalid_chunk")
    x = own_upload(c, id, u, True)
    end = offset + len(data)
    if x["asset_id"]:
        raise HTTPException(409, "already_complete")
    if content_range != f"bytes {offset}-{end - 1}/{x['size']}" or end > x["size"]:
        raise HTTPException(422, "range")
    if hashlib.sha256(data).hexdigest() != x_chunk_sha256:
        raise HTTPException(422, "chunk_hash")
    path = request.app.state.media / "chunks" / id / str(offset)
    if offset < x["offset"]:
        if not path.exists() or path.read_bytes() != data:
            raise HTTPException(409, "chunk_mismatch")
        return
    if offset != x["offset"]:
        raise HTTPException(409, "offset")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    c.execute(uploads.update().where(uploads.c.id == id).values(offset=end))


@r.post("/uploads/{id}/complete")
def complete(
    id: str, b: S.Complete, request: Request, u=Depends(current), c=Depends(db)
):
    x = own_upload(c, id, u, True)
    if x["sha256"] != b.sha256:
        raise HTTPException(409, "checksum_mismatch")
    if x["asset_id"]:
        return {"asset_id": x["asset_id"]}
    if x["offset"] != x["size"]:
        raise HTTPException(409, "incomplete")
    aid = uid()
    path = request.app.state.media / "assets" / aid
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("xb") as target:
            for p in sorted(
                (
                    p
                    for p in (request.app.state.media / "chunks" / id).iterdir()
                    if p.name.isdigit()
                ),
                key=lambda p: int(p.name),
            ):
                if target.tell() != int(p.name):
                    raise HTTPException(409, "gap")
                target.write(p.read_bytes())
        with path.open("rb") as f:
            hash = hashlib.file_digest(f, "sha256").hexdigest()
        if hash != b.sha256 or path.stat().st_size != x["size"]:
            raise HTTPException(422, "file_hash")
        add(
            c,
            "asset",
            u["id"],
            {"path": str(path), "sha256": hash, "mime": x["mime"], "size": x["size"]},
            aid,
        )
        c.execute(uploads.update().where(uploads.c.id == id).values(asset_id=aid))
        audit(c, u["id"], "upload_completed", aid)
    except Exception:
        path.unlink(missing_ok=True)
        raise
    return {"asset_id": aid}


def asset(c, id, u):
    x = require(obj(c, id, "asset"))
    if x["owner"] != u["id"]:
        refs = c.execute(
            select(objects).where(objects.c.kind == "reference")
        ).mappings()
        if not any(
            v["data"]["asset_id"] == id
            and v["data"]["active"]
            and v["data"]["license_until"] > now()
            for v in refs
        ):
            raise HTTPException(404, "not_found")
    return x


@r.get("/assets/{id}")
def metadata(id: str, u=Depends(current), c=Depends(db)):
    x = asset(c, id, u)
    return {"id": id, "sha256": x["data"]["sha256"], "mime": x["data"]["mime"]}


@r.get("/assets/{id}/content")
def content(id: str, u=Depends(current), c=Depends(db)):
    x = asset(c, id, u)["data"]
    if not Path(x["path"]).exists():
        raise HTTPException(410, "media_expired")
    return FileResponse(
        x["path"], media_type=x["mime"], headers={"Cache-Control": "private, no-store"}
    )
