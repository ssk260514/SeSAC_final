-- ============================================
-- 1. pgvector 확장 활성화
-- ============================================
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================
-- 2. ENUM 타입
-- ============================================
CREATE TYPE 모델_유형_ENUM AS ENUM ('TFLITE', 'PTH');
CREATE TYPE 세션_상태_ENUM AS ENUM ('진행중', '완료');
CREATE TYPE 추론_위치_ENUM AS ENUM ('단말', '서버');
CREATE TYPE 결과_처리_상태_ENUM AS ENUM ('완료', '미완료');

-- ============================================
-- 3. 마스터 테이블
-- ============================================

CREATE TABLE 공정 (
    공정_ID            SERIAL PRIMARY KEY,
    공정_이름          VARCHAR(50) NOT NULL UNIQUE,
    결함_유형_목록     JSONB NOT NULL DEFAULT '[]',
    신뢰도_임계값      FLOAT NOT NULL DEFAULT 0.85,
    서버_재확인_임계값  FLOAT NOT NULL DEFAULT 0.70,
    활성_여부          BOOLEAN NOT NULL DEFAULT false,
    생성_일시          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE 검사원 (
    검사원_ID          SERIAL PRIMARY KEY,
    이름               VARCHAR(50) NOT NULL,
    부서               VARCHAR(100),
    비밀번호_해시      VARCHAR(255) NOT NULL,
    활성_여부          BOOLEAN NOT NULL DEFAULT true,
    생성_일시          TIMESTAMP NOT NULL DEFAULT NOW(),
    마지막_로그인_일시 TIMESTAMP
);

CREATE TABLE 사용자_설정 (
    설정_ID            SERIAL PRIMARY KEY,
    검사원_ID          INT NOT NULL UNIQUE REFERENCES 검사원(검사원_ID) ON DELETE CASCADE,
    푸시_알림          BOOLEAN NOT NULL DEFAULT true,
    언어               VARCHAR(5) NOT NULL DEFAULT 'ko',
    생성_일시          TIMESTAMP NOT NULL DEFAULT NOW(),
    수정_일시          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE 검사_구역 (
    탱크_타입          VARCHAR(2) PRIMARY KEY,
    구역_코드          JSONB NOT NULL,
    구역_설명          VARCHAR(200),
    공정_ID            INT NOT NULL REFERENCES 공정(공정_ID)
);

-- ============================================
-- 4. 모델 레지스트리
-- ============================================

-- 단일 통합 모델: 30클래스(불량 19 + 양품 11). `공정_ID`는 메타로만 유지(NULL 허용) — 모델 선택과 무관.
CREATE TABLE 모델_레지스트리 (
    모델_ID            SERIAL PRIMARY KEY,
    공정_ID            INT REFERENCES 공정(공정_ID),  -- NULL 허용 (단일 모델 — 메타로만 유지)
    모델_버전          VARCHAR(20) NOT NULL,
    모델_유형          모델_유형_ENUM NOT NULL,
    파일_경로          VARCHAR(500) NOT NULL,
    파일_해시          VARCHAR(80),
    클래스_라벨        JSONB NOT NULL,
    활성_여부          BOOLEAN NOT NULL DEFAULT false,
    생성_일시          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_model_active ON 모델_레지스트리(모델_유형, 활성_여부);  -- 단일 모델: 공정_ID 미사용

-- ============================================
-- 5. 트랜잭션 테이블
-- ============================================

CREATE TABLE 검사_세션 (
    세션_ID            SERIAL PRIMARY KEY,
    검사원_ID          INT NOT NULL REFERENCES 검사원(검사원_ID),
    공정_ID            INT NOT NULL REFERENCES 공정(공정_ID),
    탱크_타입          VARCHAR(2) NOT NULL REFERENCES 검사_구역(탱크_타입),
    선택_구역          VARCHAR(50) NOT NULL,
    선택_세부위치      VARCHAR(50) NOT NULL,
    총_이미지_수       INT NOT NULL DEFAULT 0,
    양품_수            INT NOT NULL DEFAULT 0,
    불량_수            INT NOT NULL DEFAULT 0,
    세션_상태          세션_상태_ENUM NOT NULL DEFAULT '진행중',
    시작_일시          TIMESTAMP NOT NULL DEFAULT NOW(),
    종료_일시          TIMESTAMP
);

-- 1일 1세션 정책 DB-level enforce
CREATE UNIQUE INDEX uniq_active_session_per_inspector
    ON 검사_세션(검사원_ID) WHERE 세션_상태 = '진행중';

CREATE INDEX idx_session_inspector_date ON 검사_세션(검사원_ID, 시작_일시 DESC);

CREATE TABLE 검사_이미지 (
    이미지_ID          SERIAL PRIMARY KEY,
    세션_ID            INT NOT NULL REFERENCES 검사_세션(세션_ID) ON DELETE CASCADE,
    이미지_경로        VARCHAR(500) NOT NULL,
    촬영_일시          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_image_session ON 검사_이미지(세션_ID);

CREATE TABLE 검사_결과 (
    결과_ID            SERIAL PRIMARY KEY,
    이미지_ID          INT NOT NULL REFERENCES 검사_이미지(이미지_ID) ON DELETE CASCADE,
    공정_ID            INT NOT NULL REFERENCES 공정(공정_ID),
    모델_ID            INT REFERENCES 모델_레지스트리(모델_ID),
    추론_위치          추론_위치_ENUM NOT NULL,
    대표_여부          BOOLEAN NOT NULL DEFAULT false,
    품질_여부          BOOLEAN NOT NULL,
    결함_유형          VARCHAR(50) NOT NULL,
    신뢰도_점수        FLOAT NOT NULL,
    상위_예측          JSONB,
    추론_지연_ms       INT,
    사람_재확인_필요   BOOLEAN NOT NULL DEFAULT false,
    "Grad-CAM_경로"   VARCHAR(500),
    결과_처리_상태     결과_처리_상태_ENUM NOT NULL DEFAULT '미완료',
    시작_일시          TIMESTAMP NOT NULL DEFAULT NOW(),
    완료_일시          TIMESTAMP
);

CREATE INDEX idx_result_image ON 검사_결과(이미지_ID);
CREATE INDEX idx_result_representative ON 검사_결과(이미지_ID) WHERE 대표_여부 = true;

CREATE TABLE 검사_피드백 (
    피드백_ID          SERIAL PRIMARY KEY,
    결과_ID            INT NOT NULL UNIQUE REFERENCES 검사_결과(결과_ID) ON DELETE CASCADE,
    검사원_ID          INT NOT NULL REFERENCES 검사원(검사원_ID),
    세션_ID            INT NOT NULL REFERENCES 검사_세션(세션_ID),
    검사원_수정_여부   BOOLEAN NOT NULL DEFAULT false,
    수정된_결함_유형   VARCHAR(50),
    심각도             VARCHAR(20),
    의견               TEXT,
    최종_조치_내용     TEXT,
    생성_일시          TIMESTAMP NOT NULL DEFAULT NOW(),
    수정_일시          TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================
-- 6. RAG 테이블
-- ============================================

CREATE TABLE 매뉴얼 (
    매뉴얼_ID          SERIAL PRIMARY KEY,
    공정_ID            INT NOT NULL REFERENCES 공정(공정_ID),
    제목               VARCHAR(200) NOT NULL,
    내용               TEXT NOT NULL,
    내용_벡터          VECTOR(1024),
    출처               VARCHAR(200),
    페이지_번호        INT,
    청크_순서          INT,
    생성_일시          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_manual_process ON 매뉴얼(공정_ID);
-- 벡터 검색 인덱스 (행 100개 이상 들어간 후 만들기 권장 → 14번 단계에서 추가)

CREATE TABLE 조치_권고 (
    권고_ID            SERIAL PRIMARY KEY,
    결과_ID            INT NOT NULL REFERENCES 검사_결과(결과_ID) ON DELETE CASCADE,
    조치_요약          VARCHAR(500),
    조치_상세          TEXT,
    생성_일시          TIMESTAMP NOT NULL DEFAULT NOW(),
    수정_일시          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE 조치_권고_매뉴얼 (
    매핑_ID            SERIAL PRIMARY KEY,
    권고_ID            INT NOT NULL REFERENCES 조치_권고(권고_ID) ON DELETE CASCADE,
    매뉴얼_ID          INT NOT NULL REFERENCES 매뉴얼(매뉴얼_ID),
    순위               INT NOT NULL CHECK (순위 BETWEEN 1 AND 3),
    유사도_점수        FLOAT NOT NULL,
    생성_일시          TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(권고_ID, 순위),
    UNIQUE(권고_ID, 매뉴얼_ID)
);
