# API 명세서 — 선박 LNG 탱크 부품 품질 검사 AI 앱

> **버전**: v2.1
> **기준일**: 2026-05-13
> **참조 문서**: 기능_명세서.md (v2), ERD.md (확정판, 12 테이블), 아키텍처_플랜_초안.md (4주 / 1주 MVP 로드맵)
> **대상**: Flutter 앱 팀 / 백엔드 팀 공용

### v2.1 변경 요약 (v2.0 대비)
- `공정.서버_재확인_임계값 FLOAT DEFAULT 0.70` 신규 컬럼 — INFER-002 `needs_human_review` 분기 기준
- `검사_결과.결함_유형 VARCHAR NOT NULL` 직접 컬럼화 (이전: `상위_예측[0].class`에서 파생)
- `검사_세션` 1일 1세션 정책을 **DB-level partial UNIQUE index**로 강제 (`uniq_active_session_per_inspector`)
- `검사_이미지.탱크_타입` FK 제거 — `검사_세션.탱크_타입` JOIN으로 조회 (정규화)
- `검사_피드백.결과_ID UNIQUE` 제약 명시 → PostgreSQL `ON CONFLICT (결과_ID) DO UPDATE` upsert
- `세션_상태` ENUM에서 `'중단'` 값 제거 (Post-MVP에 `ALTER TYPE` 마이그레이션으로 재추가)
- `조치_권고_매뉴얼` 조인 테이블 UNIQUE 제약 명시: `(권고_ID, 순위)`, `(권고_ID, 매뉴얼_ID)`
- MVP 1주차 vs 2~4주차 단계별 적용 범위 표 추가 (§5)

---

## 1. 공통 규격

| 항목 | 규격 |
|---|---|
| 기본 URL | `http://{서버IP}:8000/api` |
| 인증 방식 | `Authorization: Bearer {JWT_ACCESS_TOKEN}` |
| 관리자 인증 | `X-Admin-API-Key: {ADMIN_API_KEY}` (OTA-002 전용, 검사원 JWT와 분리) |
| 기본 Content-Type | `application/json` |
| 파일 업로드 Content-Type | `multipart/form-data` |
| 에러 응답 형식 | `{"error": "ERROR_CODE", "message": "..."}` (기능 명세서 기준) |
| 액세스 토큰 유효기간 | 30분 |
| 리프레시 토큰 유효기간 | 7일 |
| 매뉴얼 조회 방식 | 결함 유형 기반 직접 SELECT (`매뉴얼.공정_ID + 결함_유형` 인덱스) — 임베딩·벡터 검색·LLM 미사용 |

---

## 2. 엔드포인트 총괄표

| Method | Path | 기능 ID | 설명 | 인증 |
|---|---|---|---|---|
| POST | `/api/auth/login` | AUTH-001 | 로그인 + JWT 발급 | ❌ |
| POST | `/api/auth/refresh` | AUTH-002 | 토큰 갱신 | ❌ |
| POST | `/api/auth/logout` | AUTH-003 | 로그아웃 (audit 로그) | ✅ |
| GET | `/api/tank-types` | ZONE-001 | 탱크 유형 목록 조회 | ✅ |
| GET | `/api/tank-types/{tank_type}/process` | ZONE-002 | 탱크 유형-공정 매핑 조회 | ✅ |
| GET | `/api/processes` | PROC-001 | 공정 목록 조회 | ✅ |
| POST | `/api/sessions` | SESS-001 | 세션 생성 (1일 1세션 — 당일 진행중 세션 있으면 409) | ✅ |
| GET | `/api/sessions` | SESS-002 | 세션 이력 목록 조회 | ✅ |
| PATCH | `/api/sessions/{id}/end` | SESS-003 | 세션 종료 | ✅ |
| GET | `/api/dashboard/summary` | SESS-004 | 대시보드 요약 조회 | ✅ |
| POST | `/api/inspect` | INFER-002 | 서버 정밀 분석 (분류+Grad-CAM+매뉴얼 직접 조회) | ✅ |
| POST | `/api/inspect/local-result` | INFER-003 | 양품 단말 결과 기록 | ✅ |
| POST | `/api/inspect/sample-upload` | INFER-004 | 양품 10% 샘플 업로드 | ✅ |
| POST | `/api/inspect/offline-batch` | INFER-005 | 오프라인 큐 배치 업로드 (멱등성, 3주차) | ✅ |
| GET | `/api/model/version` | OTA-001 | 모델 버전 확인 (OTA) | ✅ |
| PATCH | `/api/admin/models/{id}/activate` | OTA-002 | 모델 활성화 (시스템 인증, 운영용) | X-Admin-API-Key |
| GET | `/api/sessions/{id}/results` | RESULT-001 | 세션별 결과 목록 조회 | ✅ |
| GET | `/api/images/{id}/detail` | RESULT-002 | 이미지 상세 조회 | ✅ |
| POST | `/api/results/{id}/feedback` | FEEDBACK-001 | 피드백 저장 (확정) | ✅ |
| PATCH | `/api/recommendations/{id}` | FEEDBACK-002 | 조치 권고 수정 | ✅ |
| POST | `/api/sessions/{id}/finalize` | FEEDBACK-003 | 결과 일괄 확정 현황 조회 | ✅ |
| GET | `/api/settings` | SETTINGS-001a | 사용자 설정 조회 | ✅ |
| PATCH | `/api/settings` | SETTINGS-001b | 사용자 설정 수정 | ✅ |

---

## 3. 엔드포인트 상세 명세

---

### AUTH-001 — 로그인

| 항목 | 내용 |
|---|---|
| 기능 ID | AUTH-001 |
| API | `POST /api/auth/login` |
| 인증 | ❌ |
| 설명 | 검사원 ID + 비밀번호로 인증, JWT 토큰 쌍 발급 |

**요청 (Request)**
```json
{
  "inspector_id": 1,
  "name": "홍길동",
  "password": "plain_text_password"
}
```

> 화면 1에서 검사원 ID, 성함, 비밀번호 입력. 역할(role) 입력 없음 — 앱 사용자는 검사원 단일 역할. 부서는 인증 성공 후 DB에서 자동 조회.

