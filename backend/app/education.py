import math
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import Field
from .db import users, objects, one, obj, add, now
from .security import db, current, admin
from .schemas import Body
from .learning import listing
from .runtime import status
from .seed import seed_demo, key

r = APIRouter(prefix="/v1")


class Quiz(Body):
    answers: list[int] = Field(min_length=1, max_length=30)


class Publish(Body):
    published: bool


@r.get("/system/status")
def system(request: Request, u=Depends(current)):
    return {"version": "0.3.1", **status(request.app.state.engine)}


@r.get("/lessons")
def lessons(u=Depends(current), c=Depends(db)):
    progress = {
        x["data"]["lesson_id"]: x["data"]
        for x in listing(c, "lesson_progress", u["id"])
    }
    result = []
    for x in listing(c, "lesson"):
        if not x["data"]["published"]:
            continue
        d = {**x["data"], "id": x["id"], "progress": progress.get(x["id"])}
        d["questions"] = [
            {k: v for k, v in q.items() if k != "answer"} for q in d["questions"]
        ]
        result.append(d)
    return sorted(result, key=lambda x: x.get("order", 0))


@r.post("/lessons/{id}/quiz")
def quiz(id: str, b: Quiz, u=Depends(current), c=Depends(db)):
    lesson = obj(c, id, "lesson")
    if not lesson or not lesson["data"]["published"]:
        raise HTTPException(404, "lesson_not_found")
    questions = lesson["data"]["questions"]
    if len(b.answers) != len(questions) or any(
        a < 0 or a >= len(q["options"]) for a, q in zip(b.answers, questions)
    ):
        raise HTTPException(422, "invalid_answers")
    correct = sum(a == q["answer"] for a, q in zip(b.answers, questions))
    score = round(100 * correct / len(questions))
    one(c, users, users.c.id == u["id"], True)
    pid = key("progress:" + u["id"] + ":" + id)
    old = obj(c, pid, "lesson_progress", u["id"])
    result = {
        "lesson_id": id,
        "score": score,
        "best_score": max(score, old["data"]["best_score"] if old else 0),
        "completed": score >= 70 or bool(old and old["data"]["completed"]),
        "attempts": 1 + (old["data"]["attempts"] if old else 0),
        "updated": now(),
    }
    if old:
        c.execute(objects.update().where(objects.c.id == pid).values(data=result))
    else:
        add(c, "lesson_progress", u["id"], result, pid)
    return {
        **result,
        "correct": correct,
        "total": len(questions),
        "review": [
            {"correct": a == q["answer"], "correct_option": q["options"][q["answer"]]}
            for a, q in zip(b.answers, questions)
        ],
    }


@r.get("/dashboard")
def dashboard(u=Depends(current), c=Depends(db)):
    progress = listing(c, "lesson_progress", u["id"])
    practice = listing(c, "practice", u["id"])
    reports = listing(c, "report", u["id"])
    completed = {x["data"]["lesson_id"] for x in progress if x["data"]["completed"]}
    available = sorted(
        [x for x in listing(c, "lesson") if x["data"]["published"]],
        key=lambda x: x["data"].get("order", 0),
    )
    next_lesson = next(
        (
            {
                "id": x["id"],
                "title": x["data"]["title"],
                "minutes": x["data"]["minutes"],
            }
            for x in available
            if x["id"] not in completed
        ),
        None,
    )
    return {
        "name": u["name"],
        "completed_lessons": len(completed & {x["id"] for x in available}),
        "total_lessons": len(available),
        "practice_minutes": sum(x["data"]["minutes"] for x in practice),
        "reports": len(reports),
        "next_lesson": next_lesson,
    }


@r.get("/admin/lessons")
def admin_lessons(u=Depends(admin), c=Depends(db)):
    return [{"id": x["id"], **x["data"]} for x in listing(c, "lesson")]


@r.patch("/admin/lessons/{id}", status_code=204)
def publish(id: str, b: Publish, u=Depends(admin), c=Depends(db)):
    x = obj(c, id, "lesson", lock=True)
    if not x:
        raise HTTPException(404, "lesson_not_found")
    c.execute(
        objects.update()
        .where(objects.c.id == id)
        .values(data={**x["data"], "published": b.published})
    )
