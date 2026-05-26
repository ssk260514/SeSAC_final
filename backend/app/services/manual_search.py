from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text


async def search_manuals(db: AsyncSession, defect_type: str, process_id: int, top_k: int = 3):
    """결함 유형으로 매뉴얼을 직접 조회한다. 미매핑 시 해당 공정 전체 매뉴얼을 반환한다."""
    res = await db.execute(text("""
        SELECT 매뉴얼_ID, 제목, 내용, 조치_요약, 조치_상세,
               출처, 페이지_번호, 청크_순서
        FROM 매뉴얼
        WHERE 공정_ID = :pid AND 결함_유형 = :defect_type
        ORDER BY 청크_순서
        LIMIT :k
    """), {"pid": process_id, "defect_type": defect_type, "k": top_k})

    rows = res.all()

    if not rows:
        # 미등록 결함 유형 — 해당 공정의 전체 매뉴얼로 폴백
        res = await db.execute(text("""
            SELECT 매뉴얼_ID, 제목, 내용, 조치_요약, 조치_상세,
                   출처, 페이지_번호, 청크_순서
            FROM 매뉴얼
            WHERE 공정_ID = :pid
            ORDER BY 청크_순서
            LIMIT :k
        """), {"pid": process_id, "k": top_k})
        rows = res.all()

    return [
        {
            "manual_id": r[0],
            "title": r[1],
            "content": r[2],
            "summary": r[3],
            "detail": r[4],
            "source": r[5],
            "page": r[6],
            "chunk_order": r[7],
        }
        for r in rows
    ]
