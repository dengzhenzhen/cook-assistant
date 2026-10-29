"""Password authentication with short JWT access and one-use refresh tokens."""
import hashlib
import secrets
import time
from pathlib import Path
from uuid import uuid4
from typing import Annotated
import jwt
from pwdlib import PasswordHash
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select, delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from .database import get_db, User, Credential, RefreshToken, KitchenRow
from .schemas import Kitchen

router = APIRouter(prefix='/api/v1/auth', tags=['auth'])
DB = Annotated[AsyncSession, Depends(get_db)]
hasher = PasswordHash.recommended()
DUMMY_HASH = hasher.hash('not-a-valid-account-password')


def secret(request):
    configured = request.app.state.settings.jwt_secret.get_secret_value()
    if configured:
        return configured
    # Persistent local secret; production should set COOK_JWT_SECRET.
    path = Path(__file__).resolve().parents[2] / '.data' / 'jwt-secret'
    path.parent.mkdir(exist_ok=True)
    try:
        with open(path, 'x', opener=lambda p, f: __import__('os').open(p, f, 0o600)) as file:
            file.write(secrets.token_urlsafe(48))
    except FileExistsError:
        pass
    return path.read_text()


async def owner(request: Request, db: DB):
    header = request.headers.get('Authorization', '')
    if not header and request.app.state.settings.allow_development_login:
        return 'local-developer'
    try:
        scheme, token = header.split(' ', 1)
        if scheme.lower() != 'bearer': raise ValueError()
        claims = jwt.decode(token, secret(request), algorithms=['HS256'],
                            options={'require': ['sub', 'exp', 'iat']}, audience='kaifan', issuer='kaifan-api')
        user = await db.get(User, claims['sub'])
        if user is None: raise ValueError()
        return user.id
    except (ValueError, jwt.InvalidTokenError):
        raise HTTPException(401, '请登录或重新登录。', headers={'WWW-Authenticate': 'Bearer'})


class Login(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=8, max_length=128)

    @field_validator('email')
    @classmethod
    def email_format(cls, value):
        value = value.strip().lower()
        if value.count('@') != 1 or any(c.isspace() for c in value) or '.' not in value.split('@')[-1]:
            raise ValueError('请输入有效邮箱。')
        return value


class TokenInput(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


async def issue(db, request, user):
    now = int(time.time())
    access = jwt.encode({'sub': user, 'iat': now, 'exp': now+900,
                         'aud': 'kaifan', 'iss': 'kaifan-api'}, secret(request), algorithm='HS256')
    refresh = secrets.token_urlsafe(48)
    db.add(RefreshToken(digest=digest(refresh), user_id=user, expires=now+2592000))
    await db.commit()
    return {'access_token': access, 'refresh_token': refresh, 'user_id': user, 'token_type': 'bearer'}


@router.post('/register', status_code=201)
async def register(payload: Login, db: DB, request: Request):
    from starlette.concurrency import run_in_threadpool
    user = str(uuid4())
    encoded = await run_in_threadpool(hasher.hash, payload.password)
    db.add(User(id=user, name=payload.email.split('@')[0]))
    await db.flush()
    db.add(Credential(user_id=user, email=payload.email, password_hash=encoded))
    kitchen = Kitchen()
    db.add(KitchenRow(id=kitchen.kitchen_id, user_id=user, document=kitchen.model_dump()))
    try:
        return await issue(db, request, user)
    except IntegrityError:
        await db.rollback()
        raise HTTPException(409, '邮箱已注册。')


@router.post('/login')
async def login(payload: Login, db: DB, request: Request):
    # Bounded per-IP login attempts; no passwords retained in memory.
    now = time.monotonic()
    attempts = getattr(request.app.state, 'login_attempts', {})
    attempts = {k: v for k, v in attempts.items() if v[0] > now-60}
    key = request.client.host if request.client else 'unknown'
    stamp, count = attempts.get(key, (now, 0))
    if count >= 10: raise HTTPException(429, '登录尝试过多，请一分钟后重试。')
    attempts[key] = (stamp, count+1)
    request.app.state.login_attempts = attempts
    row = await db.scalar(select(Credential).where(Credential.email == payload.email))
    from starlette.concurrency import run_in_threadpool
    valid = await run_in_threadpool(hasher.verify, payload.password, row.password_hash if row else DUMMY_HASH)
    if row is None or not valid: raise HTTPException(401, '邮箱或密码错误。')
    return await issue(db, request, row.user_id)


@router.post('/refresh')
async def refresh(payload: TokenInput, db: DB, request: Request):
    # DELETE RETURNING makes refresh consumption atomic across concurrent requests.
    result = await db.execute(delete(RefreshToken).where(
        RefreshToken.digest == digest(payload.refresh_token), RefreshToken.expires > int(time.time())
    ).returning(RefreshToken.user_id))
    user = result.scalar_one_or_none()
    if user is None: raise HTTPException(401, '登录已失效，请重新登录。')
    return await issue(db, request, user)


@router.post('/logout', status_code=204)
async def logout(payload: TokenInput, db: DB):
    await db.execute(delete(RefreshToken).where(RefreshToken.digest == digest(payload.refresh_token)))
    await db.commit()