**처리 로직**
1. `검사원` 테이블에서 `검사원_ID`로 조회
2. `활성_여부 == false` → 403 "비활성 계정"
3. 비밀번호를 `비밀번호_해시`와 bcrypt 비교
4. 일치 → JWT 액세스 토큰(30분) + 리프레시 토큰(7일) 발급
5. `마지막_로그인_일시` UPDATE
6. 불일치 → 401 "인증 실패"

**응답 (Response) 200**
```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "inspector": {
    "inspector_id": 1,
    "name": "홍길동",
    "department": "품질관리팀"
  }
}
```

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `검사원` | 검사원_ID, 비밀번호_해시, 활성_여부, 이름, 부서 |
| UPDATE | `검사원` | 마지막_로그인_일시 |

---

### AUTH-002 — 토큰 갱신

| 항목 | 내용 |
|---|---|
| 기능 ID | AUTH-002 |
| API | `POST /api/auth/refresh` |
| 인증 | ❌ |
| 설명 | 리프레시 토큰으로 새 액세스 토큰 발급 |

**Flutter 측 처리**
Dio Interceptor가 401 응답 감지 → 자동으로 `/api/auth/refresh` 호출 → 새 토큰으로 원래 요청 재시도

---

### AUTH-003 — 로그아웃 *(신규)*

| 항목 | 내용 |
|---|---|
| 기능 ID | AUTH-003 |
| API | `POST /api/auth/logout` |
| 인증 | ✅ (만료 토큰도 허용) |
| 설명 | 로그아웃 audit 로그 기록. 1주차 MVP는 stdout 로그만. Post-MVP에 리프레시 토큰 블랙리스트 확장 예정 |

**요청 본문**: 없음 (Authorization 헤더만 사용)

**처리 로직 (MVP)**
1. JWT 검증 (만료 토큰도 허용 — 로그아웃이므로 401 미반환)
2. audit 로그 기록 (검사원_ID, 로그아웃 시각, 요청 IP)
3. 200 OK 반환 (서버 측 토큰 블랙리스트 없음)

**응답 200**
```json
{
  "message": "로그아웃되었습니다.",
  "logged_out_at": "2026-05-12T10:30:00Z"
}
```

**Flutter 측 처리**
- 응답 성공/실패 무관하게 `flutter_secure_storage`에서 JWT 삭제 후 화면 1로 라우팅

---

### ZONE-001 — 탱크 유형 목록 조회

| 항목 | 내용 |
|---|---|
| 기능 ID | ZONE-001 |
| API | `GET /api/tank-types` |
| 인증 | ✅ |
| 화면 | 화면 2 (탱크 유형 선택 — 1단계 카드) |
| 설명 | 탱크 유형(B/C) 목록 + 구역 코드(nested JSONB) + 매핑 공정 정보 조회 |

**응답 (Response) 200**
```json
[
  {
    "tank_type": "B",
    "sectors": {
      "외부": ["지지대"]
    },
    "description": "B형 탱크 (자립식 각형)",
    "process": {
      "process_id": 1,
      "process_name": "표면처리"
    }
  },
  {
    "tank_type": "C",
    "sectors": {
      "외벽": ["경판", "바디"],
      "내부": ["바닥", "격벽"],
      "외부": ["지지대", "플랫폼"]
    },
    "description": "C형 탱크 (멤브레인식)",
    "process": {
      "process_id": 1,
      "process_name": "표면처리"
    }
  }
]
```

> `sectors`: `구역(key) → 세부 위치 배열(value)` 형태의 nested JSONB. 화면 2의 구역 드롭다운(1단계)에는 key 목록, 세부 위치 드롭다운(2단계)에는 선택된 구역의 value 배열을 표시.

**처리 로직**
1. `검사_구역` 테이블 전체 조회 (2행: 탱크 B, C)
2. 각 탱크 유형에 매핑된 `공정` 정보 JOIN 반환

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `검사_구역` | 탱크_타입(PK), 구역_코드(JSONB), 구역_설명, 공정_ID |
| READ | `공정` | 공정_ID, 공정_이름, 활성_여부 |
| READ | `모델_레지스트리` | 모델_유형, 파일_경로, 활성_여부 (단일 모델 — 공정_ID 조건 없음) |

---

### ZONE-002 — 탱크 유형-공정 매핑 조회

| 항목 | 내용 |
|---|---|
| 기능 ID | ZONE-002 |
| API | `GET /api/tank-types/{tank_type}/process` |
| 인증 | ✅ |
| 화면 | 화면 2 (2단계: 구역+위치 선택 시) |
| 설명 | 특정 탱크 유형에 매핑된 공정 + 구역 목록 조회 |

**Path 파라미터**
| 파라미터 | 타입 | 설명 |
|---|---|---|
| tank_type | STRING | `B` 또는 `C` |

**응답 (Response) 200**
```json
{
  "tank_type": "B",
  "sectors": {
    "외부": ["지지대"]
  },
  "process": {
    "process_id": 1,
    "process_name": "표면처리",
    "confidence_threshold": 0.85,
    "defect_types": ["균열-도장", "균열-보온재", "도막떨어짐-도장", "도막분리-도장", "도장흐름-도장", "보온재손상-보온재", "스크래치-도장", "스크래치-모재", "스크래치-보온재", "탱크클리닝불량-모재", "표면양품-도장", "표면양품-모재", "표면양품-보온재"]
  }
}
```

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `검사_구역` | 탱크_타입(PK), 구역_코드(JSONB), 공정_ID |
| READ | `공정` | 전체 |

---

### PROC-001 — 공정 목록 조회

| 항목 | 내용 |
|---|---|
| 기능 ID | PROC-001 |
| API | `GET /api/processes` |
| 인증 | ✅ |
| 설명 | 전체 공정 목록 조회 (활성/비활성 포함). 내부 로직/운영 도구용 |

