from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app.core.db import get_db
from app.core.config import settings
from app.api.deps import get_current_inspector_id
from app.api.tank import _parse_sectors
from app.schemas.tank import (
    CreateSessionRequest, CreateSessionResponse, ProcessInfo,
)
from app.schemas.session import SessionSummary, DashboardSummary


router = APIRouter()


@router.post("/sessions", response_model=CreateSessionResponse)
async def create_session(
    body: CreateSessionRequest,
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    # 1. 탱크-공정 매핑 + 세부위치 검증
    zone = await db.execute(text("""
        SELECT z.구역_코드, p.공정_ID, p.공정_이름, p.활성_여부
        FROM 검사_구역 z JOIN 공정 p ON p.공정_ID = z.공정_ID
        WHERE z.탱크_타입 = :tt
    """), {"tt": body.tank_type})
    zr = zone.first()
    if zr is None:
        raise HTTPException(status_code=400, detail={"error": "TANK_TYPE_NOT_FOUND"})

    raw_sectors, process_id, process_name, is_active = zr
    if not is_active:
        raise HTTPException(status_code=400, detail={"error": "INVALID_PROCESS"})

    sectors_dict = _parse_sectors(raw_sectors)
    if body.selected_sector not in sectors_dict:
        raise HTTPException(status_code=400, detail={"error": "INVALID_SUBSECTOR"})
    if body.selected_subsector not in sectors_dict[body.selected_sector]:
        raise HTTPException(status_code=400, detail={"error": "INVALID_SUBSECTOR"})

    # 2. 1일 1세션 사전 확인 (partial unique index가 race condition도 막아줌)
    existing = await db.execute(text("""
        SELECT 세션_ID FROM 검사_세션
        WHERE 검사원_ID = :iid AND 세션_상태 = '진행중'
    """), {"iid": inspector_id})
    er = existing.first()
    if er is not None:
        raise HTTPException(
            status_code=409,
            detail={"error": "DAILY_SESSION_EXISTS",
                    "message": "오늘 이미 진행 중인 세션이 있습니다. 검사 이력에서 '이어서 검사'를 이용해주세요.",
                    "existing_session_id": er[0]},
        )

    # 3. INSERT (unique violation도 잡음)
    try:
        ins = await db.execute(text("""
            INSERT INTO 검사_세션 (검사원_ID, 공정_ID, 탱크_타입, 선택_구역, 선택_세부위치)
            VALUES (:iid, :pid, :tt, :ss, :sub)
            RETURNING 세션_ID, 시작_일시
        """), {
            "iid": inspector_id, "pid": process_id, "tt": body.tank_type,
            "ss": body.selected_sector, "sub": body.selected_subsector,
        })
        row = ins.first()
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail={"error": "DAILY_SESSION_EXISTS",
                    "message": "오늘 이미 진행 중인 세션이 있습니다.",
                    "existing_session_id": -1},
        )

    return CreateSessionResponse(
        session_id=row[0],
        status="진행중",
        started_at=row[1].isoformat(),
        tank_type=body.tank_type,
        selected_sector=body.selected_sector,
        selected_subsector=body.selected_subsector,
        process=ProcessInfo(process_id=process_id, process_name=process_name, confidence_threshold=settings.GLOBAL_CONFIDENCE_THRESHOLD),
    )


