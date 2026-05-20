from fastapi import APIRouter, Depends, HTTPException, Path, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.db import get_db
from app.api.deps import get_current_inspector_id


router = APIRouter()


@router.get("/sessions/{session_id}/results")
async def list_session_results(
    session_id: int = Path(...),
    status: str = Query(default="all"),
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    where = "i.세션_ID = :sid AND r.대표_여부 = true"
    params = {"sid": session_id}
    if status == "완료":
        where += " AND r.결과_처리_상태 = '완료'"
    elif status == "미완료":
        where += " AND r.결과_처리_상태 = '미완료'"

    res = await db.execute(text(f"""
        SELECT i.이미지_ID, i.이미지_경로, i.촬영_일시,
               r.결함_유형, r.품질_여부, r.신뢰도_점수, r.결과_처리_상태,
               r.사람_재확인_필요,
               (SELECT 결과_ID FROM 검사_결과 r2 WHERE r2.이미지_ID = i.이미지_ID AND r2.추론_위치='서버' LIMIT 1) AS server_result_id,
               (SELECT 결과_ID FROM 검사_결과 r2 WHERE r2.이미지_ID = i.이미지_ID AND r2.추론_위치='단말' LIMIT 1) AS device_result_id,
               (SELECT 피드백_ID FROM 검사_피드백 f WHERE f.결과_ID = r.결과_ID LIMIT 1) AS feedback_id
        FROM 검사_이미지 i
        JOIN 검사_결과 r ON r.이미지_ID = i.이미지_ID
        WHERE {where}
        ORDER BY i.촬영_일시 DESC
    """), params)
    return [
        {
            "image_id": row[0],
            "thumbnail_url": row[1],
            "captured_at": row[2].isoformat(),
            "defect_type": row[3],
            "is_defect": not bool(row[4]),
            "confidence": row[5],
            "result_status": row[6],
            "needs_human_review": row[7],
            "has_server_result": row[8] is not None,
            "has_device_result": row[9] is not None,
            "feedback_status": "확정" if row[10] is not None else None,
        }
        for row in res.all()
    ]


@router.get("/images/{image_id}/detail")
async def get_image_detail(
    image_id: int = Path(...),
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    img = (await db.execute(text("""
        SELECT 이미지_ID, 이미지_경로, 촬영_일시 FROM 검사_이미지 WHERE 이미지_ID = :id
    """), {"id": image_id})).first()
    if img is None:
        raise HTTPException(status_code=404, detail={"error": "NOT_FOUND"})

    results = (await db.execute(text("""
        SELECT 결과_ID, 추론_위치, 결함_유형, 신뢰도_점수, 추론_지연_ms,
               상위_예측, "Grad-CAM_경로", 사람_재확인_필요
        FROM 검사_결과 WHERE 이미지_ID = :id
    """), {"id": image_id})).all()

    device = next((r for r in results if r[1] == '단말'), None)
    server = next((r for r in results if r[1] == '서버'), None)

    action = None
    if server is not None:
        rec = (await db.execute(text("""
            SELECT 권고_ID, 조치_요약, 조치_상세 FROM 조치_권고 WHERE 결과_ID = :rid
        """), {"rid": server[0]})).first()
        if rec is not None:
            srcs = (await db.execute(text("""
                SELECT m.매뉴얼_ID, m.제목, m.페이지_번호, m.청크_순서, x.순위, x.유사도_점수
                FROM 조치_권고_매뉴얼 x JOIN 매뉴얼 m ON m.매뉴얼_ID = x.매뉴얼_ID
                WHERE x.권고_ID = :rid ORDER BY x.순위
            """), {"rid": rec[0]})).all()
            action = {
                "recommendation_id": rec[0],
                "summary": rec[1],
                "detail": rec[2],
                "source_manuals": [
                    {"manual_id": s[0], "title": s[1], "page": s[2], "chunk_order": s[3], "rank": s[4], "similarity": s[5]}
                    for s in srcs
                ],
            }

    def _row_to_dict(r, gradcam=False):
        if r is None:
            return None
        out = {
            "result_id": r[0], "defect_type": r[2], "confidence": r[3],
            "inference_ms": r[4], "top3_predictions": r[5],
            "needs_human_review": r[7],
        }
        if gradcam:
            out["gradcam_url"] = r[6]
        return out

    return {
        "image": {
            "image_id": img[0],
            "image_url": img[1],
            "gradcam_url": server[6] if server else None,
            "captured_at": img[2].isoformat(),
        },
        "device_result": _row_to_dict(device),
        "server_result": _row_to_dict(server, gradcam=True),
        "action_guide": action or {
            "recommendation_id": None,
            "summary": "[MVP 더미] 14번 단계에서 RAG로 생성됩니다.",
            "detail": "",
            "source_manuals": [],
        },
        "feedback": None,
    }