**응답 (Response) 200**
```json
[
  {
    "process_id": 1,
    "process_name": "표면처리",
    "defect_types": ["균열-도장", "균열-보온재", "도막떨어짐-도장", "도막분리-도장", "도장흐름-도장", "보온재손상-보온재", "스크래치-도장", "스크래치-모재", "스크래치-보온재", "탱크클리닝불량-모재", "표면양품-도장", "표면양품-모재", "표면양품-보온재"],
    "confidence_threshold": 0.85,
    "is_active": true,
    "has_tflite_model": true
  },
  {
    "process_id": 2,
    "process_name": "용접",
    "defect_types": ["용접불량-조인트", "용접블로우홀-조인트", "용접양품-조인트"],
    "confidence_threshold": 0.85,
    "is_active": false,
    "has_tflite_model": false
  }
]
```

**처리 로직**
1. `공정` 테이블 전체 조회
2. 단일 활성 TFLITE 모델 존재 여부 확인(`활성_여부=true AND 모델_유형='TFLITE'`) → 모든 공정 행에 동일 `has_tflite_model` 값 반환 (단일 모델 — 공정 무관)

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `공정` | 전체 |
| READ | `모델_레지스트리` | 모델_유형, 활성_여부 (공정_ID 조건 제거 — 단일) |

---

### SESS-001 — 세션 생성

| 항목 | 내용 |
|---|---|
| 기능 ID | SESS-001 |
| API | `POST /api/sessions` |
| 인증 | ✅ |
| 화면 | 화면 3 (대시보드 "검사 시작" 버튼) |
| 설명 | 새 검사 세션 생성. 당일 진행중 세션 존재 시 **409** 반환 (기존 세션 자동 반환 아님) |

**요청 (Request)**
```json
{
  "tank_type": "B",
  "selected_sector": "외부",
  "selected_subsector": "지지대"
}
```

> `process_id`는 서버가 `tank_type`에서 자동 매핑. `selected_subsector`는 화면 2 2단계 드롭다운에서 선택한 세부 위치. `process_id`는 위치 기록·매뉴얼 범위 한정용 메타이며, 모델은 단일이므로 모델 선택과 무관.

**처리 로직**
1. 당일 해당 검사원의 기존 진행 중 세션 확인 → 존재하면 `409 DAILY_SESSION_EXISTS` 반환 (body에 `existing_session_id` 포함)
2. `검사_구역` 테이블에서 `탱크_타입`으로 `공정_ID` 조회
3. `구역_코드[selected_sector]` 배열에 `selected_subsector` 포함 여부 검증
4. 해당 `공정.활성_여부` 확인 → false면 400 "비활성 공정"
5. 해당 공정의 TFLITE 모델 존재 확인 → 없으면 400 "모델 미준비"
6. `검사_세션` INSERT

> **DB-level race condition 방어**: `CREATE UNIQUE INDEX uniq_active_session_per_inspector ON 검사_세션(검사원_ID) WHERE 세션_상태='진행중';` partial unique index가 적용되어 있어, 단계 1의 SELECT-THEN-INSERT 사이에 동시 호출이 들어와도 두 번째 INSERT는 PostgreSQL `23505 unique_violation` 으로 거절됨. 서버는 이 예외를 잡아 동일한 `409 DAILY_SESSION_EXISTS` 응답으로 변환한다.

**응답 200 — 신규 세션 생성 성공**
```json
{
  "session_id": 42,
  "status": "진행중",
  "started_at": "2026-05-08T09:30:00Z",
  "tank_type": "B",
  "selected_sector": "외부",
  "selected_subsector": "지지대",
  "process": {
    "process_id": 1,
    "process_name": "표면처리",
    "confidence_threshold": 0.85
  }
}
```

**응답 409 — 당일 진행중 세션 존재**
```json
{
  "error": "DAILY_SESSION_EXISTS",
  "message": "오늘 이미 진행 중인 세션이 있습니다. 검사 이력에서 '이어서 검사'를 이용해주세요.",
  "existing_session_id": 42
}
```

> 클라이언트 처리: 409 수신 시 토스트 메시지 표시 + 검사 이력 탭(화면 4)으로 자동 이동.

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `검사_구역` | 탱크_타입 → 공정_ID |
| READ | `공정` | 활성_여부 |
| READ | `모델_레지스트리` | 모델_유형, 활성_여부 (공정_ID 조건 제거 — 단일) |
| WRITE | `검사_세션` | INSERT (검사원_ID, 공정_ID, 탱크_타입, 선택_구역, 선택_세부위치, 세션_상태, 시작_일시) |

---

### SESS-002 — 세션 이력 목록 조회

| 항목 | 내용 |
|---|---|
| 기능 ID | SESS-002 |
| API | `GET /api/sessions` |
| 인증 | ✅ |
| 화면 | 화면 3 (대시보드 최근 이력) |
| 설명 | 현재 검사원의 세션 목록 조회 (최신순). 상태 필터 지원 |

**쿼리 파라미터**
| 파라미터 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| status | STRING | `all` | 필터: `all` / `진행중` / `완료` (MVP는 `'중단'` 미지원 — `세션_상태` ENUM 값 제거) |
| limit | INT | 20 | 페이지 크기 |
| offset | INT | 0 | 오프셋 |

**응답 (Response) 200**
```json
[
  {
    "session_id": 42,
    "process_name": "표면처리",
    "tank_type": "B",
    "selected_sector": "외부",
    "selected_subsector": "지지대",
    "status": "완료",
    "started_at": "2026-05-08T09:30:00Z",
    "ended_at": "2026-05-08T10:45:00Z",
    "total_images": 23,
    "pass_count": 20,
    "fail_count": 3
  }
]
```

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `검사_세션` | 전체 (WHERE 검사원_ID, ORDER BY 시작_일시 DESC) |
| READ | `공정` | 공정_이름 (JOIN via 공정_ID) |

---

### SESS-003 — 세션 종료

| 항목 | 내용 |
|---|---|
| 기능 ID | SESS-003 |
| API | `PATCH /api/sessions/{session_id}/end` |
| 인증 | ✅ |
| 화면 | 화면 4 ("검사 완료" 버튼) |
| 설명 | 진행 중인 세션을 '완료' 상태로 변경. 미완료 건 존재 시 종료 불가 |

**처리 로직**
1. 세션_상태 == '진행중' 확인 → 아니면 400
2. 세션 내 `결과_처리_상태='미완료'` 건수 확인 → 1건이라도 있으면 400
3. UPDATE: `세션_상태='완료'`, `종료_일시=NOW()`

