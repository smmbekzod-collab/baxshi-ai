"""Owner-scoped profile and messages restricted to admins or assigned teachers."""

import io, hashlib, os, tempfile
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from fastapi.responses import Response
from pydantic import Field, field_validator
from sqlalchemy import select, or_, and_
from PIL import Image, ImageOps, UnidentifiedImageError
from .db import users, objects, conversations, messages, one, add, now
from .security import db, current, limit
from .schemas import Body
from .learning import listing, can_review

r = APIRouter(prefix="/v1")
Image.MAX_IMAGE_PIXELS = 16_000_000


class Profile(Body):
    name: str = Field(min_length=2, max_length=160)
    bio: str = Field(default="", max_length=500)
    school: str = Field(default="", max_length=60)


    @field_validator("name", mode="before")
    @classmethod
    def trim_name(cls, value):
        return value.strip() if isinstance(value, str) else value


class NewThread(Body):
    recipient_id: str


class NewMessage(Body):
    client_id: str = Field(min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
    body: str = Field(min_length=1, max_length=4000)


def profile_data(c, id):
    rows = listing(c, "profile", id)
    return (
        rows[0]["data"] if rows else {"bio": "", "school": "", "avatar_version": None}
    )


def save_profile(c, id, data):
    key = hashlib.sha256(("profile:" + id).encode()).hexdigest()[:32]
    row = one(c, objects, objects.c.id == key)
    if row:
        c.execute(objects.update().where(objects.c.id == key).values(data=data))
    else:
        add(c, "profile", id, data, key)


def allowed(c, a, b):
    if a["id"] == b["id"] or not a["active"] or not b["active"]:
        return False
    return (
        a["role"] == "super_admin"
        or b["role"] == "super_admin"
        or can_review(c, a, b["id"])
        or can_review(c, b, a["id"])
    )


@r.get("/profile")
def profile(u=Depends(current), c=Depends(db)):
    return {
        "id": u["id"],
        "name": u["name"],
        "username": u["username"],
        "role": u["role"],
        **profile_data(c, u["id"]),
    }


@r.patch("/profile", status_code=204)
def update_profile(b: Profile, u=Depends(current), c=Depends(db)):
    one(c, users, users.c.id == u["id"], True)
    c.execute(users.update().where(users.c.id == u["id"]).values(name=b.name.strip()))
    save_profile(
        c, u["id"], {**profile_data(c, u["id"]), "bio": b.bio, "school": b.school}
    )


async def avatar_bytes(request: Request, u=Depends(current)):
    body = bytearray()
    async for part in request.stream():
        body.extend(part)
        if len(body) > 3 * 1024 * 1024:
            raise HTTPException(413, "avatar_too_large")
    return bytes(body)


@r.put("/profile/avatar", status_code=204)
def upload_avatar(
    request: Request,
    data: bytes = Depends(avatar_bytes),
    u=Depends(current),
    c=Depends(db),
):
    limit(c, "avatar:" + u["id"], 30)
    try:
        import warnings

        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            im = Image.open(io.BytesIO(data))
            if im.format not in ["JPEG", "PNG", "WEBP"]:
                raise ValueError()
            im = ImageOps.exif_transpose(im)
            im.load()
            im = ImageOps.fit(im.convert("RGB"), (512, 512))
    except (
        UnidentifiedImageError,
        OSError,
        ValueError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ):
        raise HTTPException(422, "invalid_avatar")
    one(c, users, users.c.id == u["id"], True)
    folder = request.app.state.media / "avatars"
    folder.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder)
    try:
        with os.fdopen(fd, "wb") as f:
            im.save(f, format="JPEG", quality=85)
        encoded = Path(tmp).read_bytes()
        version = hashlib.sha256(encoded).hexdigest()[:16]
        os.replace(tmp, folder / (u["id"] + ".jpg"))
    finally:
        Path(tmp).unlink(missing_ok=True)
    save_profile(c, u["id"], {**profile_data(c, u["id"]), "avatar_version": version})


@r.get("/profile/avatar")
def avatar(request: Request, u=Depends(current)):
    path = request.app.state.media / "avatars" / (u["id"] + ".jpg")
    if not path.exists():
        raise HTTPException(404, "no_avatar")
    return Response(
        path.read_bytes(),
        media_type="image/jpeg",
        headers={"Cache-Control": "private, no-store"},
    )


