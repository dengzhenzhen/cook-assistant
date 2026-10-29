"""Async SQLAlchemy storage, usable with SQLite locally or PostgreSQL."""
from datetime import datetime, timezone
from pathlib import Path
from fastapi import Request
from sqlalchemy import event, JSON, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from .config import get_settings


def utcnow():
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = 'users'
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    name: Mapped[str] = mapped_column(String(80))


class RecipeRow(Base):
    __tablename__ = 'recipes'
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    document: Mapped[dict] = mapped_column(JSON)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class KitchenRow(Base):
    __tablename__ = 'kitchens'
    __table_args__ = (UniqueConstraint('user_id', name='uq_default_kitchen_user'),)
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    document: Mapped[dict] = mapped_column(JSON)


class ImportJob(Base):
    __tablename__ = 'import_jobs'
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    digest: Mapped[str] = mapped_column(String(64), index=True)
    status: Mapped[str] = mapped_column(String(20), default='pending')
    payload: Mapped[dict] = mapped_column(JSON)
    result: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    error: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AIUsage(Base):
    __tablename__ = 'ai_usage'
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    job_id: Mapped[str] = mapped_column(ForeignKey('import_jobs.id'), index=True)
    model: Mapped[str] = mapped_column(String(100))
    input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AIQuota(Base):
    __tablename__ = 'ai_quotas'
    key: Mapped[str] = mapped_column(String(150), primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0)


def make_engine(url=None):
    url = url or get_settings().database_url
    if url.startswith('sqlite'):
        Path(__file__).resolve().parents[2].joinpath('.data').mkdir(exist_ok=True)
    engine=create_async_engine(url, echo=False)
    if url.startswith('sqlite'):
        @event.listens_for(engine.sync_engine,'connect')
        def configure_sqlite(connection, record):
            cursor=connection.cursor()
            cursor.execute('PRAGMA foreign_keys=ON')
            cursor.execute('PRAGMA busy_timeout=5000')
            cursor.close()
    return engine


async def get_db(request: Request):
    async with request.app.state.sessions() as session:
        yield session


class Credential(Base):
    __tablename__ = 'credentials'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password_hash: Mapped[str] = mapped_column(String(300))


class RefreshToken(Base):
    __tablename__ = 'refresh_tokens'
    digest: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    expires: Mapped[int] = mapped_column(Integer)


class SessionRow(Base):
    __tablename__ = 'cooking_sessions'
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    document: Mapped[dict] = mapped_column(JSON)