**응답 200**
```json
{
  "session_id": 42,
  "status": "완료",
  "ended_at": "2026-05-08T10:45:00Z",
  "completed_count": 18,
  "incomplete_count": 2
}
```

---

### SESS-004 — 대시보드 요약 조회

| 항목 | 내용 |
|---|---|
| 기능 ID | SESS-004 |
| API | `GET /api/dashboard/summary` |
| 인증 | ✅ |
| 화면 | 화면 3 (대시보드 — 통계 카드 3개 + 최근 이력) |
| 설명 | 오늘 날짜 기준 세션 번호, 이미지 수, 양품률 + 최근 완료 세션 3건 |

**응답 (Response) 200**
```json
{
  "session_number": 42,
  "today_images": 67,
  "today_pass_rate": 87.5,
  "active_session_id": 42,
  "recent_sessions": [
    {
      "session_id": 41,
      "tank_type": "B",
      "started_at": "2026-05-08T09:30:00Z",
      "ended_at": "2026-05-08T10:45:00Z",
      "last_modified_at": "2026-05-08T11:00:00Z",
      "has_defect": true
    }
  ]
}
```

> `active_session_id`: 당일 진행중 세션 ID. 없으면 `null`. 클라이언트가 "검사 시작" 버튼 클릭 전 사전 가드용.
> `recent_sessions`: 세션_상태='완료' 세션만, 최근 3건, ORDER BY 종료_일시 DESC NULLS LAST.

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `검사원` | 이름, 부서 |
| READ | `검사_세션` | WHERE 검사원_ID AND 시작_일시 >= 오늘 |
| READ | `검사_세션` | WHERE 세션_상태='진행중' AND 시작_일시 >= 오늘 (`active_session_id`) |
| READ | `검사_세션` | WHERE 세션_상태='완료' ORDER BY 종료_일시 DESC NULLS LAST LIMIT 3 |
| READ | `검사_피드백` | MAX(수정_일시) per 세션_ID |

---

### INFER-002 — 서버 정밀 분석

| 항목 | 내용 |
|---|---|
| 기능 ID | INFER-002 |
| API | `POST /api/inspect` |
| 인증 | ✅ |
| Content-Type | `multipart/form-data` |
| 화면 | 화면 5 (카메라 백그라운드) → 결과 화면 4 확인 |
| 설명 | 불량/저신뢰도 이미지 서버 전송 → 정밀 분석 (분류 + Grad-CAM + RAG) |

**요청 (Request)**
```
image:            [바이너리 이미지 파일]
session_id:       42
process_id:       1
tank_type:        "B"
on_device_result: {
  "defect_type": "균열-도장",
  "confidence": 0.78,
  "inference_ms": 180,
  "top3_predictions": [
    {"class": "균열-도장", "confidence": 0.78},
    {"class": "스크래치-도장", "confidence": 0.12},
    {"class": "도막떨어짐-도장", "confidence": 0.04}
  ]
}
```

**서버 처리 흐름**
```
1. JWT 인증 확인
2. 이미지 전처리 (384×384, ImageNet 정규화)
3. MobileNetV3(.pth, 단일 통합 30클래스) 재추론
   ├─ 신뢰도 < SERVER_RECHECK_THRESHOLD (전역 0.70 — config.py) → 사람_재확인_필요=true
   └─ 신뢰도 ≥ SERVER_RECHECK_THRESHOLD                          → 정상 분류
4. Grad-CAM 히트맵 생성 → uploads/heatmaps/*.png 저장 (운영 단계 S3 마이그레이션)
5. 매뉴얼 직접 조회 (LLM·임베딩·벡터 검색 없음):
   a. SELECT 매뉴얼_ID, 제목, 내용, 조치_요약, 조치_상세, 출처, 페이지_번호, 청크_순서
      FROM 매뉴얼 WHERE 공정_ID=:pid AND 결함_유형=:defect_type
      ORDER BY 청크_순서 LIMIT 3
   b. 결과 0행이면 WHERE 공정_ID=:pid 로 폴백
   c. 매칭 청크의 사전 작성 `조치_요약`(≤500자)·`조치_상세`(단계별)를 그대로 사용
6. 결과 통합 JSON 응답
7. BackgroundTasks 비동기 저장:
   - 원본 이미지 → uploads/images/*.jpg (운영 단계 S3 마이그레이션)
   - 검사_이미지 INSERT (탱크_타입 컬럼 없음 — 세션 JOIN으로 조회)
   - 검사_결과 INSERT × 1~2 (서버 항상: 대표_여부=true / 단말 동봉 시 추가: 대표_여부=false)
     · 결함_유형 VARCHAR NOT NULL 직접 컬럼에 최종 클래스 저장
     · 상위_예측 JSONB에 Top-3 동시 저장
   - 조치_권고 INSERT + 조치_권고_매뉴얼 INSERT × 1~3
     · UNIQUE (권고_ID, 순위), UNIQUE (권고_ID, 매뉴얼_ID) 제약 적용
   - 검사_세션 카운터 UPDATE (총_이미지_수 / 양품_수 / 불량_수)
```

> `SERVER_RECHECK_THRESHOLD`(서버 재확인 임계값)는 전역 단일값 0.70. 코드는 `config.py`의 본 설정을 우선 참조하며, `공정.서버_재확인_임계값` 컬럼은 유지하되 모든 행이 동일 값. INFER-002는 공정별 차등 없음.

**응답 (Response) 200**
```json
{
  "image_id": 156,
  "server_result": {
    "result_id": 312,
    "defect_type": "균열-도장",
    "confidence": 0.923,
    "inference_ms": 1240,
    "needs_human_review": false
  },
  "on_device_result": {
    "result_id": 311,
    "defect_type": "균열-도장",
    "confidence": 0.783,
    "inference_ms": 180
  },
  "heatmap_url": "https://s3.../heatmap_156.png",
  "action_guide": {
    "recommendation_id": 89,
    "summary": "도장 균열 부위 재도장 필요",
    "detail": "1) 균열 부위 주변 50mm 범위를 사포(#180)로 연마\n2) 프라이머 도포 후 24시간 건조\n3) 상도 2회 도장",
    "source_manuals": [
      {"manual_id": 23, "title": "표면처리 정비 지침서", "page": 45, "chunk_order": 3, "rank": 1, "similarity": 1.0},
      {"manual_id": 24, "title": "표면처리 정비 지침서", "page": 47, "chunk_order": 5, "rank": 2, "similarity": 1.0},
      {"manual_id": 25, "title": "표면처리 정비 지침서", "page": 48, "chunk_order": 6, "rank": 3, "similarity": 1.0}
    ]
  }
}
```

