from urllib.parse import urlparse

import aioboto3
from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.db import get_db
from app.core.config import settings
from app.api.deps import get_current_inspector_id

router = APIRouter()


def _parse_s3_path(file_path: str) -> tuple[str, str]:
    """`파일_경로`를 (bucket, key)로 해석.

    - `s3://bucket/key/...`  → 그대로 사용
    - 그 외(레거시 `firebase://name` 등) → 모델 버킷 + `name.tflite` 로 폴백
    """
    if file_path.startswith("s3://"):
        p = urlparse(file_path)
        return p.netloc, p.path.lstrip("/")
    name = file_path.split("://", 1)[-1].rstrip("/").split("/")[-1]
    if not name.endswith(".tflite"):
        name = f"{name}.tflite"
    return settings.S3_MODELS_BUCKET, name


async def _presign_get(bucket: str, key: str) -> str:
    """모델 다운로드용 시간제한 presigned GET URL 발급."""
    session_factory = aioboto3.Session()
    async with session_factory.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_REGION,
    ) as s3:
        return await s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=settings.MODEL_URL_EXPIRES_SEC,
        )


@router.get("/model/version")
async def get_model_version(
    _: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    """단일 통합 모델의 최신 활성 TFLITE 정보. process_id 파라미터 없음 (OTA-001)."""
    row = (await db.execute(text("""
        SELECT 모델_ID, 모델_버전, 파일_경로, 파일_해시, 클래스_라벨
        FROM 모델_레지스트리
        WHERE 모델_유형 = 'TFLITE' AND 활성_여부 = true
        LIMIT 1
    """))).first()
    if row is None:
        raise HTTPException(status_code=404, detail={"error": "MODEL_NOT_READY"})

    # S3 presigned URL 발급 — 앱은 이 시간제한 URL로만 .tflite를 받는다 (Firebase ML 대체).
    bucket, key = _parse_s3_path(row[2])   # row[2] = 파일_경로
    download_url = await _presign_get(bucket, key)

    return {
        "model_id": row[0],
        "version": row[1],
        "download_url": download_url,   # presigned GET (MODEL_URL_EXPIRES_SEC 후 만료)
        "file_hash": row[3],            # "sha256:..." — 앱이 다운로드 후 검증
        "class_labels": row[4],         # {"0":"균열-도장", ... "29":"폼스프레이양품-우레탄폼"}
    }


@router.patch("/admin/models/{model_id}/activate")
async def activate_model(
    model_id: int,
    x_admin_api_key: str = Header(default=""),
    db: AsyncSession = Depends(get_db),
):
    """검증 완료 모델 활성화 (OTA-002). 단일 모델 — 동일 모델_유형 내 기존 활성 1개 자동 비활성."""
    if x_admin_api_key != settings.ADMIN_API_KEY:
        raise HTTPException(status_code=401, detail={"error": "ADMIN_AUTH_FAILED"})

    target = (await db.execute(text("""
        SELECT 모델_유형 FROM 모델_레지스트리 WHERE 모델_ID = :id
    """), {"id": model_id})).first()
    if target is None:
        raise HTTPException(status_code=404, detail={"error": "NOT_FOUND"})
    model_type = target[0]

    # 단일 모델 정책: 공정_ID 조건 없음 — 모델_유형별 활성 1개만 (계획 변경 내용 §6-3)
    await db.execute(text("""
        UPDATE 모델_레지스트리 SET 활성_여부 = false
        WHERE 모델_유형 = :mt AND 활성_여부 = true
    """), {"mt": model_type})
    await db.execute(text("""
        UPDATE 모델_레지스트리 SET 활성_여부 = true WHERE 모델_ID = :id
    """), {"id": model_id})
    await db.commit()
    return {"activated": {"model_id": model_id, "model_type": model_type}}
