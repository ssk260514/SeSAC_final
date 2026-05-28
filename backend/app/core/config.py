from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    DATABASE_URL: str
    DATABASE_URL_SYNC: str
    JWT_SECRET_KEY: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    ADMIN_API_KEY: str
    ENV: str = "dev"

    # 단일 통합 모델 전제 — 신뢰도 임계값은 전역 단일값(공정별 차등 없음).
    # `공정.신뢰도_임계값`·`공정.서버_재확인_임계값` DB 컬럼은 유지하되,
    # 운영상 모든 행이 아래 값과 동일하도록 보장. 코드에서는 본 설정을 우선 참조.
    GLOBAL_CONFIDENCE_THRESHOLD: float = 0.85   # 단말 양품 자동 종결 컷오프
    SERVER_RECHECK_THRESHOLD: float = 0.70      # 서버 사람_재확인_필요 분기 임계값

    SERVER_BASE_URL: str = "http://localhost:8000"  # .env에서 실제 기기 IP로 오버라이드 필요

    # S3 운영 데이터 버킷 — inspections/ (원본), samples/ (학습셋), heatmaps/ (Grad-CAM)
    # 모든 검사 이미지·히트맵·학습셋을 단일 버킷의 프리픽스로 분리 보관.
    S3_DATA_BUCKET: str = "lng-inspection-data"
    # 모델 전용 버킷 — 샘플/검사 데이터와 IAM 경계 분리 (Firebase ML 분리 계정 대체).
    # 앱에는 AWS 키를 주지 않고, 백엔드가 발급한 presigned URL로만 다운로드시킨다.
    S3_MODELS_BUCKET: str = "lng-inspection-models"
    MODEL_URL_EXPIRES_SEC: int = 600  # presigned URL 만료(초) — 다운로드에 충분하되 짧게
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_REGION: str = "ap-northeast-2"


settings = Settings()