> `source_manuals`: 결함 유형 직접 조회로 매칭된 청크 메타데이터 배열. `rank`=`청크_순서` ASC 순서(1=가장 작은 청크), `similarity`=직접 조회이므로 기본 `1.0` (필드는 호환성 유지 목적으로 응답에 포함).

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| WRITE | `검사_이미지` | INSERT (세션_ID, 이미지_경로=S3 URL, 촬영_일시) — **탱크_타입 컬럼 없음** (세션 JOIN으로 조회) |
| WRITE | `검사_결과` | INSERT × 2 (이미지_ID, 공정_ID, 모델_ID, 추론_위치, 대표_여부, 품질_여부, **결함_유형**, 신뢰도_점수, 상위_예측, 추론_지연_ms, 사람_재확인_필요, Grad-CAM_경로, 결과_처리_상태='미완료') |
| WRITE | `조치_권고` | INSERT (결과_ID, 조치_요약, 조치_상세) — **매뉴얼_ID FK 없음** (조치_권고_매뉴얼로 이관) |
| WRITE | `조치_권고_매뉴얼` | INSERT × 1~3 (권고_ID, 매뉴얼_ID, 순위 1~3, 유사도_점수=1.0, 생성_일시) |
| READ | `매뉴얼` | `WHERE 공정_ID=? AND 결함_유형=?` 직접 조회 (`idx_manual_defect_type`). 미매칭 시 `WHERE 공정_ID=?` 폴백 — `조치_요약`/`조치_상세`/`출처`/`페이지_번호`/`청크_순서` 추출 |
| READ | `공정` | 신뢰도_임계값 (단말 컷오프), **서버_재확인_임계값** (사람_재확인_필요 분기) — 전역 단일값 (공정별 차등 없음) |
| UPDATE | `검사_세션` | 총_이미지_수 += 1, 양품_수/불량_수 += 1 (품질_여부 기준) |

---

### INFER-003 — 양품 단말 결과 기록

| 항목 | 내용 |
|---|---|
| 기능 ID | INFER-003 |
| API | `POST /api/inspect/local-result` |
| 인증 | ✅ |
| 화면 | 화면 5 (카메라 백그라운드) |
| 설명 | 단말에서 양품 판정된 결과를 서버에 기록 (이미지 없이 메타만 전송) |

**요청 (Request)**
```json
{
  "session_id": 42,
  "process_id": 1,
  "tank_type": "B",
  "defect_type": "표면양품-도장",
  "confidence": 0.952,
  "top3_predictions": [
    {"class": "표면양품-도장", "confidence": 0.952},
    {"class": "표면양품-보온재", "confidence": 0.038},
    {"class": "스크래치-도장", "confidence": 0.010}
  ],
  "inference_ms": 165,
  "model_id": 7,
  "is_sampling": false,
  "captured_at": "2026-05-08T09:35:12Z"
}
```

> `defect_type`: 모델이 출력한 정확한 클래스명 (예: `"표면양품-도장"`). 단순 `"양품"` 문자열 아님.
> 품질_여부(BOOLEAN) 도출: `defect_type`에 `"양품"` 문자열이 포함되는지로 서버가 판별 (통합 30클래스 공통 규칙 — 공정 무관).

**처리 로직**
1. `검사_이미지` INSERT
2. `검사_결과` INSERT 1행 (추론_위치='단말', 대표_여부=true, 결과_처리_상태='완료')
3. `검사_세션` UPDATE: 총_이미지_수 += 1, 양품_수 += 1
4. `is_sampling == true`이면 이미지 업로드 큐 추가

---

### INFER-004 — 양품 10% 샘플링 업로드

| 항목 | 내용 |
|---|---|
| 기능 ID | INFER-004 |
| API | `POST /api/inspect/sample-upload` |
| 인증 | ✅ |
| Content-Type | `multipart/form-data` |
| 설명 | 양품 이미지 중 10% 확률로 이미지 업로드 (학습 데이터 확보) |

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| UPDATE | `검사_이미지` | 이미지_경로=S3 URL (샘플 업로드 후 경로 갱신) |

---

### INFER-005 — 오프라인 큐 배치 업로드 *(신규 — 3주차 구현)*

| 항목 | 내용 |
|---|---|
| 기능 ID | INFER-005 |
| API | `POST /api/inspect/offline-batch` |
| 인증 | ✅ |
| Content-Type | `multipart/form-data` |
| 설명 | 네트워크 끊김 중 sqflite에 누적된 불량/저신뢰도 이미지 일괄 업로드. INFER-002의 배치 버전. 멱등성 키(`client_request_id`) 지원 |

**요청**
```
images[]:  [바이너리 이미지 배열, N개]
metadata:  JSON 배열 (images[]와 동일 순서)
```

`metadata` 배열 항목:
```json
[
  {
    "client_request_id": "550e8400-e29b-41d4-a716-446655440000",
    "session_id": 42,
    "process_id": 1,
    "tank_type": "B",
    "captured_at": "2026-05-08T09:35:12Z",
    "on_device_result": {
      "defect_type": "균열-도장",
      "confidence": 0.78,
      "inference_ms": 180,
      "top3_predictions": [
        {"class": "균열-도장", "confidence": 0.78},
        {"class": "스크래치-도장", "confidence": 0.12},
        {"class": "스크래치-도장", "confidence": 0.04}
      ]
    }
  }
]
```

> 배치 크기 제한: 1회 최대 50건. 초과 시 `400 BATCH_SIZE_LIMIT_EXCEEDED`. 클라이언트가 50건 단위 청크 분할 순차 호출.
> `client_request_id`: UUID v4 멱등성 키 — 동일 UUID 재수신 시 이전 결과 반환 (중복 INSERT 방지).

