from datetime import datetime,timezone
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Request as HTTPRequest
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from cook_scheduler import Request, generate_plan, SchedulingError
from ..database import get_db, RecipeRow, KitchenRow
from ..schemas import Recipe, Kitchen, SavedPlanRequest

router=APIRouter(prefix='/api/v1')
DB=Annotated[AsyncSession,Depends(get_db)]


from ..auth import owner


Owner=Annotated[str,Depends(owner)]


async def owned(db,cls,key,user):
    row=await db.get(cls,key)
    if row is None or row.user_id!=user: raise HTTPException(404,'记录不存在。')
    return row


@router.get('/profile')
async def profile(user:Owner,db:DB):
    from ..database import User
    account=await db.get(User,user)
    return {'user_id':user,'name':account.name,'development_mode':user=='local-developer'}


@router.get('/recipes',response_model=list[Recipe])
async def recipes(db:DB,user:Owner):
    rows=(await db.scalars(select(RecipeRow).where(RecipeRow.user_id==user).order_by(RecipeRow.updated_at.desc()))).all()
    return [row.document for row in rows]


@router.post('/recipes',response_model=Recipe,status_code=201)
async def create_recipe(recipe:Recipe,db:DB,user:Owner):
    db.add(RecipeRow(id=recipe.recipe_id,user_id=user,document=recipe.model_dump()))
    try: await db.commit()
    except IntegrityError as exc:
        await db.rollback();raise HTTPException(409,'菜谱 ID 已存在，请编辑已有菜谱。') from exc
    return recipe


@router.get('/recipes/{recipe_id}',response_model=Recipe)
async def get_recipe(recipe_id:str,db:DB,user:Owner):
    return (await owned(db,RecipeRow,recipe_id,user)).document


@router.put('/recipes/{recipe_id}',response_model=Recipe)
async def update_recipe(recipe_id:str,recipe:Recipe,db:DB,user:Owner):
    if recipe_id!=recipe.recipe_id: raise HTTPException(422,'菜谱 ID 不一致。')
    row=await owned(db,RecipeRow,recipe_id,user)
    row.document=recipe.model_dump();row.updated_at=datetime.now(timezone.utc)
    await db.commit();return recipe


@router.delete('/recipes/{recipe_id}',status_code=204)
async def delete_recipe(recipe_id:str,db:DB,user:Owner):
    await db.delete(await owned(db,RecipeRow,recipe_id,user));await db.commit()


@router.get('/kitchens/default',response_model=Kitchen)
async def default_kitchen(db:DB,user:Owner):
    row=await db.scalar(select(KitchenRow).where(KitchenRow.user_id==user))
    if row is None: raise HTTPException(404,'默认厨房尚未初始化。')
    return row.document


@router.put('/kitchens/{kitchen_id}',response_model=Kitchen)
async def update_kitchen(kitchen_id:str,kitchen:Kitchen,db:DB,user:Owner):
    if kitchen_id!=kitchen.kitchen_id: raise HTTPException(422,'厨房 ID 不一致。')
    row=await owned(db,KitchenRow,kitchen_id,user);row.document=kitchen.model_dump()
    await db.commit();return kitchen


@router.post('/plans/from-recipes')
async def from_recipes(payload:SavedPlanRequest,db:DB,user:Owner):
    now=datetime.now(timezone.utc);offset=None
    if payload.target_finish_time is not None:
        if payload.target_finish_time.tzinfo is None: raise HTTPException(422,'开饭时间必须包含时区。')
        offset=int((payload.target_finish_time-now).total_seconds())
        if not 0<offset<=604800: raise HTTPException(422,'请选择未来一周内的开饭时间。')
    if len(set(payload.recipe_ids))!=len(payload.recipe_ids): raise HTTPException(422,'请勿重复选择菜谱。')
    recipes=[Recipe.model_validate((await owned(db,RecipeRow,key,user)).document) for key in payload.recipe_ids]
    if any(not r.confirmed for r in recipes): raise HTTPException(422,'请先确认 AI 识别的菜谱内容。')
    kitchen=Kitchen.model_validate((await owned(db,KitchenRow,payload.kitchen_id,user)).document)
    try:
        request=Request(tasks=[t for r in recipes for t in r.tasks],holds=[h for r in recipes for h in r.holds],
            capacities=kitchen.capacities,cook_count=kitchen.cook_count,target_finish_seconds=offset,
            max_holding_seconds={r.recipe_id:r.max_holding_seconds for r in recipes})
    except ValidationError as exc:
        raise HTTPException(422,"所选菜谱含重复任务 ID 或无效依赖，请编辑后重试。") from exc
    # CPU work runs outside the event loop.
    from starlette.concurrency import run_in_threadpool
    try: plan=await run_in_threadpool(generate_plan,request,time_limit_seconds=3)
    except SchedulingError as exc: raise HTTPException(409,str(exc)) from exc
    return {'origin':now.isoformat(),'request':request.model_dump(),'plan':plan.model_dump(),
            'recipes':{r.recipe_id:r.name for r in recipes}}
