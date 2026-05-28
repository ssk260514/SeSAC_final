"""S3 운영 데이터 버킷(lng-inspection-data) 헬퍼.

프리픽스 3종:
  inspections/{YYYY}/{MM}/{DD}/{uuid}.jpg  — 표시용 원본 (전수)
  samples/{YYYY}/{MM}/{DD}/{label}/{uuid}.jpg — 학습셋 (복사본, 라벨=서버 재추론/검사원 수정값)
  heatmaps/{YYYY}/{MM}/{DD}/{uuid}.png     — Grad-CAM (서버 불량 분류분만)

samples/·heatmaps/ 는 inspections/ 와 동일한 {date}/{uuid} 를 재사용한다.
이 결정성 덕분에 라벨 수정 MOVE 가 inspections uri 만으로 기존 sample 키를 재구성할 수 있다.
"""
import aioboto3

from app.core.config import settings


def _session():
    return aioboto3.Session()


def _client(session):
    return session.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_REGION,
    )


def _key_of(s3_uri: str) -> str:
    """s3://bucket/key → key"""
    rest = s3_uri[len("s3://"):]
    return rest.split("/", 1)[1]


def parse_inspections_uri(s3_uri: str) -> tuple[str, str]:
    """inspections uri → (date_path='YYYY/MM/DD', file_uuid)"""
    key = _key_of(s3_uri)              # inspections/2026/05/28/uuid.jpg
    parts = key.split("/")
    date_path = "/".join(parts[1:4])   # 2026/05/28
    file_uuid = parts[4].rsplit(".", 1)[0]
    return date_path, file_uuid


async def put_image(data: bytes, prefix: str, date_path: str, file_uuid: str, ext: str) -> str:
    """{prefix}/{date_path}/{file_uuid}.{ext} 로 업로드하고 s3 uri 반환."""
    key = f"{prefix}/{date_path}/{file_uuid}.{ext}"
    content_type = "image/png" if ext == "png" else "image/jpeg"
    session = _session()
    async with _client(session) as s3:
        await s3.put_object(
            Bucket=settings.S3_DATA_BUCKET, Key=key, Body=data, ContentType=content_type
        )
    return f"s3://{settings.S3_DATA_BUCKET}/{key}"


async def copy_to_samples(src_inspections_uri: str, label: str) -> str:
    """inspections 원본을 samples/{date}/{label}/{uuid}.jpg 로 복사 (서버 사이드 CopyObject)."""
    date_path, file_uuid = parse_inspections_uri(src_inspections_uri)
    src_key = _key_of(src_inspections_uri)
    dest_key = f"samples/{date_path}/{label}/{file_uuid}.jpg"
    session = _session()
    async with _client(session) as s3:
        await s3.copy_object(
            Bucket=settings.S3_DATA_BUCKET,
            CopySource={"Bucket": settings.S3_DATA_BUCKET, "Key": src_key},
            Key=dest_key,
        )
    return f"s3://{settings.S3_DATA_BUCKET}/{dest_key}"


async def move_samples_label(src_inspections_uri: str, old_label: str, new_label: str) -> None:
    """라벨 변경 MOVE: 기존 samples/{old} DELETE(best-effort) + samples/{new} COPY(항상)."""
    if old_label == new_label:
        return
    date_path, file_uuid = parse_inspections_uri(src_inspections_uri)
    src_key = _key_of(src_inspections_uri)
    old_key = f"samples/{date_path}/{old_label}/{file_uuid}.jpg"
    new_key = f"samples/{date_path}/{new_label}/{file_uuid}.jpg"
    session = _session()
    async with _client(session) as s3:
        try:
            await s3.delete_object(Bucket=settings.S3_DATA_BUCKET, Key=old_key)
        except Exception:
            pass  # 미샘플링이었으면 없음 — 무시
        await s3.copy_object(
            Bucket=settings.S3_DATA_BUCKET,
            CopySource={"Bucket": settings.S3_DATA_BUCKET, "Key": src_key},
            Key=new_key,
        )


async def generate_presigned(s3_uri: str, expires: int = 600) -> str:
    """s3:// uri → presigned GET URL. s3:// 가 아니면 원본 그대로 반환(레거시 통과)."""
    if not s3_uri or not s3_uri.startswith("s3://"):
        return s3_uri
    key = _key_of(s3_uri)
    session = _session()
    async with _client(session) as s3:
        return await s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.S3_DATA_BUCKET, "Key": key},
            ExpiresIn=expires,
        )