**응답 200**
```json
{
  "batch_size": 5,
  "succeeded_count": 4,
  "failed_count": 1,
  "results": [
    {
      "client_request_id": "550e8400-e29b-41d4-a716-446655440000",
      "status": "success",
      "image_id": 156,
      "server_result": {"result_id": 312, "defect_type": "균열-도장", "confidence": 0.923, "inference_ms": 1240, "needs_human_review": false},
      "on_device_result": {"result_id": 311, "defect_type": "균열-도장", "confidence": 0.78, "inference_ms": 180},
      "heatmap_url": "https://s3.../heatmap_156.png",
      "action_guide": {
        "recommendation_id": 89,
        "summary": "도장 균열 부위 재도장 필요",
        "detail": "...",
        "source_manuals": [
          {"manual_id": 23, "title": "표면처리 정비 지침서", "page": 45, "chunk_order": 3, "rank": 1, "similarity": 0.91}
        ]
      }
    },
    {
      "client_request_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
      "status": "failed",
      "error_code": "INFERENCE_ERROR",
      "error_message": "이미지 디코딩 실패"
    }
  ]
}
```

---

### OTA-001 — 모델 버전 확인

| 항목 | 내용 |
|---|---|
| 기능 ID | OTA-001 |
| API | `GET /api/model/version` |
| 인증 | ✅ |
| 설명 | 단일 활성 TFLite 모델 정보 조회 (앱 시작 시 OTA 체크용 — 공정 무관) |

**쿼리 파라미터**: 없음 (단일 모델 — `process_id` 등 파라미터 불필요)

**응답 (Response) 200**
```json
{
  "model_id": 7,
  "version": "v2",
  "download_url": "https://lng-inspection-models.s3.ap-northeast-2.amazonaws.com/best_model_v5_datamatch_full.tflite?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Expires=600&...",
  "file_hash": "sha256:abc123...",
  "class_labels": {
    "0": "용접불량-조인트",
    "1": "용접블로우홀-조인트",
    "2": "용접양품-조인트",
    "3": "절단불량-모재",
    "4": "절단불량-보온재",
    "5": "절단양품-모재",
    "6": "절단양품-보온재",
    "7": "바인딩불량-케이블타이",
    "8": "바인딩양품-케이블타이",
    "9": "케이블설치불량-케이블그랜드",
    "10": "케이블설치양품-케이블그랜드",
    "11": "케이블손상-케이블",
    "12": "케이블양품-케이블",
    "13": "볼트체결불량-파이프",
    "14": "볼트체결양품-파이프",
    "15": "폼스프레이불량-우레탄폼",
    "16": "폼스프레이양품-우레탄폼",
    "17": "균열-도장",
    "18": "균열-보온재",
    "19": "도막떨어짐-도장",
    "20": "도막분리-도장",
    "21": "도장흐름-도장",
    "22": "보온재손상-보온재",
    "23": "스크래치-도장",
    "24": "스크래치-모재",
    "25": "스크래치-보온재",
    "26": "탱크클리닝불량-모재",
    "27": "표면양품-도장",
    "28": "표면양품-모재",
    "29": "표면양품-보온재"
  }
}
```

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `모델_레지스트리` | WHERE 모델_유형='TFLITE' + 활성_여부=true (단일 — 공정_ID 조건 없음) |

---

### OTA-002 — 모델 활성화 *(신규 — 운영용)*

| 항목 | 내용 |
|---|---|
| 기능 ID | OTA-002 |
| API | `PATCH /api/admin/models/{model_id}/activate` |
| 인증 | `X-Admin-API-Key` 헤더 (환경변수 `ADMIN_API_KEY`, 검사원 JWT와 분리) |
| 설명 | 검증 완료 모델 활성화. 동일 (공정_ID, 모델_유형) 내 기존 활성 모델 자동 비활성화 |

**처리 로직 (단일 트랜잭션)**
1. `X-Admin-API-Key` 헤더 검증 → 미일치 시 401 `ADMIN_AUTH_FAILED`
2. 대상 `model_id` 조회 → 없으면 404
3. 동일 (공정_ID, 모델_유형) 기존 활성 모델 `활성_여부=false`
4. 대상 모델 `활성_여부=true`

**응답 200**
```json
{
  "activated": {"model_id": 7, "model_type": "TFLITE", "version": "v2"},
  "deactivated_previous": [{"model_id": 5, "version": "v1"}],
  "activated_at": "2026-05-12T10:00:00Z"
}
```

> 1주차 MVP: 본 API 미구현. 운영자가 SQL로 직접 활성화. 2~3주차 OTA 도입 시 구현.

---

### RESULT-001 — 세션별 결과 목록 조회

| 항목 | 내용 |
|---|---|
| 기능 ID | RESULT-001 |
| API | `GET /api/sessions/{session_id}/results` |
| 인증 | ✅ |
| 화면 | 화면 4 (검사 이력 — 카드 리스트) |
| 설명 | 세션의 전체 이미지 + 결과 목록. 필터링 지원 |

**쿼리 파라미터**
| 파라미터 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| status | STRING | `all` | `all` / `완료` / `미완료` |

**응답 (Response) 200**
```json
[
  {
    "image_id": 156,
    "thumbnail_url": "https://s3.../thumb_156.jpg",
    "defect_type": "균열-도장",
    "is_defect": true,
    "confidence": 0.923,
    "is_representative": true,
    "result_status": "완료",
    "has_server_result": true,
    "has_device_result": true,
    "needs_human_review": false,
    "feedback_status": "확정",
    "captured_at": "2026-05-08T09:35:12Z"
  }
]
```

> `thumbnail_url`: MVP는 `이미지_경로`(원본 S3 URL)와 동일 값 반환. Post-MVP에 CloudFront Resizing 도입 시 본 필드만 변경.
> `feedback_status`: 피드백 행 존재 여부로 판별. 행 존재 = `"확정"`, 없으면 `null`.

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `검사_이미지` | WHERE 세션_ID |
| READ | `검사_결과` | WHERE 이미지_ID (단말+서버) |
| READ | `검사_피드백` | WHERE 세션_ID (행 존재 여부) |

---

### RESULT-002 — 이미지 상세 조회

