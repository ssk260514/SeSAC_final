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

    OPENAI_API_KEY: str = ""
    SERVER_BASE_URL: str = "http://localhost:8000"  # .env에서 실제 기기 IP로 오버라이드 필요


settings = Settings()
