"""Compare-and-swap for durable offline recipe/kitchen edits."""
from typing import Annotated, Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from ..auth import owner
from ..database import get_db, RecipeRow, KitchenRow
from ..schemas import Recipe, Kitchen

router = APIRouter(prefix='/api/v1/sync', tags=['sync'])
DB = Annotated[AsyncSession, Depends(get_db)]
Owner = Annotated[str, Depends(owner)]


class Edit(BaseModel):
    kind: Literal['recipe', 'kitchen']
    base: dict | None = None
    document: dict


@router.post('/edit')
async def edit(payload: Edit, db: DB, user: Owner):
    schema, model, id_field = (Recipe, RecipeRow, 'recipe_id') if payload.kind == 'recipe' else (Kitchen, KitchenRow, 'kitchen_id')
    try: document = schema.model_validate(payload.document).model_dump()
    except ValueError: raise HTTPException(422, '离线编辑数据无效。')
    key = document[id_field]
    row = await db.scalar(select(model).where(model.id == key).with_for_update())
    if row is not None and row.user_id != user: raise HTTPException(404, '记录不存在。')
    if row is not None and row.document == document: return {'document': document}
    if (row.document if row else None) != payload.base:
        raise HTTPException(409, '云端内容已改变，本地编辑已保留，请解决冲突。')
    if row:
        # Conditional update also protects SQLite, where FOR UPDATE is ignored.
        from sqlalchemy import update, cast
        condition = model.document == row.document
        if db.bind.dialect.name == 'postgresql':
            from sqlalchemy.dialects.postgresql import JSONB
            condition = cast(model.document, JSONB) == row.document
        result = await db.execute(update(model).where(model.id == key, condition).values(document=document))
        if result.rowcount != 1: raise HTTPException(409, '内容已改变，请重试同步。')
    else:
        if payload.kind == 'kitchen': raise HTTPException(404, '厨房不存在。')
        db.add(model(id=key, user_id=user, document=document))
    try: await db.commit()
    except IntegrityError:
        await db.rollback(); raise HTTPException(409, '记录已改变，请重试同步。')
    return {'document': document}