@r.delete("/profile/avatar", status_code=204)
def remove_avatar(request: Request, u=Depends(current), c=Depends(db)):
    one(c, users, users.c.id == u["id"], True)
    (request.app.state.media / "avatars" / (u["id"] + ".jpg")).unlink(missing_ok=True)
    save_profile(c, u["id"], {**profile_data(c, u["id"]), "avatar_version": None})


@r.get("/contacts")
def contacts(
    q: str = Query("", max_length=100),
    offset: int = Query(0, ge=0),
    u=Depends(current),
    c=Depends(db),
):
    # Permission is checked before pagination so assigned contacts cannot be hidden by unrelated users.
    rows = c.execute(
        select(users).where(users.c.active == True).order_by(users.c.name)
    ).mappings()
    results = [
        {"id": x["id"], "name": x["name"], "role": x["role"]}
        for x in rows
        if allowed(c, u, x) and q.lower() in x["name"].lower()
    ]
    return results[offset : offset + 100]


def check_thread(c, id, u):
    t = one(c, conversations, conversations.c.id == id)
    if not t or u["id"] not in [t["a"], t["b"]]:
        raise HTTPException(404, "thread_not_found")
    peer = one(c, users, users.c.id == (t["b"] if t["a"] == u["id"] else t["a"]))
    if not peer or not allowed(c, u, peer):
        raise HTTPException(403, "contact_unavailable")
    return t, peer


@r.post("/conversations", status_code=201)
def start_thread(b: NewThread, u=Depends(current), c=Depends(db)):
    peer = one(c, users, users.c.id == b.recipient_id)
    if not peer or not allowed(c, u, peer):
        raise HTTPException(403, "contact_unavailable")
    a, z = sorted([u["id"], peer["id"]])
    one(c, users, users.c.id == a, True)
    id = hashlib.sha256((a + ":" + z).encode()).hexdigest()[:32]
    if not one(c, conversations, conversations.c.id == id):
        c.execute(conversations.insert().values(id=id, a=a, b=z, created=now()))
    return {"id": id, "peer_name": peer["name"]}


@r.get("/conversations")
def threads(offset: int = Query(0, ge=0), u=Depends(current), c=Depends(db)):
    rows = c.execute(
        select(conversations)
        .where(or_(conversations.c.a == u["id"], conversations.c.b == u["id"]))
        .order_by(conversations.c.created.desc())
    ).mappings()
    result = []
    for t in rows:
        try:
            _, peer = check_thread(c, t["id"], u)
        except HTTPException:
            continue
        result.append(
            {"id": t["id"], "peer_name": peer["name"], "peer_role": peer["role"]}
        )
    return result[offset : offset + 100]


@r.get("/conversations/{id}/messages")
def get_messages(
    id: str, after: int = Query(0, ge=0), u=Depends(current), c=Depends(db)
):
    check_thread(c, id, u)
    return [
        dict(x)
        for x in c.execute(
            select(messages)
            .where(messages.c.thread == id, messages.c.id > after)
            .order_by(messages.c.id)
            .limit(100)
        ).mappings()
    ]


@r.post("/conversations/{id}/messages", status_code=201)
def send(id: str, b: NewMessage, u=Depends(current), c=Depends(db)):
    check_thread(c, id, u)
    one(c, users, users.c.id == u["id"], True)
    old = one(
        c,
        messages,
        and_(messages.c.sender == u["id"], messages.c.client_id == b.client_id),
    )
    body = b.body.strip()
    if not body:
        raise HTTPException(422, "empty_message")
    if old:
        if old["thread"] != id or old["body"] != body:
            raise HTTPException(409, "message_id_conflict")
        return {"id": old["id"]}
    limit(c, "message:" + u["id"], 100)
    inserted = c.execute(
        messages.insert().values(
            thread=id, sender=u["id"], client_id=b.client_id, body=body, created=now()
        )
    )
    return {"id": inserted.inserted_primary_key[0]}


def erase_user(c, id, media):
    (media / "avatars" / (id + ".jpg")).unlink(missing_ok=True)
    c.execute(
        objects.delete().where(
            objects.c.owner == id, objects.c.kind.in_(["profile", "lesson_progress"])
        )
    )
    c.execute(
        messages.update()
        .where(messages.c.sender == id)
        .values(body="[Deleted by account owner]")
    )
