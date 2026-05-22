from sentence_transformers import SentenceTransformer
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text


_model_singleton: SentenceTransformer | None = None


def get_embedder() -> SentenceTransformer:
    global _model_singleton
    if _model_singleton is None:
        _model_singleton = SentenceTransformer("BAAI/bge-m3")
    return _model_singleton


async def search_manuals(db: AsyncSession, query_text: str, process_id: int, top_k: int = 3):
    vec = get_embedder().encode(query_text, normalize_embeddings=True).tolist()
    res = await db.execute(text("""
        SELECT 매뉴얼_ID, 제목, 내용, 출처, 페이지_번호, 청크_순서,
               1 - (내용_벡터 <=> CAST(:vec AS vector)) AS similarity
        FROM 매뉴얼
        WHERE 공정_ID = :pid AND 내용_벡터 IS NOT NULL
        ORDER BY 내용_벡터 <=> CAST(:vec AS vector)
        LIMIT :k
    """), {"vec": str(vec), "pid": process_id, "k": top_k})
    return [
        {
            "manual_id": r[0],
            "title": r[1],
            "content": r[2],
            "source": r[3],
            "page": r[4],
            "chunk_order": r[5],
            "similarity": float(r[6]),
        }
        for r in res.all()
    ]
