from fastapi import APIRouter, Depends, HTTPException, Path
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.db import get_db
from app.core.config import settings
from app.api.deps import get_current_inspector_id
from app.schemas.tank import TankTypeOut, ProcessInfo


router = APIRouter()


def _parse_sectors(raw) -> dict:
    """["외부-지지대", "내부-바닥"] → {"외부": ["지지대"], "내부": ["바닥"]}"""
    if isinstance(raw, dict):
        return raw
    result = {}
    for item in raw:
        parts = item.split("-", 1)
        if len(parts) == 2:
            sector, sub = parts
            result.setdefault(sector, []).append(sub)
        else:
            result.setdefault(item, [])
    return result


@router.get("/tank-types", response_model=list[TankTypeOut])
async def list_tank_types(
    db: AsyncSession = Depends(get_db),
    _: int = Depends(get_current_inspector_id),
):
    result = await db.execute(text("""
        SELECT z.탱크_타입, z.구역_코드, z.구역_설명,
               p.공정_ID, p.공정_이름, p.결함_유형_목록
        FROM 검사_구역 z
        JOIN 공정 p ON p.공정_ID = z.공정_ID
        ORDER BY z.탱크_타입
    """))
    rows = result.all()
    return [
        TankTypeOut(
            tank_type=r[0],
            sectors=_parse_sectors(r[1]),
            description=r[2],
            process=ProcessInfo(
                process_id=r[3],
                process_name=r[4],
                confidence_threshold=settings.GLOBAL_CONFIDENCE_THRESHOLD,
                defect_types=r[5],
            ),
        )
        for r in rows
    ]


@router.get("/tank-types/{tank_type}/process", response_model=TankTypeOut)
async def get_tank_type_detail(
    tank_type: str = Path(..., pattern="^[BC]$"),
    db: AsyncSession = Depends(get_db),
    _: int = Depends(get_current_inspector_id),
):
    result = await db.execute(text("""
        SELECT z.탱크_타입, z.구역_코드, z.구역_설명,
               p.공정_ID, p.공정_이름, p.결함_유형_목록
        FROM 검사_구역 z
        JOIN 공정 p ON p.공정_ID = z.공정_ID
        WHERE z.탱크_타입 = :tt
    """), {"tt": tank_type})
    r = result.first()
    if r is None:
        raise HTTPException(status_code=400, detail={"error": "TANK_TYPE_NOT_FOUND"})
    return TankTypeOut(
        tank_type=r[0],
        sectors=_parse_sectors(r[1]),
        description=r[2],
        process=ProcessInfo(
            process_id=r[3],
            process_name=r[4],
            confidence_threshold=settings.GLOBAL_CONFIDENCE_THRESHOLD,
            defect_types=r[5],
        ),
    )
