from fastapi import APIRouter, Depends, Request, HTTPException
from sqlalchemy import select
from cryptography.fernet import Fernet
import pyotp
from .db import users, sessions, policy, one, now, uid, audit
from .security import db, current, verify, ph, dummy, limit, fail, tokens, digest
from . import schemas as S

r = APIRouter(prefix="/v1/auth")


@r.post("/register", status_code=201)
def register(b: S.Register, request: Request, c=Depends(db)):
    limit(c, "register:" + request.client.host, 10)
    if not one(c, policy, policy.c.id == 1)["data"]["registration"]:
        raise HTTPException(403, "registration_closed")
    if one(c, users, users.c.username == b.username.lower()):
        raise HTTPException(409, "username_exists")
    id = uid()
    c.execute(
        users.insert().values(
            id=id,
            username=b.username.lower(),
            name=b.name,
            password=ph.hash(b.password),
            role="user",
        )
    )
    audit(c, id, "registered", id)
    return {"id": id}


@r.post("/login")
def login(b: S.Login, request: Request, c=Depends(db)):
    limit(c, "login:" + request.client.host, 100)
    u = one(c, users, users.c.username == b.username.lower(), True)
    valid = verify(b.password, u["password"] if u else dummy)
    if u and u["locked_until"] > now():
        fail(c, 429, "account_locked")
    step = now() // 30
    if u and u["role"] == "super_admin":
        secret = (
            Fernet(request.app.state.settings["key"].encode())
            .decrypt(u["totp"].encode())
            .decode()
            if u["totp"]
            else ""
        )
        valid = (
            valid
            and bool(secret)
            and step > u["totp_step"]
            and pyotp.TOTP(secret).verify(b.otp, valid_window=0)
        )
    if not u or not u["active"] or not valid:
        if u:
            failures = u["failures"] + 1
            c.execute(
                users.update()
                .where(users.c.id == u["id"])
                .values(
                    failures=failures, locked_until=now() + 900 if failures >= 5 else 0
                )
            )
        fail(c, 401, "invalid_credentials_or_otp")
    c.execute(
        users.update()
        .where(users.c.id == u["id"])
        .values(
            failures=0,
            locked_until=0,
            totp_step=step if u["role"] == "super_admin" else -1,
        )
    )
    result = tokens(c, request.app.state.settings, u)
    audit(c, u["id"], "login", u["id"])
    return result


@r.post("/refresh")
def refresh(b: S.Refresh, request: Request, c=Depends(db)):
    hash = digest(b.refresh_token)
    s = one(c, sessions, sessions.c.hash == hash, True)
    if not s:
        old = one(c, sessions, sessions.c.previous == hash, True)
        if old:
            c.execute(
                sessions.update().where(sessions.c.id == old["id"]).values(revoked=True)
            )
        fail(c, 401, "invalid_refresh")
    u = one(c, users, users.c.id == s["owner"])
    if s["revoked"] or s["expires"] < now() or not u["active"]:
        raise HTTPException(401, "invalid_refresh")
    return tokens(c, request.app.state.settings, u, s)


@r.get("/me")
def me(u=Depends(current)):
    return {k: u[k] for k in ["id", "username", "name", "role"]}


@r.post("/logout", status_code=204)
def logout(request: Request, u=Depends(current), c=Depends(db)):
    c.execute(
        sessions.update().where(sessions.c.id == request.state.sid).values(revoked=True)
    )


@r.post("/password", status_code=204)
def password(b: S.Password, u=Depends(current), c=Depends(db)):
    if not verify(b.old_password, u["password"]):
        raise HTTPException(401, "invalid_credentials")
    c.execute(
        users.update()
        .where(users.c.id == u["id"])
        .values(password=ph.hash(b.new_password))
    )
    c.execute(sessions.update().where(sessions.c.owner == u["id"]).values(revoked=True))
    audit(c, u["id"], "password_changed", u["id"])
