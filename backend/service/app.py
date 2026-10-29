"""Authenticated cooking service, scheduling API and retained HTML prototype."""
from pathlib import Path
from threading import BoundedSemaphore

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from .lifecycle import lifespan
from .config import get_settings
from .api import catalog, ai
from . import auth
from .api import sessions, offline

from cook_scheduler import Plan, Request, SchedulingError, generate_plan

ROOT = Path(__file__).resolve().parents[2]
FRONTEND = ROOT / "frontend"
app = FastAPI(title="开饭 · 烹饪助手", version="0.4.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware,allow_origins=get_settings().cors_origins,allow_methods=["GET","POST","PUT","DELETE"],allow_headers=["Content-Type","Authorization"])
app.include_router(catalog.router)
app.include_router(ai.router)
app.include_router(auth.router)
app.include_router(sessions.router)
app.include_router(offline.router)
solvers = BoundedSemaphore(2)


@app.get("/api/health")
def health():
    return {"status": "ok", "scheduler": "OR-Tools CP-SAT", "mode": "local-development"}


@app.post("/api/v1/plans/generate", response_model=Plan)
@app.post("/api/v1/plans/recalculate", response_model=Plan)
def schedule(request: Request):
    """Generate or recalculate using the same Request contract as the CLI."""
    if len(request.tasks) > 100 or len(request.holds) > 200:
        raise HTTPException(422, "原型最多支持 100 个任务、200 段资源占用。")
    if max(request.now_seconds, request.target_finish_seconds or 0) > 604800:
        raise HTTPException(422, "原型仅支持一周内的相对时间。")
    if any(t.duration_seconds > 86400 for t in request.tasks) or any(
        (s.remaining_seconds or 0) > 86400 for s in request.execution
    ):
        raise HTTPException(422, "单个任务的时长或剩余时间不能超过 24 小时。")
    if not solvers.acquire(blocking=False):
        raise HTTPException(503, "调度器正忙，请稍后重试。")
    try:
        return generate_plan(request, time_limit_seconds=3)
    except SchedulingError as exc:
        raise HTTPException(409, str(exc)) from exc
    finally:
        solvers.release()


@app.get("/project-plan", include_in_schema=False)
def project_plan():
    return FileResponse(ROOT / "docs" / "PROJECT_PLAN.md", media_type="text/plain; charset=utf-8")


# API routes must precede the static root mount.
app.mount("/", StaticFiles(directory=FRONTEND, html=True), name="prototype")