| 항목 | 내용 |
|---|---|
| 기능 ID | RESULT-002 |
| API | `GET /api/images/{image_id}/detail` |
| 인증 | ✅ |
| 화면 | 화면 4-1 (정밀 분석 모달) |
| 설명 | 특정 이미지의 분석 결과 전체 + Top-3 예측 + Grad-CAM + 조치 가이드 상세 |

**응답 (Response) 200**
```json
{
  "image": {
    "image_id": 156,
    "image_url": "https://s3.../original_156.jpg",
    "gradcam_url": "https://s3.../heatmap_156.png",
    "captured_at": "2026-05-08T09:35:12Z"
  },
  "device_result": {
    "result_id": 311,
    "defect_type": "균열-도장",
    "confidence": 0.783,
    "inference_ms": 180,
    "model_version": "v2",
    "model_type": "TFLITE"
  },
  "server_result": {
    "result_id": 312,
    "defect_type": "균열-도장",
    "confidence": 0.923,
    "inference_ms": 1240,
    "model_version": "v2",
    "model_type": "PTH",
    "needs_human_review": false,
    "top3_predictions": [
      {"class": "균열-도장", "confidence": 0.923},
      {"class": "도막떨어짐-도장", "confidence": 0.054},
      {"class": "스크래치-도장", "confidence": 0.023}
    ]
  },
  "action_guide": {
    "recommendation_id": 89,
    "summary": "도장 균열 부위 재도장 필요",
    "detail": "1) 균열 부위 주변 50mm 범위를 사포...",
    "source_manuals": [
      {"manual_id": 23, "title": "표면처리 정비 지침서", "page": 45, "chunk_order": 3, "rank": 1, "similarity": 0.91},
      {"manual_id": 24, "title": "표면처리 정비 지침서", "page": 47, "chunk_order": 5, "rank": 2, "similarity": 0.85},
      {"manual_id": 25, "title": "표면처리 정비 지침서", "page": 48, "chunk_order": 6, "rank": 3, "similarity": 0.78}
    ]
  },
  "feedback": null
}
```

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `검사_이미지` | 이미지_경로 |
| READ | `검사_결과` | WHERE 이미지_ID (2행: 단말+서버), 상위_예측, Grad-CAM_경로 |
| READ | `모델_레지스트리` | 모델_버전, 모델_유형 |
| READ | `조치_권고` | WHERE 결과_ID = 서버 결과 결과_ID |
| READ | `조치_권고_매뉴얼` | WHERE 권고_ID, ORDER BY 순위 |
| READ | `매뉴얼` | 제목, 출처, 페이지_번호, 청크_순서 |
| READ | `검사_피드백` | WHERE 결과_ID |

---

### FEEDBACK-001 — 피드백 저장 (확정)

| 항목 | 내용 |
|---|---|
| 기능 ID | FEEDBACK-001 |
| API | `POST /api/results/{result_id}/feedback` |
| 인증 | ✅ |
| 화면 | 화면 6 (결과 처리) |
| 설명 | AI 결과 검토 후 피드백 저장. 항상 확정 저장. 기존 피드백 있으면 UPDATE |

**요청 (Request)**
```json
{
  "session_id": 42,
  "modified_defect_type": null,
  "severity": "보통",
  "opinion": "Grad-CAM 히트맵과 육안 확인 결과 일치",
  "final_action_content": "재도장 작업 지시서 발행"
}
```

**처리 로직**
1. result_id로 `검사_결과` 조회 (원본 `결함_유형` 컬럼 가져옴)
2. `INSERT INTO 검사_피드백 (...) VALUES (...) ON CONFLICT (결과_ID) DO UPDATE SET ...` upsert — `검사_피드백.결과_ID`에 걸린 UNIQUE 제약이 동시성·중복 INSERT를 방어
3. `검사원_수정_여부` 자동 판별: `modified_defect_type`이 `검사_결과.결함_유형`과 다르면 `true`
4. `검사_결과.결과_처리_상태 = '완료'` UPDATE

**응답 200**
```json
{
  "feedback_id": 56,
  "result_id": 312,
  "inspector_modified": false,
  "result_status": "완료",
  "saved_at": "2026-05-08T10:15:00Z"
}
```

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `검사_결과` | 결과_ID 유효성, 원본 결함유형 |
| WRITE | `검사_피드백` | INSERT or UPDATE (결과_ID UNIQUE 제약) |
| UPDATE | `검사_결과` | 결과_처리_상태='완료' |

---

### FEEDBACK-002 — 조치 권고 수정

| 항목 | 내용 |
|---|---|
| 기능 ID | FEEDBACK-002 |
| API | `PATCH /api/recommendations/{recommendation_id}` |
| 인증 | ✅ |
| 화면 | 화면 6 |
| 설명 | 매뉴얼에서 채택된 조치 가이드를 검사원이 현장 상황에 맞게 수정 |

**요청 (Request)**
```json
{
  "action_detail": "1) 균열 부위 주변 80mm 범위를 사포(#120)로 연마\n2) 프라이머 2회 도포 후 48시간 건조"
}
```

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| UPDATE | `조치_권고` | 조치_상세, 수정_일시 |

---

### FEEDBACK-003 — 결과 일괄 확정 현황 조회

| 항목 | 내용 |
|---|---|
| 기능 ID | FEEDBACK-003 |
| API | `POST /api/sessions/{session_id}/finalize` |
| 인증 | ✅ |
| 화면 | 화면 4 ("검사 완료" 버튼과 연계) |
| 설명 | 세션 피드백 완료 현황 반환. 피드백 행 존재 = 확정 (별도 상태 전이 없음) |

**응답 200**
```json
{
  "session_id": 42,
  "finalized_count": 18,
  "pending_count": 2,
  "pending_image_ids": [157, 159]
}
```

---

### SETTINGS-001a — 사용자 설정 조회

| 항목 | 내용 |
|---|---|
| 기능 ID | SETTINGS-001a |
| API | `GET /api/settings` |
| 인증 | ✅ |
| 화면 | 화면 7 (설정) |
| 설명 | 현재 사용자의 앱 설정 조회. `사용자_설정` 테이블에서 조회. 행 없으면 기본값 반환 |

