from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.db import get_db
from app.core.security import (
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from app.schemas.auth import (
    LoginRequest, LoginResponse, InspectorOut,
    RefreshRequest, RefreshResponse, LogoutResponse,
)
from app.api.deps import get_current_inspector_id


router = APIRouter()


@router.post("/login", response_model=LoginResponse)
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        text("""
            SELECT 검사원_ID, 이름, 부서, 비밀번호_해시, 활성_여부
            FROM 검사원 WHERE 검사원_ID = :id
        """),
        {"id": body.inspector_id},
    )
    row = result.first()
    if row is None:
        raise HTTPException(status_code=401, detail={"error": "AUTH_FAILED", "message": "ID 또는 비밀번호가 올바르지 않습니다."})

    inspector_id, name, department, pw_hash, is_active = row
    if not is_active:
        raise HTTPException(status_code=403, detail={"error": "INACTIVE_ACCOUNT", "message": "비활성 계정입니다. 관리자에게 문의하세요."})
    if not verify_password(body.password, pw_hash):
        raise HTTPException(status_code=401, detail={"error": "AUTH_FAILED", "message": "ID 또는 비밀번호가 올바르지 않습니다."})

    await db.execute(
        text("UPDATE 검사원 SET 마지막_로그인_일시 = NOW() WHERE 검사원_ID = :id"),
        {"id": inspector_id},
    )
    await db.commit()

    return LoginResponse(
        access_token=create_access_token(inspector_id),
        refresh_token=create_refresh_token(inspector_id),
        inspector=InspectorOut(inspector_id=inspector_id, name=name, department=department),
    )


@router.post("/refresh", response_model=RefreshResponse)
async def refresh(body: RefreshRequest):
    try:
        payload = decode_token(body.refresh_token)
    except ValueError:
        raise HTTPException(status_code=401, detail={"error": "TOKEN_EXPIRED"})
    if payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail={"error": "TOKEN_TYPE_INVALID"})

    inspector_id = int(payload["sub"])
    return RefreshResponse(access_token=create_access_token(inspector_id))


@router.post("/logout", response_model=LogoutResponse)
async def logout(inspector_id: int = Depends(get_current_inspector_id)):
    now = datetime.now(timezone.utc).isoformat()
    print(f"[AUDIT] inspector_id={inspector_id} logged out at {now}")
    return LogoutResponse(message="로그아웃되었습니다.", logged_out_at=now)
