from datetime import datetime, timezone

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
    for candidate in [r for r in [server, device] if r is not None]:
        rec = (await db.execute(text("""
            SELECT 권고_ID, 조치_요약, 조치_상세 FROM 조치_권고 WHERE 결과_ID = :rid
        """), {"rid": candidate[0]})).first()
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
            break

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

    feedback = None
    for candidate in [r for r in [server, device] if r is not None]:
        fb = (await db.execute(text("""
            SELECT 피드백_ID, 수정된_결함_유형, 심각도, 의견, 최종_조치_내용
            FROM 검사_피드백 WHERE 결과_ID = :rid
        """), {"rid": candidate[0]})).first()
        if fb is not None:
            feedback = {
                "feedback_id": fb[0],
                "modified_defect_type": fb[1],
                "severity": fb[2],
                "opinion": fb[3],
                "final_action_content": fb[4],
            }
            break

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
            "summary": "조치 가이드를 생성하지 못했습니다.",
            "detail": "",
            "source_manuals": [],
        },
        "feedback": feedback,
    }


@router.post("/results/{result_id}/feedback")
async def save_feedback(
    result_id: int,
    body: dict,
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    r = (await db.execute(text("""
        SELECT 결과_ID, 결함_유형, (SELECT 세션_ID FROM 검사_이미지 WHERE 이미지_ID = r.이미지_ID)
        FROM 검사_결과 r WHERE 결과_ID = :rid
    """), {"rid": result_id})).first()
    if r is None:
        raise HTTPException(status_code=404, detail={"error": "NOT_FOUND"})

    original_type = r[1]
    session_id = body.get("session_id") or r[2]
    modified_type = body.get("modified_defect_type")
    inspector_modified = modified_type is not None and modified_type != original_type

    upsert = await db.execute(text("""
        INSERT INTO 검사_피드백 (
            결과_ID, 검사원_ID, 세션_ID,
            검사원_수정_여부, 수정된_결함_유형, 심각도, 의견, 최종_조치_내용,
            생성_일시, 수정_일시
        ) VALUES (
            :rid, :iid, :sid, :modified, :mtype, :sev, :op, :fa, NOW(), NOW()
        )
        ON CONFLICT (결과_ID) DO UPDATE SET
            검사원_수정_여부 = EXCLUDED.검사원_수정_여부,
            수정된_결함_유형 = EXCLUDED.수정된_결함_유형,
            심각도 = EXCLUDED.심각도,
            의견 = EXCLUDED.의견,
            최종_조치_내용 = EXCLUDED.최종_조치_내용,
            수정_일시 = NOW()
        RETURNING 피드백_ID
    """), {
        "rid": result_id, "iid": inspector_id, "sid": session_id,
        "modified": inspector_modified, "mtype": modified_type,
        "sev": body.get("severity"), "op": body.get("opinion"),
        "fa": body.get("final_action_content"),
    })
    feedback_id = upsert.scalar_one()

    await db.execute(text("""
        UPDATE 검사_결과 SET 결과_처리_상태='완료', 완료_일시=NOW() WHERE 결과_ID = :rid
    """), {"rid": result_id})

    await db.commit()
    return {
        "feedback_id": feedback_id,
        "result_id": result_id,
        "inspector_modified": inspector_modified,
        "result_status": "완료",
        "saved_at": datetime.now(timezone.utc).isoformat(),
    }


@router.patch("/recommendations/{recommendation_id}")
async def update_recommendation(
    recommendation_id: int,
    body: dict,
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    detail = body.get("action_detail")
    if detail is None:
        raise HTTPException(status_code=400, detail={"error": "MISSING_FIELD"})
    res = await db.execute(text("""
        UPDATE 조치_권고 SET 조치_상세 = :d, 수정_일시 = NOW()
        WHERE 권고_ID = :rid RETURNING 권고_ID
    """), {"d": detail, "rid": recommendation_id})
    if res.first() is None:
        raise HTTPException(status_code=404, detail={"error": "NOT_FOUND"})
    await db.commit()
    return {"recommendation_id": recommendation_id, "saved_at": datetime.now(timezone.utc).isoformat()}
