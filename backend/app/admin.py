import csv, io, hmac, hashlib
from fastapi import APIRouter, Depends, Request, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy import select, func
from .db import users, sessions, objects, jobs, policy, one, obj, add, audit, now, uid
from .security import db, admin, ph
from .media import require
from .learning import listing, serialize
from . import schemas as S

r = APIRouter(prefix="/v1/admin", dependencies=[Depends(admin)])


@r.get("/stats")
def stats(c=Depends(db)):
    count = lambda t: c.execute(select(func.count()).select_from(t)).scalar_one()
    return {
        "users": count(users),
        "reports": len(listing(c, "report")),
        "references": len(listing(c, "reference")),
        "jobs": dict(
            c.execute(select(jobs.c.status, func.count()).group_by(jobs.c.status)).all()
        ),
    }


@r.get("/users")
def user_list(
    offset: int = Query(0, ge=0), limit: int = Query(200, ge=1, le=200), c=Depends(db)
):
    return [
        {k: x[k] for k in ["id", "username", "name", "role", "active"]}
        for x in c.execute(
            select(users).order_by(users.c.username).offset(offset).limit(limit)
        ).mappings()
    ]


@r.post("/users", status_code=201)
def user_create(b: S.Register, u=Depends(admin), c=Depends(db)):
    if one(c, users, users.c.username == b.username.lower()):
        raise HTTPException(409, "username_exists")
    id = uid()
    c.execute(
        users.insert().values(
            id=id,
            name=b.name,
            username=b.username.lower(),
            password=ph.hash(b.password),
            role="user",
        )
    )
    audit(c, u["id"], "user_created", id)
    return {"id": id}


@r.patch("/users/{id}", status_code=204)
def user_patch(id: str, b: S.UserPatch, u=Depends(admin), c=Depends(db)):
    x = require(one(c, users, users.c.id == id, True))
    if x["role"] == "super_admin":
        raise HTTPException(409, "protected_admin")
    c.execute(users.update().where(users.c.id == id).values(**b.model_dump()))
    c.execute(sessions.update().where(sessions.c.owner == id).values(revoked=True))
    audit(c, u["id"], "user_updated", id, b.model_dump())


@r.post("/users/{id}/revoke", status_code=204)
def revoke(id: str, u=Depends(admin), c=Depends(db)):
    c.execute(sessions.update().where(sessions.c.owner == id).values(revoked=True))
    audit(c, u["id"], "sessions_revoked", id)


@r.put("/policy", status_code=204)
def update_policy(b: S.Policy, u=Depends(admin), c=Depends(db)):
    p = one(c, policy, policy.c.id == 1, True)
    if p["version"] != b.version:
        raise HTTPException(409, "stale_version")
    c.execute(
        policy.update()
        .where(policy.c.id == 1)
        .values(data=b.model_dump(exclude={"version"}), version=b.version + 1)
    )
    audit(c, u["id"], "policy_updated", "policy")


@r.get("/references")
def references(c=Depends(db)):
    return [serialize(x) for x in listing(c, "reference")]


def reference_values(c, b, u):
    require(obj(c, b.asset_id, "asset", u["id"]))
    if b.active and b.license_until < now():
        raise HTTPException(422, "license_expired")
    return b.model_dump()


@r.post("/references", status_code=201)
def reference(b: S.Reference, u=Depends(admin), c=Depends(db)):
    id = add(c, "reference", u["id"], reference_values(c, b, u))
    audit(c, u["id"], "reference_created", id)
    return {"id": id}


@r.put("/references/{id}", status_code=204)
def reference_edit(id: str, b: S.Reference, u=Depends(admin), c=Depends(db)):
    x = require(obj(c, id, "reference", lock=True))
    data = reference_values(c, b, u)
    if x["data"].get("technical_demo"):
        data["technical_demo"] = True
    c.execute(
        objects.update()
        .where(objects.c.id == id)
        .values(data=data, version=x["version"] + 1)
    )
    audit(c, u["id"], "reference_updated", id)


@r.get("/contents")
def contents(c=Depends(db)):
    return [serialize(x) for x in listing(c, "content")]


@r.post("/contents", status_code=201)
def content(b: S.Content, u=Depends(admin), c=Depends(db)):
    id = add(c, "content", u["id"], b.model_dump())
    audit(c, u["id"], "content_created", id)
    return {"id": id}


