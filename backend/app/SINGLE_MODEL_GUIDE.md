# 단일 통합 모델 기준 — backend/app 신규 작성 가이드

> **배경**: 본 프로젝트는 "공정별 6개 모델 분기"에서 **단일 통합 모델 1개(30클래스 = 불량 19 + 양품 11)** 로 전환되었습니다. `backend/app/` 의 inspect·tank·session·result·settings·ota 라우터는 아직 미구현 상태이므로, **처음부터 단일 모델 전제로 작성**해야 합니다. 본 문서는 그 작성 가이드입니다.
>
> **확정 사항**: 모델 파일명 `best_model_v5_datamatch_full.pth/.tflite`, 클래스 30개, 양품 판별 = `'양품' in defect_type`, 전역 임계값 0.85/0.70 (`app/core/config.py`의 `GLOBAL_CONFIDENCE_THRESHOLD`/`SERVER_RECHECK_THRESHOLD`), `모델_레지스트리.공정_ID` NULL 허용.
>
> **참조**: `명세서/계획 변경 내용.md` §6-3, `명세서/기능_명세서.md`, `명세서/API_SPEC.md`.

---

## 1. 신규 라우터 작성 시 공통 규칙

| 항목 | 규칙 |
|---|---|
| 모델 선택 | **단일 모델 1개 가정**. `WHERE 모델_유형 IN ('PTH','TFLITE') AND 활성_여부=true` (공정_ID 조건 **금지**) |
| 양품 판별 | `defect_type` 클래스명에 `"양품"` 포함 여부 — `'양품' in defect_type` (서버) / `defectType.contains('양품')` (Flutter) |
| 신뢰도 임계값 | `settings.GLOBAL_CONFIDENCE_THRESHOLD` (0.85) · `settings.SERVER_RECHECK_THRESHOLD` (0.70). `공정.신뢰도_임계값` DB 조회 금지(전역 단일) |
| `process_id` | 폼/JSON 필드로 받되 **모델 선택에 사용 금지**. 위치 기록·RAG 매뉴얼 범위 한정용 메타 |
| RAG 매뉴얼 검색 | `WHERE 매뉴얼.공정_ID = 세션.공정_ID` **유지** (공정별 매뉴얼 분리는 불변) |

---

## 2. 라우터별 작성 포인트

### 2-1. `app/api/tank.py` (신규) — 탱크/공정 자동 매핑
- `GET /api/tank-types/{tank_type}/process`
- 응답의 `defect_types`: `모델_레지스트리.클래스_라벨` JSONB 30개 그대로 반환 (공정 단위 분기 없음)
- 응답의 `confidence_threshold`: `settings.GLOBAL_CONFIDENCE_THRESHOLD`
- 응답의 `has_tflite_model`: `SELECT EXISTS(SELECT 1 FROM 모델_레지스트리 WHERE 모델_유형='TFLITE' AND 활성_여부=true)` (공정_ID 조건 없음)
- 응답의 `process_id`: 검사_구역에서 `tank_type` → `공정_ID` 매핑은 그대로 (위치 메타용)

### 2-2. `app/api/inspect.py` (신규) — 분류·INFER 시리즈
- INFER-001 (단말 결과 등록), INFER-002 (서버 추론), INFER-003 (Top-3), INFER-004 (양품 샘플링), INFER-005 (오프라인 배치) 전부 단일 모델 전제
- 분류기는 **30클래스** 출력 (`out_features=30`)
- `품질_여부` 도출: `is_pass = '양품' in top1_class` (사용자 전제 4)
- `사람_재확인_필요`: `top1_confidence < settings.SERVER_RECHECK_THRESHOLD`
- `process_id` 폼 필드는 받되 모델 선택에 사용하지 않음. RAG 검색에서만 `세션.공정_ID` 활용

### 2-3. `app/api/session.py` (신규) — 검사 세션
- 단일 모델과 무관 — 기존 명세 그대로
- `검사_세션.공정_ID`는 검사_구역 매핑값 그대로 저장 (위치 기록·RAG 메타)

### 2-4. `app/api/result.py` (신규) — 결과 처리
- 결함 유형 드롭다운 데이터 소스: `모델_레지스트리.클래스_라벨` 30개 (공정.결함_유형_목록 사용 금지)
- 검사원 수정 결함 유형은 30클래스 중 하나여야 함

### 2-5. `app/api/settings.py` (신규)
- 단일 모델과 무관. 푸시 알림·언어 설정만

### 2-6. `app/api/ota.py` (신규) — OTA 모델 갱신
- `GET /api/model/version` — **`process_id` 쿼리 파라미터 없음**. 응답에도 `process_id` 필드 없음. 단일 활성 TFLITE 1개 반환
- `PATCH /api/admin/models/{model_id}/activate` (OTA-002):
  - `X-Admin-API-Key` 헤더 검증 → `settings.ADMIN_API_KEY` 와 비교
  - 트랜잭션:
    ```sql
    BEGIN;
    UPDATE 모델_레지스트리 SET 활성_여부=false WHERE 모델_유형=? AND 활성_여부=true;  -- 공정_ID 조건 제거
    UPDATE 모델_레지스트리 SET 활성_여부=true WHERE 모델_ID=?;
    COMMIT;
    ```
  - 응답 JSON의 `activated`에 `process_id` 필드 포함 금지

---

## 3. 미구현 → 단일 모델 신규 작성 우선순위

1. `app/api/tank.py` (PROC-001, ZONE-001, SESS-001 기반 화면 2 동작)
2. `app/api/inspect.py` (INFER-001/002/003, MVP 단말+서버 추론 핵심)
3. `app/api/result.py` (FEEDBACK-001, 결과 처리 화면 6)
4. `app/api/ota.py` (OTA-001/002, 3주차 OTA 도입 시점)
5. `app/api/session.py` (SESS-002/003)
6. `app/api/settings.py` (SETTINGS-001)

각 라우터는 본 가이드 §1 공통 규칙 + §2 라우터별 포인트를 따른다.

---

## 4. 학습팀 답 도착 시 재정합 대상

§8 미해결 항목(모델 30클래스 통합 최종본 검증·클래스 ID 0~29 순서) 답 도착 시 다음을 재정합:

- `backend/sql/002_seed.sql` — 모델_레지스트리 `클래스_라벨` JSONB (현 placeholder)
- `backend/app/api/inspect.py` 의 `_CLASSES` 또는 모델 출력 인덱스 매핑
- `inspection_app/lib/features/capture/data/local/tflite_inference_service.dart` 의 `_unifiedLabels`
- `tutorial/02·09·14` 의 _CLASSES 배열

순서가 다르면 위 4곳을 동일하게 재배치.

---

## 5. 참조

- 영향 분석서: [명세서/계획 변경 내용.md](../../명세서/계획%20변경%20내용.md) §6 · §9
- 기능 ID 매핑: [명세서/기능_명세서.md](../../명세서/기능_명세서.md) (PROC-001, ZONE-001, INFER-001~005, OTA-001/002, FEEDBACK-001 등)
- API 계약: [명세서/API_SPEC.md](../../명세서/API_SPEC.md)
- ERD: [명세서/schema_diagram.md](../../명세서/schema_diagram.md)
