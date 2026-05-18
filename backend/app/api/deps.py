from fastapi import Depends, Header, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.db import get_db
from app.core.security import decode_token


async def get_current_inspector_id(
    authorization: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> int:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail={"error": "AUTH_REQUIRED"})
    token = authorization.removeprefix("Bearer ").strip()
    try:
        payload = decode_token(token)
    except ValueError:
        raise HTTPException(status_code=401, detail={"error": "TOKEN_EXPIRED"})

    if payload.get("type") != "access":
        raise HTTPException(status_code=401, detail={"error": "TOKEN_TYPE_INVALID"})

    inspector_id = int(payload["sub"])

    result = await db.execute(
        text('SELECT 활성_여부 FROM 검사원 WHERE 검사원_ID = :id'),
        {"id": inspector_id},
    )
    row = result.first()
    if row is None:
        raise HTTPException(status_code=404, detail={"error": "INSPECTOR_NOT_FOUND"})
    if not row[0]:
        raise HTTPException(status_code=403, detail={"error": "INACTIVE_ACCOUNT"})

    return inspector_id
