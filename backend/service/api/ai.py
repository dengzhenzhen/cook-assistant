import base64
import hashlib
import io
import json
from datetime import datetime,timezone
from fastapi import APIRouter, HTTPException, Request, UploadFile
from sqlalchemy import select,func
from ..config import get_settings
from ..database import ImportJob, AIUsage, AIQuota
from ..imports import reserve_quotas
from ..deepseek import normalize_resources
from ..schemas import Recipe
from ..schemas import TextImport,new_id
from .catalog import DB,Owner,owned

router=APIRouter(prefix='/api/v1')


def job_view(job):
    recipe=Recipe.model_validate(job.result) if job.result else None
    if recipe and job.payload.get('parser_version')!=2:
        recipe=normalize_resources(recipe)
    result=recipe.model_dump() if recipe else None
    return {'job_id':job.id,'status':job.status,'recipe':result,'error':job.error}


async def enqueue(request,db,user,payload):
    settings=request.app.state.settings
    if not settings.deepseek_api_key.get_secret_value(): raise HTTPException(503,'尚未配置 DeepSeek API。')
    digest=hashlib.sha256((settings.deepseek_model+json.dumps(payload,sort_keys=True,ensure_ascii=False)).encode()).hexdigest()
    cached=await db.scalar(select(ImportJob).where(ImportJob.user_id==user,ImportJob.digest==digest,
        ImportJob.status.in_(['pending','running','completed'])).order_by(ImportJob.created_at.desc()))
    if cached: return job_view(cached)
    await reserve_quotas(db,user,settings)
    job=ImportJob(id=new_id(),user_id=user,digest=digest,payload=payload,status='pending')
    db.add(job);await db.commit()
    request.app.state.import_worker.queue.put_nowait(job.id)
    return job_view(job)


@router.get('/ai/status')
async def status(request:Request,db:DB,user:Owner):
    settings=request.app.state.settings
    day=datetime.now(timezone.utc).strftime('%Y%m%d')
    quota=await db.get(AIQuota,f'{user}:day:{day}')
    tokens=await db.execute(select(func.sum(AIUsage.input_tokens),func.sum(AIUsage.output_tokens))
        .join(ImportJob,AIUsage.job_id==ImportJob.id).where(ImportJob.user_id==user))
    input_tokens,output_tokens=tokens.one()
    return {'provider':'DeepSeek','configured':bool(settings.deepseek_api_key.get_secret_value()),
        'model':settings.deepseek_model,'daily_used':quota.count if quota else 0,'daily_limit':settings.ai_daily_limit,
        'input_tokens':input_tokens or 0,'output_tokens':output_tokens or 0}


@router.post('/recipes/import/text',status_code=202)
async def import_text(payload:TextImport,request:Request,db:DB,user:Owner):
    return await enqueue(request,db,user,{'source':'text','text':payload.text.strip()})


@router.post('/recipes/import/image',status_code=202)
async def import_images(images:list[UploadFile],request:Request,db:DB,user:Owner):
    from PIL import Image,UnidentifiedImageError
    if not 1<=len(images)<=5: raise HTTPException(422,'每次请选择 1–5 张图片。')
    urls=[]
    for upload in images:
        content=await upload.read(4*1024*1024+1)
        if len(content)>4*1024*1024: raise HTTPException(413,'单张图片不能超过 4MB。')
        try:
            with Image.open(io.BytesIO(content)) as image:
                if image.format not in ('JPEG','PNG','WEBP') or max(image.size)>4096:
                    raise HTTPException(422,'支持 JPEG/PNG/WebP 图片，单边最多 4096 像素。')
                mime=Image.MIME[image.format];image.verify()
        except (UnidentifiedImageError,OSError,Image.DecompressionBombError) as exc:
            raise HTTPException(422,'图片内容无效。') from exc
        urls.append('data:'+mime+';base64,'+base64.b64encode(content).decode())
    return await enqueue(request,db,user,{'source':'image','text':'解析这些截图中同一道菜的完整菜谱。','images':urls})


@router.get('/import-jobs/{job_id}')
async def import_job(job_id:str,db:DB,user:Owner):
    return job_view(await owned(db,ImportJob,job_id,user))
