import hashlib, json
from datetime import date
from pathlib import Path
from fastapi import APIRouter, Depends, Request, HTTPException, Header
from sqlalchemy import select, func
from .db import users, objects, jobs, policy, sessions, one, obj, add, audit, now, uid
from .security import db, current
from .media import require
from . import schemas as S

r = APIRouter(prefix="/v1")


def listing(c, kind, owner=None):
    q = select(objects).where(objects.c.kind == kind)
    if owner:
        q = q.where(objects.c.owner == owner)
    return c.execute(q.order_by(objects.c.created.desc())).mappings().all()


def serialize(x):
    return {
        **x["data"],
        "id": x["id"],
        "owner": x["owner"],
        "created": x["created"],
        "version": x["version"],
    }


def can_review(c, u, owner):
    if u["role"] == "super_admin":
        return True
    if u["role"] != "teacher":
        return False
    groups = {
        x["id"] for x in listing(c, "group") if x["data"]["teacher_id"] == u["id"]
    }
    return any(
        x["data"]["group_id"] in groups and x["data"]["user_id"] == owner
        for x in listing(c, "member")
    )


@r.get("/config")
def config(c=Depends(db)):
    p = one(c, policy, policy.c.id == 1)
    return {**p["data"], "version": p["version"]}


@r.get("/references")
def references(school: str | None = None, u=Depends(current), c=Depends(db)):
    out = []
    for x in listing(c, "reference"):
        d = x["data"]
        if (
            d["active"]
            and d["license_until"] > now()
            and (not school or d["school"] == school)
        ):
            a = obj(c, d["asset_id"], "asset")
            if a and Path(a["data"]["path"]).exists():
                out.append(
                    {
                        **serialize(x),
                        "sha256": a["data"]["sha256"],
                        "mime": a["data"]["mime"],
                    }
                )
    return out


@r.get("/contents")
def contents(u=Depends(current), c=Depends(db)):
    return [serialize(x) for x in listing(c, "content") if x["data"]["published"]]


@r.post("/analyses", status_code=202)
def analyze(
    b: S.Analyze,
    request: Request,
    idempotency_key: str = Header(min_length=8, max_length=200),
    u=Depends(current),
    c=Depends(db),
):
    one(c, users, users.c.id == u["id"], True)
    p = one(c, policy, policy.c.id == 1)["data"]
    if p["maintenance"]:
        raise HTTPException(503, "maintenance")
    if not request.app.state.testing:
        from .runtime import status

        health = status(request.app.state.engine)
        if not health["ffmpeg_available"]:
            raise HTTPException(503, "decoder_unavailable")
        if not health["worker_online"]:
            raise HTTPException(503, "worker_unavailable")
    version = request.headers.get("X-App-Version", "0.2.0")
    try:
        if tuple(map(int, version.split("."))) < tuple(
            map(int, p["minimum_app_version"].split("."))
        ):
            raise HTTPException(426, "upgrade_required")
    except ValueError:
        raise HTTPException(422, "invalid_version")
    digest = hashlib.sha256(
        json.dumps(b.model_dump(), sort_keys=True).encode()
    ).hexdigest()
    previous = one(
        c, jobs, (jobs.c.owner == u["id"]) & (jobs.c.idem == idempotency_key)
    )
    if previous:
        if previous["digest"] != digest:
            raise HTTPException(409, "idempotency_mismatch")
        return {"job_id": previous["id"]}
    a = require(obj(c, b.asset_id, "asset", u["id"]))
    if not Path(a["data"]["path"]).exists():
        raise HTTPException(410, "media_expired")
    if b.reference_id:
        ref = require(obj(c, b.reference_id, "reference"))["data"]
        if (
            not ref["active"]
            or ref["license_until"] < now()
            or ref["school"] != b.school
        ):
            raise HTTPException(422, "invalid_reference")
    count = c.execute(
        select(func.count())
        .select_from(jobs)
        .where(jobs.c.owner == u["id"], jobs.c.created > now() - 86400)
    ).scalar_one()
    if count >= p["daily_job_limit"]:
        raise HTTPException(429, "daily_quota")
    id = uid()
    c.execute(
        jobs.insert().values(
            id=id,
            owner=u["id"],
            idem=idempotency_key,
            digest=digest,
            data=b.model_dump(),
        )
    )
    audit(c, u["id"], "analysis_consent", id, {"version": b.consent_version})
    return {"job_id": id}


@r.get("/analyses")
def my_jobs(u=Depends(current), c=Depends(db)):
    return [
        dict(x)
        for x in c.execute(
            select(jobs)
            .where(jobs.c.owner == u["id"])
            .order_by(jobs.c.created.desc())
            .limit(100)
        ).mappings()
    ]


@r.get("/analyses/{id}")
def job(id: str, u=Depends(current), c=Depends(db)):
    x = require(one(c, jobs, (jobs.c.id == id) & (jobs.c.owner == u["id"])))
    return {
        "id": id,
        "status": x["status"],
        "report_id": x["report_id"],
        "error_code": x["error"],
    }


@r.post("/analyses/{id}/cancel", status_code=204)
def cancel(id: str, u=Depends(current), c=Depends(db)):
    x = require(one(c, jobs, (jobs.c.id == id) & (jobs.c.owner == u["id"]), True))
    if x["status"] in ["queued", "running"]:
        c.execute(
            jobs.update().where(jobs.c.id == id).values(status="cancelled", lease=None)
        )


@r.get("/reports/latest")
def latest(u=Depends(current), c=Depends(db)):
    rows = listing(c, "report", u["id"])
    if not rows:
        raise HTTPException(404, "no_report")
    return rows[0]["data"]