@r.put("/contents/{id}", status_code=204)
def content_edit(id: str, b: S.Content, u=Depends(admin), c=Depends(db)):
    x = require(obj(c, id, "content", lock=True))
    c.execute(
        objects.update()
        .where(objects.c.id == id)
        .values(data=b.model_dump(), version=x["version"] + 1)
    )
    audit(c, u["id"], "content_updated", id)


@r.get("/jobs")
def all_jobs(c=Depends(db)):
    return [
        dict(x)
        for x in c.execute(
            select(jobs).order_by(jobs.c.created.desc()).limit(200)
        ).mappings()
    ]


@r.post("/jobs/{id}/{action}", status_code=204)
def job_action(id: str, action: str, u=Depends(admin), c=Depends(db)):
    x = require(one(c, jobs, jobs.c.id == id, True))
    if action == "retry" and x["status"] in ["failed", "cancelled"]:
        if not one(c, users, users.c.id == x["owner"])["active"]:
            raise HTTPException(409, "inactive_owner")
        c.execute(
            jobs.update()
            .where(jobs.c.id == id)
            .values(status="queued", error=None, attempts=0, lease=None)
        )
    elif action == "cancel" and x["status"] in ["queued", "running"]:
        c.execute(
            jobs.update().where(jobs.c.id == id).values(status="cancelled", lease=None)
        )
    else:
        raise HTTPException(409, "invalid_job_action")
    audit(c, u["id"], "job_" + action, id)


@r.get("/reports")
def all_reports(c=Depends(db)):
    return [
        {"id": x["id"], "owner": x["owner"], "data": x["data"]}
        for x in listing(c, "report")
    ]


@r.get("/audit")
def audits(c=Depends(db)):
    return [serialize(x) for x in listing(c, "audit")]


@r.get("/groups")
def groups(c=Depends(db)):
    return [serialize(x) for x in listing(c, "group")]


@r.post("/groups", status_code=201)
def group(b: S.Group, u=Depends(admin), c=Depends(db)):
    teacher = require(one(c, users, users.c.id == b.teacher_id))
    if teacher["role"] not in ["teacher", "super_admin"]:
        raise HTTPException(422, "teacher_required")
    id = add(c, "group", u["id"], b.model_dump())
    audit(c, u["id"], "group_created", id)
    return {"id": id}


@r.post("/groups/{id}/members", status_code=204)
def member(id: str, b: S.Member, u=Depends(admin), c=Depends(db)):
    require(obj(c, id, "group", lock=True))
    require(one(c, users, users.c.id == b.user_id))
    if not any(
        x["data"] == {"group_id": id, "user_id": b.user_id}
        for x in listing(c, "member")
    ):
        add(c, "member", u["id"], {"group_id": id, "user_id": b.user_id})
    audit(c, u["id"], "member_added", id)


@r.post("/groups/{id}/assignments", status_code=201)
def assignment(id: str, b: S.Assignment, u=Depends(admin), c=Depends(db)):
    require(obj(c, id, "group"))
    aid = add(c, "assignment", u["id"], {**b.model_dump(), "group_id": id})
    audit(c, u["id"], "assignment_created", aid)
    return {"id": aid}


@r.get("/research.csv")
def research(request: Request, u=Depends(admin), c=Depends(db)):
    allowed = {x["owner"] for x in listing(c, "consent") if x["data"]["enabled"]}
    stream = io.StringIO()
    writer = csv.writer(stream)
    writer.writerow(
        [
            "participant",
            "created",
            "school",
            "model",
            "pitch",
            "rhythm",
            "breath",
            "resonance",
            "style",
        ]
    )
    for x in listing(c, "report"):
        if x["owner"] not in allowed:
            continue
        id = hmac.new(
            request.app.state.settings["secret"].encode(),
            x["owner"].encode(),
            hashlib.sha256,
        ).hexdigest()[:20]
        scores = {m["kind"]: m["score"] for m in x["data"]["metrics"]}
        writer.writerow(
            [
                id,
                x["created"],
                x["data"]["school"],
                x["data"]["model_version"],
                *[
                    scores[k]
                    for k in ["pitch", "rhythm", "breath", "resonance", "style"]
                ],
            ]
        )
    audit(c, u["id"], "research_export", "consented_reports")
    return Response(stream.getvalue(), media_type="text/csv")
