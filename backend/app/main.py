import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from app.core.db import engine

app = FastAPI(
    title="선박 LNG탱크 부품 품질 검사 API",
    version="0.1.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # dev 전용. 운영에서는 사내 도메인만
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def preload_models():
    import asyncio
    loop = asyncio.get_event_loop()
    try:
        from app.services.classifier import get_classifier
        await loop.run_in_executor(None, get_classifier)
        print("[startup] 분류기 로드 완료")
    except Exception as e:
        print(f"[startup] 분류기 로드 실패: {e}")
    try:
        from app.services.manual_search import get_embedder
        await loop.run_in_executor(None, get_embedder)
        print("[startup] 임베더 로드 완료")
    except Exception as e:
        print(f"[startup] 임베더 로드 실패: {e}")


@app.get("/api/health")
async def health_check():
    """헬스 체크. DB 연결까지 검증."""
    async with engine.connect() as conn:
        result = await conn.execute(text("SELECT 1"))
        result.scalar_one()
    return {"status": "ok", "db": "ok"}


os.makedirs("uploads", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

from app.api import auth, tank, session, inspect, result, settings

app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(tank.router, prefix="/api", tags=["tank"])
app.include_router(session.router, prefix="/api", tags=["session"])
app.include_router(inspect.router, prefix="/api", tags=["inspect"])
app.include_router(result.router, prefix="/api", tags=["result"])
app.include_router(settings.router, prefix="/api", tags=["settings"])
