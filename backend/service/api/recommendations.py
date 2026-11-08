"""Authenticated name-only menu recommendation endpoint."""
from fastapi import APIRouter, HTTPException, Request
from sqlalchemy import select

from ..database import AIUsage, ImportJob, RecipeRow
from ..deepseek import AIError
from ..imports import reserve_quotas
from ..recommendations import MenuRequest, MenuResponse, generate_menu, parse_menu
from ..schemas import new_id
from .catalog import DB, Owner

router = APIRouter(prefix='/api/v1')


@router.post('/recommendations/menu', response_model=MenuResponse)
async def recommend_menu(payload: MenuRequest, request: Request, db: DB, user: Owner):
    settings = request.app.state.settings
    if not settings.deepseek_api_key.get_secret_value():
        raise HTTPException(503, '尚未配置 DeepSeek API。')
    rows = (await db.scalars(select(RecipeRow).where(RecipeRow.user_id == user)
                             .order_by(RecipeRow.updated_at.desc()))).all()
    library = []
    for row in rows:
        name = row.document.get('name') if isinstance(row.document, dict) else None
        if isinstance(name, str) and name.strip() and row.document.get('confirmed', True):
            library.append({'id': row.id, 'name': name.strip()[:80]})
    await reserve_quotas(db, user, settings)
    # This job is an accounting parent only. It is never queued for recipe import.
    job = ImportJob(id=new_id(), user_id=user, digest=new_id(),
                    payload={'kind': 'recommendation'}, status='running')
    db.add(job)
    await db.commit()
    usage = {}
    try:
        content, usage = await generate_menu(settings, payload, library)
        menu = parse_menu(content, payload, library)
        job.status = 'completed'
        return menu
    except AIError as exc:
        if exc.usage:
            usage = exc.usage
        job.status = 'failed'
        job.error = str(exc)[:500]
        raise HTTPException(502, str(exc)) from exc
    except Exception as exc:
        job.status = 'failed'
        job.error = '推荐失败，请稍后重试。'
        raise HTTPException(502, job.error) from exc
    finally:
        if isinstance(usage, dict):
            def tokens(key):
                value = usage.get(key, 0)
                return value if type(value) is int and value >= 0 else 0
            if usage:
                db.add(AIUsage(id=new_id(), job_id=job.id, model=settings.deepseek_model,
                               input_tokens=tokens('prompt_tokens'),
                               output_tokens=tokens('completion_tokens')))
        await db.commit()
