CREATE TABLE 멱등성_요청 (
    client_request_id UUID PRIMARY KEY,
    검사원_ID        INT NOT NULL REFERENCES 검사원(검사원_ID),
    처리_결과         JSONB,
    생성_일시         TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 30일 이상 된 항목은 정리 (운영자 cron)
CREATE INDEX idx_idempotency_created ON 멱등성_요청(생성_일시);