@r.get("/reports")
def reports(u=Depends(current), c=Depends(db)):
    return [x["data"] for x in listing(c, "report", u["id"])]


@r.get("/reports/{id}")
def report(id: str, u=Depends(current), c=Depends(db)):
    x = require(obj(c, id, "report"))
    if x["owner"] != u["id"] and not can_review(c, u, x["owner"]):
        raise HTTPException(404, "not_found")
    return x["data"]


@r.get("/reports/{id}/reviews")
def reviews(id: str, u=Depends(current), c=Depends(db)):
    report(id, u, c)
    return [serialize(x) for x in listing(c, "review") if x["data"]["report_id"] == id]


@r.post("/reports/{id}/reviews", status_code=201)
def review(id: str, b: S.Review, u=Depends(current), c=Depends(db)):
    x = require(obj(c, id, "report"))
    if not can_review(c, u, x["owner"]):
        raise HTTPException(403, "teacher_required")
    rid = add(
        c,
        "review",
        u["id"],
        {**b.model_dump(), "report_id": id, "rubric": "teacher-v1"},
    )
    audit(c, u["id"], "review_created", id)
    return {"id": rid}


@r.get("/practice")
def practice(u=Depends(current), c=Depends(db)):
    return [serialize(x) for x in listing(c, "practice", u["id"])]


@r.put("/practice", status_code=204)
def save_practice(b: S.Practice, u=Depends(current), c=Depends(db)):
    try:
        d = date.fromisoformat(b.day)
    except ValueError:
        raise HTTPException(422, "invalid_date")
    if d > date.today():
        raise HTTPException(422, "future_date")
    one(c, users, users.c.id == u["id"], True)
    x = next(
        (x for x in listing(c, "practice", u["id"]) if x["data"]["day"] == b.day), None
    )
    if x:
        c.execute(
            objects.update().where(objects.c.id == x["id"]).values(data=b.model_dump())
        )
    else:
        add(c, "practice", u["id"], b.model_dump())


@r.get("/research-consent")
def consent_get(u=Depends(current), c=Depends(db)):
    x = next(iter(listing(c, "consent", u["id"])), None)
    return {"enabled": x["data"]["enabled"] if x else False}


@r.put("/research-consent", status_code=204)
def consent(b: S.Consent, u=Depends(current), c=Depends(db)):
    one(c, users, users.c.id == u["id"], True)
    c.execute(
        objects.delete().where(objects.c.kind == "consent", objects.c.owner == u["id"])
    )
    add(c, "consent", u["id"], b.model_dump())
    audit(c, u["id"], "research_consent", u["id"], b.model_dump())


@r.get("/export")
def export(u=Depends(current), c=Depends(db)):
    return {
        "profile": {k: u[k] for k in ["id", "name", "username"]},
        "reports": reports(u, c),
        "practice": practice(u, c),
    }


@r.post("/delete-account", status_code=202)
def delete_account(request: Request, u=Depends(current), c=Depends(db)):
    if u["role"] == "super_admin":
        raise HTTPException(409, "protected_admin")
    c.execute(
        users.update()
        .where(users.c.id == u["id"])
        .values(
            active=False,
            name="Deleted",
            username="deleted-" + u["id"],
            password="disabled",
            totp=None,
        )
    )
    c.execute(sessions.update().where(sessions.c.owner == u["id"]).values(revoked=True))
    c.execute(
        jobs.update()
        .where(jobs.c.owner == u["id"], jobs.c.status.in_(["queued", "running"]))
        .values(status="cancelled", lease=None)
    )
    c.execute(
        objects.delete().where(objects.c.kind == "consent", objects.c.owner == u["id"])
    )
    from .social import erase_user

    erase_user(c, u["id"], request.app.state.media)
    audit(c, u["id"], "deletion_requested", u["id"])
    return {"status": "scheduled"}


@r.get("/assignments")
def assignments(u=Depends(current), c=Depends(db)):
    groups = {
        x["data"]["group_id"]
        for x in listing(c, "member")
        if x["data"]["user_id"] == u["id"]
    }
    return [
        serialize(x)
        for x in listing(c, "assignment")
        if x["data"]["group_id"] in groups
    ]


@r.put("/assignments/{id}/submit", status_code=204)
def submit(id: str, b: S.Submit, u=Depends(current), c=Depends(db)):
    if id not in {x["id"] for x in assignments(u, c)}:
        raise HTTPException(404, "not_found")
    require(obj(c, b.report_id, "report", u["id"]))
    one(c, users, users.c.id == u["id"], True)
    for x in listing(c, "submission", u["id"]):
        if x["data"]["assignment_id"] == id:
            c.execute(objects.delete().where(objects.c.id == x["id"]))
    add(c, "submission", u["id"], {"assignment_id": id, "report_id": b.report_id})


@r.post("/analyses/{id}/retry", status_code=204)
def retry(id: str, request: Request, u=Depends(current), c=Depends(db)):
    from .security import limit

    x = require(one(c, jobs, (jobs.c.id == id) & (jobs.c.owner == u["id"]), True))
    if x["status"] != "failed":
        raise HTTPException(409, "invalid_job_action")
    asset = require(obj(c, x["data"]["asset_id"], "asset", u["id"]))
    if not Path(asset["data"]["path"]).exists():
        raise HTTPException(410, "media_expired")
    limit(c, "analysis-retry:" + u["id"], 10)
    c.execute(
        jobs.update()
        .where(jobs.c.id == id)
        .values(status="queued", attempts=0, error=None, lease=None)
    )
    audit(c, u["id"], "analysis_retry", id)
