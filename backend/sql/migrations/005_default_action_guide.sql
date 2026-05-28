-- 기존 검사_결과 backfill — 조치_권고가 없는 결과에 매뉴얼(결함_유형) 가이드를 채워넣는다.
-- 사전 조건: scripts/seed_manuals.py 로 매뉴얼 테이블이 채워져 있어야 함.
-- 신규 결과는 inspect.py 의 _apply_default_action_guide 가 자동 처리하므로,
-- 이 파일은 단말-only 등 과거에 가이드 없이 쌓인 결과를 1회 보정하는 용도다.
--
-- 룩업은 결함_유형 단독(공정_ID 무시) — 단말 경로의 process_id 부정확 문제를 피한다.

-- (1) 조치_권고 backfill + (2) 조치_권고_매뉴얼 출처 링크 backfill 을 한 번에.
WITH ins AS (
    INSERT INTO 조치_권고 (결과_ID, 조치_요약, 조치_상세, 생성_일시, 수정_일시)
    SELECT r.결과_ID, m.조치_요약, m.조치_상세, NOW(), NOW()
    FROM 검사_결과 r
    JOIN LATERAL (
        SELECT 매뉴얼_ID, 조치_요약, 조치_상세
        FROM 매뉴얼 WHERE 결함_유형 = r.결함_유형
        ORDER BY 매뉴얼_ID LIMIT 1
    ) m ON true
    LEFT JOIN 조치_권고 c ON c.결과_ID = r.결과_ID
    WHERE c.권고_ID IS NULL
    RETURNING 권고_ID, 결과_ID
)
INSERT INTO 조치_권고_매뉴얼 (권고_ID, 매뉴얼_ID, 순위, 유사도_점수)
SELECT ins.권고_ID, m.매뉴얼_ID, 1, 1.0
FROM ins
JOIN 검사_결과 r ON r.결과_ID = ins.결과_ID
JOIN LATERAL (
    SELECT 매뉴얼_ID FROM 매뉴얼 WHERE 결함_유형 = r.결함_유형
    ORDER BY 매뉴얼_ID LIMIT 1
) m ON true;