**응답 200**
```json
{
  "inspector_id": 1,
  "push_notification": true,
  "language": "ko",
  "app_version": "v1.4.2",
  "updated_at": "2026-05-08T11:00:00Z"
}
```

> `updated_at`: 최초 진입 시 (`사용자_설정` 행 없으면) `null` 반환.

**ERD ↔ API 필드 매핑**

| ERD 컬럼 (한글) | API 필드 (영문) | 비고 |
|---|---|---|
| `사용자_설정.검사원_ID` | `inspector_id` | FK UNIQUE — 1:1 |
| `사용자_설정.푸시_알림` | `push_notification` | BOOLEAN, 기본값 `true` |
| `사용자_설정.언어` | `language` | `'ko'` / `'en'`, 기본값 `'ko'` |
| `사용자_설정.수정_일시` | `updated_at` | upsert 시 NOW() 갱신 |

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| READ | `사용자_설정` | WHERE 검사원_ID, 푸시_알림, 언어, 수정_일시 |

---

### SETTINGS-001b — 사용자 설정 수정

| 항목 | 내용 |
|---|---|
| 기능 ID | SETTINGS-001b |
| API | `PATCH /api/settings` |
| 인증 | ✅ |
| 화면 | 화면 7 (설정) |
| 설명 | 앱 설정 변경. UPSERT — 행 없으면 INSERT, 있으면 UPDATE |

**요청 (Request)**
```json
{
  "push_notification": false,
  "language": "en"
}
```

**응답 200**
```json
{
  "message": "설정이 저장되었습니다.",
  "updated_at": "2026-05-08T11:00:00Z"
}
```

**ERD 연동**
| 작업 | 테이블 | 컬럼 |
|---|---|---|
| WRITE | `사용자_설정` | INSERT or UPDATE (검사원_ID UNIQUE 제약) |

---

## 4. 단계별 적용 범위 (아키텍처 플랜 4주 / 1주 MVP 로드맵 기준)

| 엔드포인트 | 1주차 MVP | 2주차 | 3주차 | 4주차 | 비고 |
|---|---|---|---|---|---|
| AUTH-001 / AUTH-002 | ✅ | | | | JWT 자동 갱신 안정화는 4주차 |
| AUTH-003 (logout) | ✅ (audit 로그만) | | | | 토큰 블랙리스트(Redis)는 Post-MVP |
| ZONE-001 / ZONE-002 / PROC-001 | ✅ | | | | |
| SESS-001 ~ SESS-004 | ✅ | | | | 1일 1세션 partial UNIQUE index 적용 |
| INFER-002 (서버 정밀 분석) | ✅ | | | | 1주차는 키워드 검색, 2주차 매뉴얼 직접 조회(`조치_요약`/`조치_상세` 사전 작성)로 교체 |
| INFER-003 (단말 양품 결과) | ❌ | ✅ | | | 1주차는 단말 추론 없음 — 모든 사진 서버 전송 |
| INFER-004 (양품 10% 샘플) | ❌ | | ✅ | | S3 비동기 업로드 |
| INFER-005 (오프라인 배치) | ❌ | | ✅ | | `client_request_id` 멱등성 키 |
| OTA-001 (모델 버전) | ❌ | | ✅ | | S3 presigned URL 발급 (3차 변경: Firebase ML 제거, `tutorial/21`) |
| OTA-002 (모델 활성화) | ❌ | | ✅ | | `X-Admin-API-Key`, 단일 활성 모델 트랜잭션 |
| RESULT-001 / RESULT-002 | ✅ | | | | `thumbnail_url`은 MVP 원본 URL과 동일 (Post-MVP CloudFront Resizing) |
| FEEDBACK-001 ~ FEEDBACK-003 | ✅ | | | | upsert (`결과_ID` UNIQUE) |
| SETTINGS-001a / 001b | ✅ (UI만) | ✅ (다국어 리소스) | | | 푸시 실제 발송 2주차 이후 |

> **MVP 1주차 구조 특이사항**: 단말기 자체 추론(TFLite) 미적용. Flutter 앱은 모든 사진을 INFER-002로 직접 전송. 양품/불량 모두 서버 분류 결과를 사용. 2주차에 `tflite_flutter` + NNAPI Delegate 통합 후 `is_pass + confidence ≥ 0.85` 양품 단말 종결 분기 도입.

---

## 5. 에러 코드 정의

| HTTP | 에러 코드 | 설명 |
|---|---|---|
| 400 | INVALID_PROCESS | 비활성 공정 선택 |
| 400 | MODEL_NOT_READY | 해당 공정 TFLite 모델 미준비 |
| 400 | SESSION_NOT_ACTIVE | 진행 중이 아닌 세션 조작 시도 |
| 400 | TANK_TYPE_NOT_FOUND | 존재하지 않는 탱크 유형 |
| 400 | TANK_TYPE_PROCESS_NOT_MAPPED | 탱크 유형에 매핑된 공정 없음 |
| 400 | INVALID_SUBSECTOR | `selected_subsector`가 `검사_구역.구역_코드[selected_sector]` 배열에 없음 |
| 400 | INCOMPLETE_RESULTS_EXIST | 세션 내 미완료 건 존재 (세션 종료 불가) |
| 400 | BATCH_SIZE_LIMIT_EXCEEDED | INFER-005 배치 크기 50건 초과 |
| 400 | METADATA_IMAGE_COUNT_MISMATCH | INFER-005 images[]와 metadata 배열 길이 불일치 |
| 401 | AUTH_FAILED | 인증 실패 (ID 또는 비밀번호 오류) |
| 401 | TOKEN_EXPIRED | 액세스 토큰 만료 |
| 401 | ADMIN_AUTH_FAILED | 관리자 API 시스템 인증 실패 |
| 403 | INACTIVE_ACCOUNT | 비활성 계정 로그인 시도 |
| 404 | NOT_FOUND | 리소스 없음 |
| 409 | DAILY_SESSION_EXISTS | 당일 진행중 세션 존재 (1일 1세션 규칙) |
| 500 | INFERENCE_ERROR | 서버 추론 실패 |
| 500 | MANUAL_LOOKUP_ERROR | 매뉴얼 직접 조회 실패 (DB 오류 등) |
| 503 | GPU_BUSY | GPU 큐 초과 |
