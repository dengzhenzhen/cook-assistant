"""Durable local import queue. Pending jobs survive restarts; in-flight jobs are not rebilled silently."""
import asyncio
from datetime import datetime, timezone
from sqlalchemy import select, update
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.dialects.postgresql import insert as pg_insert
from .database import ImportJob, AIQuota, AIUsage
from .schemas import new_id
from .deepseek import complete, parse_result, AIError


async def reserve_quotas(db, user_id, settings):
    now=datetime.now(timezone.utc)
    buckets=[(f'{user_id}:minute:{now:%Y%m%d%H%M}',settings.ai_minute_limit),
             (f'{user_id}:day:{now:%Y%m%d}',settings.ai_daily_limit),
             (f'global:day:{now:%Y%m%d}',settings.ai_global_daily_limit)]
    insert=pg_insert if db.bind.dialect.name=='postgresql' else sqlite_insert
    for key,limit in buckets:
        await db.execute(insert(AIQuota).values(key=key,count=0).on_conflict_do_nothing())
        result=await db.execute(update(AIQuota).where(AIQuota.key==key,AIQuota.count<limit).values(count=AIQuota.count+1))
        if result.rowcount!=1:
            from fastapi import HTTPException
            raise HTTPException(429,'AI 解析配额已用尽，请稍后重试；手动菜谱和排程仍可使用。')


class ImportWorker:
    def __init__(self, sessions, settings):
        self.sessions,self.settings=sessions,settings
        self.queue=asyncio.Queue()

    async def restore(self):
        async with self.sessions() as db:
            await db.execute(update(ImportJob).where(ImportJob.status=='running').values(
                status='failed',error='服务重启中断了解析，请主动重新导入；不会静默重复扣费。'))
            pending=(await db.scalars(select(ImportJob.id).where(ImportJob.status=='pending'))).all()
            await db.commit()
        for job in pending: self.queue.put_nowait(job)

    async def run(self):
        while True:
            job_id=await self.queue.get()
            try:
                await self.process(job_id)
            finally:
                self.queue.task_done()

    async def process(self, job_id):
        async with self.sessions() as db:
            job=await db.get(ImportJob,job_id)
            if not job or job.status!='pending': return
            payload=job.payload
            job.status='running'
            await db.commit()
        try:
            prompt=payload.get('text','')
            images=payload.get('images')
            for attempt in range(2):
                try:
                    content,usage=await complete(self.settings,prompt,images)
                except AIError as exc:
                    if exc.usage: await self.record_usage(job_id,exc.usage)
                    raise
                await self.record_usage(job_id,usage)
                try:
                    recipe=parse_result(content,payload['source'])
                    break
                except AIError as exc:
                    if attempt: raise
                    prompt=('仅修正下面 JSON 的字段类型、ID、任务依赖或资源占用关系，保持原有菜名、食材与烹饪操作。'
                            '不要增加新菜品。程序校验问题：'+exc.validation_hint+'\nJSON：'+content)
                    images=None
            async with self.sessions() as db:
                job=await db.get(ImportJob,job_id)
                job.status='completed';job.result=recipe.model_dump();job.payload={'parser_version':2}
                await db.commit()
        except Exception as exc:
            async with self.sessions() as db:
                job=await db.get(ImportJob,job_id)
                job.status='failed'
                job.error=str(exc) if isinstance(exc,AIError) else '解析任务失败，请重试。'
                job.payload={}
                await db.commit()

    async def record_usage(self,job_id,usage):
        async with self.sessions() as db:
            db.add(AIUsage(id=new_id(),job_id=job_id,model=self.settings.deepseek_model,
                input_tokens=usage.get('prompt_tokens',0),output_tokens=usage.get('completion_tokens',0)))
            await db.commit()
