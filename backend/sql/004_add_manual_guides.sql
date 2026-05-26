-- 매뉴얼 테이블에 사전 작성 가이드 컬럼 추가 (RAG/LLM 제거에 따른 마이그레이션)
-- 기존 운영 DB에 적용. 신규 설치는 001_schema.sql에 이미 포함됨.

ALTER TABLE 매뉴얼
    ADD COLUMN IF NOT EXISTS 조치_요약 VARCHAR(500),
    ADD COLUMN IF NOT EXISTS 조치_상세 TEXT;
