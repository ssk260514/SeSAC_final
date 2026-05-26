from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.db import get_db
from app.api.deps import get_current_inspector_id


class SettingsBody(BaseModel):
    push_notification: bool = True
    language: str = "ko"


router = APIRouter()


@router.get("/settings")
async def get_settings(
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(text("""
        SELECT 푸시_알림, 언어, 수정_일시 FROM 사용자_설정 WHERE 검사원_ID = :iid
    """), {"iid": inspector_id})
    row = res.first()
    if row is None:
        return {
            "inspector_id": inspector_id,
            "push_notification": True,
            "language": "ko",
            "app_version": "v0.1.0",
            "updated_at": None,
        }
    return {
        "inspector_id": inspector_id,
        "push_notification": row[0],
        "language": row[1],
        "app_version": "v0.1.0",
        "updated_at": row[2].isoformat() if row[2] else None,
    }


@router.patch("/settings")
async def update_settings(
    body: SettingsBody,
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    push = body.push_notification
    lang = body.language
    print(f"[settings] PATCH inspector_id={inspector_id} push={push} lang={lang}")
    upsert = await db.execute(text("""
        INSERT INTO 사용자_설정 (검사원_ID, 푸시_알림, 언어, 수정_일시)
        VALUES (:iid, :p, :l, NOW())
        ON CONFLICT (검사원_ID) DO UPDATE SET
            푸시_알림 = EXCLUDED.푸시_알림,
            언어 = EXCLUDED.언어,
            수정_일시 = NOW()
        RETURNING 수정_일시
    """), {"iid": inspector_id, "p": push, "l": lang})
    updated = upsert.scalar_one()
    await db.commit()
    return {"message": "설정이 저장되었습니다.", "updated_at": updated.isoformat()}
