"""One-service Railway deployment runs a durable DB worker alongside the API."""

import logging, shutil, threading, time
from sqlalchemy import select, func
from .db import worker_heartbeats, jobs, now, uid
from .worker import run_one, cleanup


def heartbeat(engine, id):
    with engine.begin() as c:
        row = c.execute(
            select(worker_heartbeats.c.id).where(worker_heartbeats.c.id == id)
        ).first()
        if row:
            c.execute(
                worker_heartbeats.update()
                .where(worker_heartbeats.c.id == id)
                .values(updated=now())
            )
        else:
            c.execute(worker_heartbeats.insert().values(id=id, updated=now()))
        c.execute(
            worker_heartbeats.delete().where(
                worker_heartbeats.c.updated < now() - 86400
            )
        )


def status(engine):
    with engine.connect() as c:
        stamp = c.execute(select(func.max(worker_heartbeats.c.updated))).scalar()
        queued = c.execute(
            select(func.count()).select_from(jobs).where(jobs.c.status == "queued")
        ).scalar_one()
    return {
        "worker_online": bool(stamp and stamp > now() - 300),
        "ffmpeg_available": bool(shutil.which("ffmpeg")),
        "queued": queued,
        "last_heartbeat": stamp,
    }


def worker_loop(engine, media, stop):
    id = uid()
    last = 0
    try:
        while not stop.is_set():
            try:
                heartbeat(engine, id)
                if now() - last > 3600:
                    cleanup(engine, media)
                    last = now()
                if not run_one(engine):
                    stop.wait(2)
            except Exception as error:
                logging.error("worker_cycle_failed category=%s", type(error).__name__)
                stop.wait(5)
    finally:
        with engine.begin() as c:
            c.execute(worker_heartbeats.delete().where(worker_heartbeats.c.id == id))
