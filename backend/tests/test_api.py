import hashlib
import io
import wave
import numpy as np
import pyotp
import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from app.main import create_app
from app.db import users, uid, policy, one, objects, jobs, add, now
from app.security import ph, verify
from app.worker import run_one, cleanup
from app.acoustics import evaluate, Rejected


@pytest.fixture
def env(tmp_path):
    key = Fernet.generate_key().decode()
    app = create_app(
        "sqlite:///" + str(tmp_path / "test.db"),
        tmp_path / "media",
        {"secret": "x" * 64, "key": key},
        testing=True,
    )
    otp = pyotp.random_base32()
    ids = {}
    with app.state.engine.begin() as c:
        for name, role in [
            ("alice", "user"),
            ("bob", "user"),
            ("admin", "super_admin"),
            ("teacher", "teacher"),
        ]:
            ids[name] = uid()
            c.execute(
                users.insert().values(
                    id=ids[name],
                    username=name,
                    name=name,
                    password=ph.hash("VerySafePass123!"),
                    role=role,
                    totp=Fernet(key.encode()).encrypt(otp.encode()).decode()
                    if name == "admin"
                    else None,
                )
            )
    with TestClient(app) as client:

        def login(name):
            r = client.post(
                "/v1/auth/login",
                json={
                    "username": name,
                    "password": "VerySafePass123!",
                    "otp": pyotp.TOTP(otp).now() if name == "admin" else "",
                },
            )
            assert r.status_code == 200, r.text
            return r.json()

        yield app, client, ids, login, otp
    app.state.engine.dispose()


def auth(token):
    return {"Authorization": "Bearer " + token["access_token"]}


