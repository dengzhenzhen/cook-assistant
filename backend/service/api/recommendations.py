"""Authenticated name-only menu recommendation endpoint."""
from fastapi import APIRouter, HTTPException, Request
from sqlalchemy import select

from ..database import AIUsage, ImportJob, RecipeRow
from ..deepseek import AIError
from ..imports import reserve_quotas
from ..recommendations import (MenuRequest, MenuResponse, ResolveItem, ResolveRequest,
                               ResolveResponse, Candidate, generate_menu, parse_menu,
                               normalized_name)
from ..schemas import new_id
from .catalog import DB, Owner
from .ai import enqueue

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


@router.post('/recommendations/resolve', response_model=ResolveResponse,
             response_model_exclude_none=True)
async def resolve_menu(payload: ResolveRequest, request: Request, db: DB, user: Owner):
    rows = (await db.scalars(select(RecipeRow).where(RecipeRow.user_id == user))).all()
    by_name = {}
    for row in rows:
        doc = row.document
        name = doc.get('name') if isinstance(doc, dict) else None
        if isinstance(name, str) and name.strip():
            by_name.setdefault(normalized_name(name), []).append(Candidate(
                recipe_id=row.id, name=name.strip(), confirmed=doc.get('confirmed', True),
                servings=doc.get('servings', 2),
                ingredient_names=[item['name'] for item in doc.get('ingredients', [])[:6]
                                  if isinstance(item, dict) and isinstance(item.get('name'), str)]))
    items = []
    for name in payload.names:
        key = normalized_name(name)
        candidates = by_name.get(key, [])
        selected = payload.selected_recipe_ids.get(key)
        if selected:
            choice = next((candidate for candidate in candidates
                           if candidate.recipe_id == selected), None)
            if choice is None:
                items.append(ResolveItem(name=name, status='failed', error='选定菜谱不存在或无权使用。'))
            else:
                items.append(ResolveItem(name=name,
                    status='matched' if choice.confirmed else 'needs_review',
                    recipe_id=choice.recipe_id))
            continue
        if len(candidates) > 1:
            items.append(ResolveItem(name=name, status='needs_choice', candidates=candidates))
            continue
        if candidates:
            choice = candidates[0]
            items.append(ResolveItem(name=name,
                status='matched' if choice.confirmed else 'needs_review',
                recipe_id=choice.recipe_id))
            continue
        try:
            job = await enqueue(request, db, user, {'source': 'text', 'text': normalized_name(name)})
            items.append(ResolveItem(name=name, status='import_pending', job_id=job['job_id']))
        except HTTPException as exc:
            await db.rollback()
            items.append(ResolveItem(name=name, status='failed', error=str(exc.detail)))
        except Exception:
            await db.rollback()
            items.append(ResolveItem(name=name, status='failed', error='菜谱导入失败，请稍后重试。'))
    return ResolveResponse(items=items)