@router.get("/sessions", response_model=list[SessionSummary])
async def list_sessions(
    status: str | None = None,
    limit: int = 20,
    offset: int = 0,
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    where = "검사원_ID = :iid"
    params = {"iid": inspector_id, "lim": limit, "off": offset}
    if status and status != "all":
        where += " AND 세션_상태 = :st"
        params["st"] = status

    res = await db.execute(text(f"""
        SELECT 세션_ID, 탱크_타입, 시작_일시, 종료_일시, 불량_수 > 0 AS has_defect
        FROM 검사_세션
        WHERE {where}
        ORDER BY 시작_일시 DESC
        LIMIT :lim OFFSET :off
    """), params)
    rows = res.all()
    return [
        SessionSummary(
            session_id=r[0],
            tank_type=r[1],
            started_at=r[2].isoformat(),
            ended_at=r[3].isoformat() if r[3] else None,
            has_defect=bool(r[4]),
        )
        for r in rows
    ]


@router.get("/dashboard/summary", response_model=DashboardSummary)
async def dashboard_summary(
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    active = await db.execute(text("""
        SELECT 세션_ID, 탱크_타입, 선택_구역, 선택_세부위치 FROM 검사_세션
        WHERE 검사원_ID = :iid AND 세션_상태='진행중'
        ORDER BY 시작_일시 DESC
        LIMIT 1
    """), {"iid": inspector_id})
    active_row = active.first()
    active_id = active_row[0] if active_row else None
    active_tank_type = active_row[1] if active_row else None
    active_sector = active_row[2] if active_row else None
    active_subsector = active_row[3] if active_row else None

    # 통계 기준: 진행중 세션이 있으면 그 세션, 없으면 가장 최근 완료 세션
    if active_id is not None:
        stats_row = (await db.execute(text("""
            SELECT 세션_ID, 총_이미지_수, 양품_수 FROM 검사_세션 WHERE 세션_ID = :sid
        """), {"sid": active_id})).first()
    else:
        stats_row = (await db.execute(text("""
            SELECT 세션_ID, 총_이미지_수, 양품_수 FROM 검사_세션
            WHERE 검사원_ID = :iid AND 세션_상태 = '완료'
            ORDER BY 종료_일시 DESC NULLS LAST LIMIT 1
        """), {"iid": inspector_id})).first()

    session_number = stats_row[0] if stats_row else 0
    total_imgs = stats_row[1] if stats_row else 0
    pass_imgs = stats_row[2] if stats_row else 0
    pass_rate = (pass_imgs / total_imgs * 100.0) if total_imgs > 0 else 0.0

    recent = await db.execute(text("""
        SELECT s.세션_ID, s.탱크_타입, s.시작_일시, s.종료_일시,
               (s.불량_수 > 0) AS has_defect,
               MAX(f.수정_일시) AS last_modified
        FROM 검사_세션 s
        LEFT JOIN 검사_피드백 f ON f.세션_ID = s.세션_ID
        WHERE s.검사원_ID = :iid AND s.세션_상태 = '완료'
        GROUP BY s.세션_ID
        ORDER BY s.종료_일시 DESC NULLS LAST
        LIMIT 3
    """), {"iid": inspector_id})
    recent_rows = recent.all()

    return DashboardSummary(
        session_number=session_number,
        today_images=total_imgs,
        today_pass_rate=round(pass_rate, 1),
        active_session_id=active_id,
        active_tank_type=active_tank_type,
        active_sector=active_sector,
        active_subsector=active_subsector,
        recent_sessions=[
            SessionSummary(
                session_id=r[0],
                tank_type=r[1],
                started_at=r[2].isoformat(),
                ended_at=r[3].isoformat() if r[3] else None,
                last_modified_at=r[5].isoformat() if r[5] else None,
                has_defect=bool(r[4]),
            )
            for r in recent_rows
        ],
    )


@router.patch("/sessions/{session_id}/end")
async def end_session(
    session_id: int,
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    s = (await db.execute(text("""
        SELECT 세션_상태 FROM 검사_세션 WHERE 세션_ID = :sid AND 검사원_ID = :iid
    """), {"sid": session_id, "iid": inspector_id})).first()
    if s is None:
        raise HTTPException(status_code=404, detail={"error": "NOT_FOUND"})
    if s[0] != '진행중':
        raise HTTPException(status_code=400, detail={"error": "SESSION_NOT_ACTIVE"})

    incomplete = (await db.execute(text("""
        SELECT COUNT(*) FROM 검사_결과 r
        JOIN 검사_이미지 i ON i.이미지_ID = r.이미지_ID
        WHERE i.세션_ID = :sid AND r.대표_여부=true AND r.결과_처리_상태='미완료'
    """), {"sid": session_id})).scalar()
    if incomplete and incomplete > 0:
        raise HTTPException(status_code=400, detail={"error": "INCOMPLETE_RESULTS_EXIST", "incomplete_count": incomplete})

    end = (await db.execute(text("""
        UPDATE 검사_세션 SET 세션_상태='완료', 종료_일시=NOW()
        WHERE 세션_ID = :sid RETURNING 종료_일시
    """), {"sid": session_id})).first()
    await db.commit()

    return {"session_id": session_id, "status": "완료", "ended_at": end[0].isoformat()}
