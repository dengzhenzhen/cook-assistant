"""Versioned session snapshots: offline retries are idempotent, conflicts explicit."""
from typing import Annotated
from uuid import uuid4
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from ..auth import owner
from ..database import get_db, SessionRow
from cook_scheduler import Request

router = APIRouter(prefix='/api/v1/sessions', tags=['sessions'])
DB = Annotated[AsyncSession, Depends(get_db)]
Owner = Annotated[str, Depends(owner)]


class Snapshot(BaseModel):
    session_id: str = Field(min_length=1, max_length=80)
    base_version: int = Field(ge=0)
    mutation_id: str = Field(min_length=1, max_length=80)
    document: dict


def validate_document(doc):
    try:
        Request.model_validate(doc['snapshot']['request'])
        tasks = {t['id']: t for t in doc['snapshot']['request']['tasks']}
        states = doc.get('states', {})
        if set(states)-set(tasks): raise ValueError('unknown task')
        for key, state in states.items():
            if state['status'] not in ('running', 'completed'): raise ValueError('status')
            if state['started'] < 0: raise ValueError('time')
            if state.get('ended') is not None and state['ended'] < state['started']: raise ValueError('end')
            for dependency in tasks[key].get('dependencies', []):
                previous = states.get(dependency, {})
                if previous.get('status') != 'completed' or previous.get('ended', float('inf')) > state['started']:
                    raise ValueError('dependency')
    except (ValueError, KeyError, TypeError):
        raise HTTPException(422, '会话数据或任务依赖无效。')


@router.get('')
async def listing(db: DB, user: Owner):
    rows = (await db.scalars(select(SessionRow).where(SessionRow.user_id == user))).all()
    return [{'session_id': r.id, 'version': r.version, 'document': r.document} for r in rows]


@router.get('/{session_id}')
async def get_session(session_id: str, db: DB, user: Owner):
    row = await db.get(SessionRow, session_id)
    if row is None or row.user_id != user: raise HTTPException(404, '会话不存在。')
    return {'session_id': row.id, 'version': row.version, 'document': row.document}


@router.put('/{session_id}')
async def sync(session_id: str, payload: Snapshot, db: DB, user: Owner):
    if session_id != payload.session_id: raise HTTPException(422, '会话 ID 不一致。')
    validate_document(payload.document)
    row = await db.get(SessionRow, session_id)
    if row is not None and row.user_id != user: raise HTTPException(404, '会话不存在。')
    if row is not None and row.document.get('_mutation_id') == payload.mutation_id:
        return {'version': row.version}
    if (row.version if row else 0) != payload.base_version:
        raise HTTPException(409, {'message': '会话已在其他设备更新。', 'version': row.version if row else 0,
                                  'document': row.document if row else None})
    document = {**payload.document, '_mutation_id': payload.mutation_id}
    if row:
        # Completed facts cannot be removed or rewritten by another snapshot.
        old = row.document.get('states', {})
        if any(s.get('status') == 'completed' and document.get('states', {}).get(k) != s for k, s in old.items()):
            raise HTTPException(409, '已完成任务不可修改。')
        result = await db.execute(update(SessionRow).where(SessionRow.id == session_id,
            SessionRow.version == payload.base_version).values(document=document, version=payload.base_version+1))
        if result.rowcount != 1: raise HTTPException(409, '会话版本冲突，请重新加载。')
    else:
        db.add(SessionRow(id=session_id, user_id=user, document=document, version=1))
    try:
        await db.commit()
    except __import__('sqlalchemy').exc.IntegrityError:
        await db.rollback()
        raise HTTPException(409, '会话版本冲突，请重新加载。')
    return {'version': payload.base_version+1}
