import os, secrets, hashlib, jwt, pyotp
from argon2 import PasswordHasher
from argon2.exceptions import VerificationError, InvalidHashError
from cryptography.fernet import Fernet
from fastapi import Request, HTTPException, Depends
from fastapi.security import HTTPBearer
from .db import users, sessions, rates, one, now, uid

ph = PasswordHasher()
dummy = ph.hash(secrets.token_urlsafe(32))
bearer = HTTPBearer(auto_error=False)


def digest(x):
    return hashlib.sha256(x.encode()).hexdigest()


def config():
    secret = os.environ.get("JWT_SECRET", "")
    key = os.environ.get("ENCRYPTION_KEY", "")
    if len(secret) < 48:
        raise RuntimeError("JWT_SECRET must contain 48+ random characters")
    Fernet(key.encode())
    return {"secret": secret, "key": key}


def db(request: Request):
    with request.app.state.engine.begin() as c:
        yield c


def fail(c, code, message):
    # Persist lockout/revocation even when FastAPI returns an error.
    c.commit()
    raise HTTPException(code, message)


def verify(password, encoded):
    try:
        return ph.verify(encoded, password)
    except (VerificationError, InvalidHashError):
        return False


def limit(c, key, maximum=60):
    key = digest(key)
    row = one(c, rates, rates.c.id == key, True)
    if row is None:
        c.execute(rates.insert().values(id=key, count=1, window=now()))
        return
    count = row["count"] + 1 if row["window"] > now() - 900 else 1
    c.execute(
        rates.update()
        .where(rates.c.id == key)
        .values(count=count, window=row["window"] if count > 1 else now())
    )
    if count > maximum:
        fail(c, 429, "rate_limit")


def tokens(c, settings, user, session=None):
    refresh = secrets.token_urlsafe(48)
    if session is None:
        sid = uid()
        c.execute(
            sessions.insert().values(
                id=sid,
                owner=user["id"],
                hash=digest(refresh),
                expires=now() + 30 * 86400,
            )
        )
    else:
        sid = session["id"]
        c.execute(
            sessions.update()
            .where(sessions.c.id == sid)
            .values(previous=session["hash"], hash=digest(refresh))
        )
    access = jwt.encode(
        {
            "sub": user["id"],
            "sid": sid,
            "iat": now(),
            "exp": now() + 900,
            "aud": "baxshi-mobile",
            "iss": "baxshi-ai",
        },
        settings["secret"],
        algorithm="HS256",
    )
    return {
        "access_token": access,
        "refresh_token": refresh,
        "subject": user["id"],
        "role": user["role"],
        "name": user["name"],
    }


def current(request: Request, credentials=Depends(bearer), c=Depends(db)):
    if credentials is None:
        raise HTTPException(401, "auth")
    try:
        claims = jwt.decode(
            credentials.credentials,
            request.app.state.settings["secret"],
            algorithms=["HS256"],
            audience="baxshi-mobile",
            issuer="baxshi-ai",
            options={"require": ["exp", "sub", "sid", "iat"]},
        )
        u = one(c, users, users.c.id == claims["sub"])
        s = one(c, sessions, sessions.c.id == claims["sid"])
        if (
            not u
            or not u["active"]
            or not s
            or s["owner"] != u["id"]
            or s["revoked"]
            or s["expires"] < now()
        ):
            raise ValueError()
        request.state.sid = s["id"]
        return u
    except (ValueError, KeyError, jwt.PyJWTError):
        raise HTTPException(401, "auth")


def admin(u=Depends(current)):
    if u["role"] != "super_admin":
        raise HTTPException(403, "super_admin_required")
    return u
