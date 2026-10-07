import os, time, logging, shutil
from pathlib import Path
from sqlalchemy import select, or_
from .db import connect, jobs, objects, users, uploads, policy, one, obj, add, now, uid
from .acoustics import evaluate, Rejected


def run_one(engine):
    with engine.begin() as c:
        row = (
            c.execute(
                select(jobs)
                .where(
                    or_(
                        jobs.c.status == "queued",
                        (jobs.c.status == "running") & (jobs.c.lease_until < now()),
                    )
                )
                .order_by(jobs.c.created)
                .with_for_update(skip_locked=True)
                .limit(1)
            )
            .mappings()
            .first()
        )
        if not row:
            return False
        if row["attempts"] >= 3:
            c.execute(
                jobs.update()
                .where(jobs.c.id == row["id"])
                .values(status="failed", error="attempt_limit")
            )
            return True
        id = row["id"]
        lease = uid()
        data = row["data"]
        owner = row["owner"]
        c.execute(
            jobs.update()
            .where(jobs.c.id == id)
            .values(
                status="running",
                lease=lease,
                lease_until=now() + 600,
                attempts=row["attempts"] + 1,
            )
        )
        source_asset = obj(c, data["asset_id"], "asset")
        source = source_asset["data"]["path"] if source_asset else ""
        reference = None
        invalid = False
        if data["reference_id"]:
            ref = obj(c, data["reference_id"], "reference")
            invalid = (
                not ref
                or not ref["data"]["active"]
                or ref["data"]["license_until"] < now()
            )
            if ref:
                ref_asset = obj(c, ref["data"]["asset_id"], "asset")
                if ref_asset:
                    reference = ref_asset["data"]["path"]
                else:
                    invalid = True
    try:
        if invalid:
            raise Rejected("reference_unavailable")
        rid = uid()
        result = evaluate(source, reference, rid, data)
        if data.get("reference_id") and ref:
            result["reference_label"] = ref["data"].get("title", "")
            result["technical_reference"] = ref["data"].get("technical_demo", False)
        with engine.begin() as c:
            current = one(c, jobs, jobs.c.id == id, True)
            if (
                not current
                or current["lease"] != lease
                or current["status"] != "running"
            ):
                return True
            if not one(c, users, users.c.id == owner)["active"]:
                c.execute(
                    jobs.update()
                    .where(jobs.c.id == id)
                    .values(status="cancelled", lease=None)
                )
                return True
            add(c, "report", owner, result, rid)
            c.execute(
                jobs.update()
                .where(jobs.c.id == id)
                .values(status="completed", report_id=rid, lease=None, error=None)
            )
    except Exception as e:
        with engine.begin() as c:
            c.execute(
                jobs.update()
                .where(
                    jobs.c.id == id, jobs.c.lease == lease, jobs.c.status == "running"
                )
                .values(
                    status="failed",
                    lease=None,
                    error=str(e) if isinstance(e, Rejected) else "processing_failed",
                )
            )
        logging.warning("job_failed id=%s category=%s", id, type(e).__name__)
    return True


def cleanup(engine, media):
    with engine.begin() as c:
        retention = one(c, policy, policy.c.id == 1)["data"]["retention_days"]
        deleted = {
            x["id"]
            for x in c.execute(
                select(users).where(
                    users.c.username.like("deleted-%"), users.c.active == False
                )
            ).mappings()
        }
        refs = (
            c.execute(select(objects).where(objects.c.kind == "reference"))
            .mappings()
            .all()
        )
        protected = {
            x["data"]["asset_id"] for x in refs if x["data"]["license_until"] > now()
        }
        active = (
            c.execute(select(jobs).where(jobs.c.status.in_(["queued", "running"])))
            .mappings()
            .all()
        )
        protected |= {x["data"]["asset_id"] for x in active}
        active_refs = {x["data"].get("reference_id") for x in active}
        protected |= {x["data"]["asset_id"] for x in refs if x["id"] in active_refs}
        for x in (
            c.execute(select(objects).where(objects.c.kind == "asset")).mappings().all()
        ):
            if x["id"] not in protected and (
                x["created"] < now() - retention * 86400 or x["owner"] in deleted
            ):
                Path(x["data"]["path"]).unlink(missing_ok=True)
                for up in (
                    c.execute(select(uploads).where(uploads.c.asset_id == x["id"]))
                    .mappings()
                    .all()
                ):
                    shutil.rmtree(media / "chunks" / up["id"], ignore_errors=True)
                    c.execute(uploads.delete().where(uploads.c.id == up["id"]))
        for up in (
            c.execute(
                select(uploads).where(
                    uploads.c.asset_id == None, uploads.c.created < now() - 604800
                )
            )
            .mappings()
            .all()
        ):
            shutil.rmtree(media / "chunks" / up["id"], ignore_errors=True)
            c.execute(uploads.delete().where(uploads.c.id == up["id"]))
        if deleted:
            reports = {
                x["id"]
                for x in c.execute(
                    select(objects).where(
                        objects.c.kind == "report", objects.c.owner.in_(deleted)
                    )
                ).mappings()
            }
            for x in (
                c.execute(
                    select(objects).where(
                        objects.c.kind.in_(["review", "member", "submission"])
                    )
                )
                .mappings()
                .all()
            ):
                if (
                    x["data"].get("report_id") in reports
                    or x["data"].get("user_id") in deleted
                ):
                    c.execute(objects.delete().where(objects.c.id == x["id"]))
            c.execute(
                objects.delete().where(
                    objects.c.owner.in_(deleted),
                    objects.c.kind.in_(["report", "practice", "consent", "submission"]),
                )
            )


if __name__ == "__main__":
    import threading
    from .db import initialize
    from .runtime import worker_loop

    engine = connect(os.environ["DATABASE_URL"])
    initialize(engine)
    worker_loop(
        engine, Path(os.environ.get("MEDIA_ROOT", "./media")), threading.Event()
    )
