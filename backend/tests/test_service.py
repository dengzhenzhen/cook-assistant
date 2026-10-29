"""Exercise the real scheduler through the HTTP boundary."""
from pathlib import Path
import json

from fastapi.testclient import TestClient
from service.app import app

client = TestClient(app)
ROOT = Path(__file__).resolve().parents[2]


def dinner():
    return json.loads((ROOT / "examples" / "dinner.json").read_text())


def test_serves_mobile_prototype_and_health():
    assert client.get("/").status_code == 200
    assert "开饭" in client.get("/").text
    assert client.get("/api/health").json()["scheduler"] == "OR-Tools CP-SAT"
    assert client.get("/app.js").status_code == 200
    assert client.get("/project-plan").status_code == 200


def test_generate_returns_real_resource_constrained_plan():
    response = client.post("/api/v1/plans/generate", json=dinner())
    assert response.status_code == 200
    plan = response.json()
    assert len(plan["tasks"]) == len(dinner()["tasks"])
    assert plan["allocations"]
    assert plan["lateness_seconds"] == 0


def test_resource_shortage_is_actionable_conflict():
    data = dinner()
    data["capacities"]["wok"] = 0
    response = client.post("/api/v1/plans/generate", json=data)
    assert response.status_code == 409
    assert "wok" in response.json()["detail"]


def test_bad_dependency_is_validation_error():
    data = dinner()
    data["tasks"][0]["dependencies"] = ["missing"]
    assert client.post("/api/v1/plans/generate", json=data).status_code == 422


def test_recalculate_preserves_completed_and_running_tasks():
    data = dinner()
    data["now_seconds"] = 200
    data["execution"] = [
        {"task_id": "rice_wash", "actual_start": 0, "actual_end": 130},
        {"task_id": "rice_cook", "actual_start": 130, "remaining_seconds": 1700},
    ]
    response = client.post("/api/v1/plans/recalculate", json=data)
    assert response.status_code == 200
    tasks = {t["task_id"]: t for t in response.json()["tasks"]}
    assert tasks["rice_wash"]["end_seconds"] == 130
    assert tasks["rice_cook"]["start_seconds"] == 130
    assert tasks["rice_cook"]["end_seconds"] == 1900
    assert all(t["start_seconds"] >= 200 for t in tasks.values() if t["status"] == "pending")


def test_request_bounds_and_busy_response(monkeypatch):
    data = dinner()
    data["tasks"][0]["duration_seconds"] = 86401
    assert client.post("/api/v1/plans/generate", json=data).status_code == 422
    class Busy:
        def acquire(self, blocking=False):
            return False
    monkeypatch.setattr("service.app.solvers", Busy())
    assert client.post("/api/v1/plans/generate", json=dinner()).status_code == 503