def audio():
    b = io.BytesIO()
    with wave.open(b, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        t = np.arange(96000) / 16000
        w.writeframes((np.sin(2 * np.pi * 220 * t) * 6000).astype("<i2").tobytes())
    return b.getvalue()


def upload(client, token, data=None):
    data = data or audio()
    sha = hashlib.sha256(data).hexdigest()
    headers = auth(token)
    r = client.post(
        "/v1/uploads",
        headers=headers,
        json={
            "recording_id": uid(),
            "size": len(data),
            "sha256": sha,
            "mime": "audio/wav",
        },
    )
    assert r.status_code == 201, r.text
    id = r.json()["id"]
    h = {
        **headers,
        "Content-Range": f"bytes 0-{len(data) - 1}/{len(data)}",
        "X-Chunk-Sha256": sha,
        "Content-Type": "application/octet-stream",
    }
    assert (
        client.put(
            "/v1/uploads/" + id + "/chunks/0", headers=h, content=data
        ).status_code
        == 204
    )
    assert (
        client.put(
            "/v1/uploads/" + id + "/chunks/0", headers=h, content=data
        ).status_code
        == 204
    )
    r = client.post(
        "/v1/uploads/" + id + "/complete", headers=headers, json={"sha256": sha}
    )
    assert r.status_code == 200, r.text
    assert (
        client.post(
            "/v1/uploads/" + id + "/complete", headers=headers, json={"sha256": sha}
        ).json()
        == r.json()
    )
    return r.json()["asset_id"], id


def test_roles_and_otp(env):
    app, c, ids, login, otp = env
    a = login("alice")
    admin = login("admin")
    assert c.get("/v1/admin/users", headers=auth(a)).status_code == 403
    assert c.get("/v1/admin/users", headers=auth(admin)).status_code == 200
    assert (
        c.post(
            "/v1/auth/login",
            json={
                "username": "admin",
                "password": "VerySafePass123!",
                "otp": pyotp.TOTP(otp).now(),
            },
        ).status_code
        == 401
    )
    assert (
        c.post(
            "/v1/auth/register",
            json={
                "username": "test",
                "name": "Test",
                "password": "VerySafePass123!",
                "role": "super_admin",
            },
        ).status_code
        == 422
    )


def test_refresh_replay_revokes(env):
    _, c, _, login, _ = env
    a = login("alice")
    b = c.post("/v1/auth/refresh", json={"refresh_token": a["refresh_token"]})
    assert b.status_code == 200
    assert (
        c.post(
            "/v1/auth/refresh", json={"refresh_token": a["refresh_token"]}
        ).status_code
        == 401
    )
    assert c.get("/v1/auth/me", headers=auth(b.json())).status_code == 401


def test_logout_revokes_access(env):
    _, c, _, login, _ = env
    a = login("alice")
    assert c.post("/v1/auth/logout", headers=auth(a)).status_code == 204
    assert c.get("/v1/auth/me", headers=auth(a)).status_code == 401


def test_lockout_persists(env):
    _, c, _, _, _ = env
    for _ in range(5):
        assert (
            c.post(
                "/v1/auth/login", json={"username": "alice", "password": "wrong"}
            ).status_code
            == 401
        )
    assert (
        c.post(
            "/v1/auth/login", json={"username": "alice", "password": "VerySafePass123!"}
        ).status_code
        == 429
    )


def test_upload_idor_and_worker(env):
    app, c, _, login, _ = env
    a = login("alice")
    b = login("bob")
    asset, up = upload(c, a)
    assert c.get("/v1/uploads/" + up, headers=auth(b)).status_code == 404
    assert c.get("/v1/assets/" + asset + "/content", headers=auth(b)).status_code == 404
    data = {
        "asset_id": asset,
        "school": "xorazm",
        "locale": "uz",
        "reference_id": None,
        "consent_version": "analysis-v1",
    }
    h = {**auth(a), "Idempotency-Key": "job-once-001"}
    r = c.post("/v1/analyses", headers=h, json=data)
    assert r.status_code == 202, r.text
    assert c.post("/v1/analyses", headers=h, json=data).json() == r.json()
    assert (
        c.post(
            "/v1/analyses", headers=h, json={**data, "school": "surxondaryo"}
        ).status_code
        == 409
    )
    assert (
        c.post(
            "/v1/analyses",
            headers={**auth(b), "Idempotency-Key": "job-once-002"},
            json=data,
        ).status_code
        == 404
    )
    assert run_one(app.state.engine)
    job = c.get("/v1/analyses/" + r.json()["job_id"], headers=auth(a)).json()
    assert job["status"] == "completed", job
    report = c.get("/v1/reports/latest", headers=auth(a)).json()
    assert len(report["metrics"]) == 5 and all(
        m["score"] is None for m in report["metrics"]
    )
    assert not report["demo"]
    assert c.get("/v1/reports/" + report["id"], headers=auth(b)).status_code == 404


def test_policy_concurrency(env):
    _, c, _, login, _ = env
    a = login("admin")
    p = c.get("/v1/config").json()
    assert (
        c.put(
            "/v1/admin/policy", headers=auth(a), json={**p, "registration": True}
        ).status_code
        == 204
    )
    assert c.put("/v1/admin/policy", headers=auth(a), json=p).status_code == 409


def test_group_teacher_acl(env):
    app, c, ids, login, _ = env
    teacher = login("teacher")
    admin = login("admin")
    with app.state.engine.begin() as db:
        rid = add(db, "report", ids["alice"], {"id": "fake"})
    assert (
        c.post(
            f"/v1/reports/{rid}/reviews",
            headers=auth(teacher),
            json={"score": 85, "note": "Clear phrase"},
        ).status_code
        == 403
    )
    g = c.post(
        "/v1/admin/groups",
        headers=auth(admin),
        json={"title": "Practice group", "teacher_id": ids["teacher"]},
    ).json()["id"]
    assert (
        c.post(
            f"/v1/admin/groups/{g}/members",
            headers=auth(admin),
            json={"user_id": ids["alice"]},
        ).status_code
        == 204
    )
    assert (
        c.post(
            f"/v1/reports/{rid}/reviews",
            headers=auth(teacher),
            json={"score": 85, "note": "Clear phrase"},
        ).status_code
        == 201
    )


def test_delete_and_cleanup(env):
    app, c, ids, login, _ = env
    a = login("alice")
    asset, _ = upload(c, a)
    assert (
        c.put(
            "/v1/research-consent", headers=auth(a), json={"enabled": True}
        ).status_code
        == 204
    )
    assert c.post("/v1/delete-account", headers=auth(a)).status_code == 202
    assert c.get("/v1/auth/me", headers=auth(a)).status_code == 401
    cleanup(app.state.engine, app.state.media)
    from pathlib import Path

    with app.state.engine.begin() as db:
        row = one(db, objects, objects.c.id == asset)
        assert not Path(row["data"]["path"]).exists()
    assert not verify("anything", "disabled")


def test_checksum_rejection(env):
    _, c, _, login, _ = env
    a = login("alice")
    data = audio()
    sha = hashlib.sha256(data).hexdigest()
    up = c.post(
        "/v1/uploads",
        headers=auth(a),
        json={
            "recording_id": uid(),
            "size": len(data),
            "sha256": sha,
            "mime": "audio/wav",
        },
    ).json()["id"]
    h = {
        **auth(a),
        "Content-Range": f"bytes 0-{len(data) - 1}/{len(data)}",
        "X-Chunk-Sha256": "0" * 64,
    }
    assert (
        c.put(f"/v1/uploads/{up}/chunks/0", headers=h, content=data).status_code == 422
    )
    assert c.get("/v1/uploads/" + up, headers=auth(a)).json()["offset"] == 0


def test_reference_baseline_and_silence(tmp_path):
    f = tmp_path / "voice.wav"
    f.write_bytes(audio())
    r = evaluate(
        str(f),
        str(f),
        uid(),
        {
            "locale": "en",
            "school": "xorazm",
            "reference_id": "ref",
            "asset_id": "asset",
        },
    )
    assert r["metrics"][0]["score"] > 95
    assert all(m["score"] is None for m in r["metrics"][2:])
    with wave.open(str(tmp_path / "silence.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\0" * 192000)
    with pytest.raises(Rejected, match="audio_too_quiet"):
        evaluate(
            str(tmp_path / "silence.wav"),
            None,
            uid(),
            {
                "locale": "uz",
                "school": "xorazm",
                "reference_id": None,
                "asset_id": "asset",
            },
        )


def test_playlist_cannot_access_local_paths(tmp_path):
    from app.acoustics import decode

    path = tmp_path / "fake.wav"
    path.write_text("ffconcat version 1.0\nfile /etc/passwd\n")
    with pytest.raises(Rejected, match="unsupported_container"):
        decode(str(path))
