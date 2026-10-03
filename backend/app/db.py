"""PostgreSQL in deployment; SQLite only for local tests."""

import time, uuid
from sqlalchemy import (
    MetaData,
    Table,
    Column,
    String,
    Text,
    Integer,
    Boolean,
    JSON,
    ForeignKey,
    UniqueConstraint,
    create_engine,
    select,
    event,
)

metadata = MetaData()


def uid():
    return uuid.uuid4().hex


def now():
    return int(time.time())


users = Table(
    "users",
    metadata,
    Column("id", String(32), primary_key=True),
    Column("username", String(120), unique=True, nullable=False),
    Column("name", String(160), nullable=False),
    Column("password", Text, nullable=False),
    Column("role", String(20), nullable=False),
    Column("active", Boolean, nullable=False, default=True),
    Column("totp", Text),
    Column("totp_step", Integer, nullable=False, default=-1),
    Column("failures", Integer, nullable=False, default=0),
    Column("locked_until", Integer, nullable=False, default=0),
)
sessions = Table(
    "sessions",
    metadata,
    Column("id", String(32), primary_key=True),
    Column("owner", ForeignKey("users.id"), nullable=False, index=True),
    Column("hash", String(64), unique=True, nullable=False),
    Column("previous", String(64), index=True),
    Column("expires", Integer, nullable=False),
    Column("revoked", Boolean, default=False, nullable=False),
)
objects = Table(
    "objects",
    metadata,
    Column("id", String(32), primary_key=True),
    Column("kind", String(30), nullable=False, index=True),
    Column("owner", ForeignKey("users.id"), nullable=False, index=True),
    Column("data", JSON, nullable=False),
    Column("created", Integer, nullable=False, default=now),
    Column("version", Integer, nullable=False, default=1),
)
uploads = Table(
    "uploads",
    metadata,
    Column("id", String(32), primary_key=True),
    Column("owner", ForeignKey("users.id"), nullable=False),
    Column("recording_id", String(100), nullable=False),
    Column("size", Integer, nullable=False),
    Column("sha256", String(64), nullable=False),
    Column("mime", String(30), nullable=False),
    Column("offset", Integer, nullable=False, default=0),
    Column("asset_id", String(32)),
    Column("created", Integer, nullable=False, default=now),
    UniqueConstraint("owner", "recording_id"),
)
jobs = Table(
    "jobs",
    metadata,
    Column("id", String(32), primary_key=True),
    Column("owner", ForeignKey("users.id"), nullable=False, index=True),
    Column("idem", String(200), nullable=False),
    Column("digest", String(64), nullable=False),
    Column("data", JSON, nullable=False),
    Column("status", String(20), nullable=False, default="queued", index=True),
    Column("lease", String(32)),
    Column("lease_until", Integer, nullable=False, default=0),
    Column("attempts", Integer, nullable=False, default=0),
    Column("error", String(100)),
    Column("report_id", String(32)),
    Column("created", Integer, nullable=False, default=now),
    UniqueConstraint("owner", "idem"),
)
policy = Table(
    "policy",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("data", JSON, nullable=False),
    Column("version", Integer, nullable=False),
)
rates = Table(
    "rates",
    metadata,
    Column("id", String(64), primary_key=True),
    Column("count", Integer, nullable=False),
    Column("window", Integer, nullable=False),
)


def connect(url):
    e = create_engine(
        url,
        pool_pre_ping=True,
        connect_args={"check_same_thread": False} if url.startswith("sqlite") else {},
    )
    if url.startswith("sqlite"):

        @event.listens_for(e, "connect")
        def setup(c, _):
            c.execute("PRAGMA foreign_keys=ON")
            c.execute("PRAGMA busy_timeout=10000")

    return e


def initialize(engine):
    metadata.create_all(engine)
    with engine.begin() as c:
        if c.execute(select(policy)).first() is None:
            c.execute(
                policy.insert().values(
                    id=1,
                    version=1,
                    data={
                        "registration": False,
                        "maintenance": False,
                        "banner": "",
                        "retention_days": 30,
                        "daily_job_limit": 20,
                        "minimum_app_version": "0.2.0",
                    },
                )
            )


def one(c, table, where, lock=False):
    q = select(table).where(where)
    return c.execute(q.with_for_update() if lock else q).mappings().first()


def obj(c, identifier, kind=None, owner=None, lock=False):
    row = one(c, objects, objects.c.id == identifier, lock)
    if (
        row is None
        or (kind and row["kind"] != kind)
        or (owner and row["owner"] != owner)
    ):
        return None
    return row


def add(c, kind, owner, data, identifier=None):
    identifier = identifier or uid()
    c.execute(objects.insert().values(id=identifier, kind=kind, owner=owner, data=data))
    return identifier


def audit(c, actor, action, target, detail=None):
    add(c, "audit", actor, {"action": action, "target": target, "detail": detail or {}})
