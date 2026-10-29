import asyncio
from contextlib import asynccontextmanager,suppress
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker
from .config import get_settings
from .database import Base,User,KitchenRow,make_engine
from .schemas import Kitchen
from .imports import ImportWorker


@asynccontextmanager
async def lifespan(app):
    settings=get_settings()
    if not settings.development_mode and len(settings.jwt_secret.get_secret_value()) < 32:
        raise RuntimeError('正式部署必须配置至少 32 字符的 COOK_JWT_SECRET。')
    engine=make_engine(settings.database_url)
    sessions=async_sessionmaker(engine,expire_on_commit=False)
    app.state.settings=settings;app.state.sessions=sessions
    if settings.development_mode:
        async with engine.begin() as conn: await conn.run_sync(Base.metadata.create_all)
        async with sessions() as db:
            if await db.get(User,'local-developer') is None:
                db.add(User(id='local-developer',name='本地开发账号'));await db.flush()
            if await db.scalar(select(KitchenRow).where(KitchenRow.user_id=='local-developer')) is None:
                kitchen=Kitchen();db.add(KitchenRow(id=kitchen.kitchen_id,user_id='local-developer',document=kitchen.model_dump()))
            await db.commit()
    worker=ImportWorker(sessions,settings)
    app.state.import_worker=worker
    await worker.restore()
    task=asyncio.create_task(worker.run())
    try: yield
    finally:
        task.cancel()
        with suppress(asyncio.CancelledError): await task
        await engine.dispose()
