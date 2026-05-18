from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
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


@app.get("/api/health")
async def health_check():
    """헬스 체크. DB 연결까지 검증."""
    async with engine.connect() as conn:
        result = await conn.execute(text("SELECT 1"))
        result.scalar_one()
    return {"status": "ok", "db": "ok"}


from app.api import auth
app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
