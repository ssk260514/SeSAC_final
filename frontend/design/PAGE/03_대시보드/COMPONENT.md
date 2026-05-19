# 화면 3: 대시보드

> ← [MAIN.md](../MAIN.md) | Feature: `lib/features/dashboard/`

## 1. 개요
- **목적**: 검사원 정보 확인, 검사 시작 (1일 1세션), 완료된 세션 결과 조회/수정
- **Feature 모듈**: `dashboard`

---

## 2. Presentation Layer

### 2.1 UI 구성
| 영역 | 요소 | 타입 | 설명 |
|---|---|---|---|
| 상단 | AppBar 좌측 | Row | 프로필 이미지(둥근) + "LNG Inspection" 타이틀 |
| 상단 | AppBar 우측 | Row | "위치 변경" 아이콘(edit_location_alt) + 알림 아이콘(notifications) + 로그아웃 아이콘(logout) |
| 본문 | 프로필 카드 | Card | 프로필 아이콘 + 이름("선임 검사원 김검사") + 부서("제4터미널 / 안전운영팀") |
| 본문 | 현재 검사 위치 표시 (옵션) | Chip 또는 Caption | "탱크 B · 외부 / 지지대" — Riverpod 상태에서 표시 |
| 본문 | 통계 카드 3개 | Row × Card | 세션 번호, 총 이미지(장), 양품률(%) |
| 본문 | "검사 시작" 버튼 | ElevatedButton (대형, full-width) | 카메라 아이콘 + "검사 시작" → `POST /api/sessions` 호출하여 새 세션 생성 → 카메라 화면. 1일 1세션 정책: 당일 진행중 세션이 이미 있으면 서버가 409 반환 → 클라이언트는 토스트 표시 + 검사 이력 탭으로 자동 이동. (사전 가드: `GET /api/dashboard/summary`의 `active_session_id`로 미리 감지 가능, 옵션) |
| 본문 | "최근 세션 이력" 헤더 | Row | 제목 |
| 본문 | 최근 세션 이력 리스트 | ListView (최근 3건) | 세션 제목 + 시간 정보. 최근 3건만 표시 |
| 하단 | Bottom Navigation Bar | BottomNav | 4탭 (대시보드 활성) |

### 2.2 Widget 트리 (개요)
> TODO

### 2.3 State & Provider
> TODO: `DashboardState`, `DashboardNotifier`, `dashboardNotifierProvider`

### 2.4 UI 이벤트 → Notifier 메서드 매핑
> TODO

---

## 3. Domain Layer

### 3.1 Entity
> TODO: `InspectionSession` (세션_ID, 검사원_ID, 공정_ID, 탱크_타입, 선택_구역, 선택_세부위치, 세션_상태, 시작_일시, 종료_일시, 총_이미지_수, 양품_수, 불량_수), `DashboardSummary` (active_session_id, 최근 세션 3건)

### 3.2 UseCase
> TODO: `FetchDashboardSummaryUseCase`, `StartSessionUseCase`, `FetchRecentSessionsUseCase`, `LogoutUseCase`

### 3.3 Repository (Interface)
> TODO: `SessionRepository`, `DashboardRepository`

---

## 4. Data Layer

### 4.1 ERD 매핑
| 작업 | 테이블 | 컬럼 | 설명 |
|---|---|---|---|
| READ | 검사원 | 이름, 부서 | 프로필 카드 |
| READ | 검사_세션 | 세션_ID, 총_이미지_수, 양품_수 | 통계 카드 (양품률 = 양품_수/총_이미지_수) |
| READ | 검사_세션 | 세션_ID (WHERE 검사원_ID AND 세션_상태='진행중' AND 시작_일시 >= 오늘) | `active_session_id` 사전 가드용 (대시보드 summary 응답에 포함) |
| INSERT | 검사_세션 | 검사원_ID, 공정_ID, 탱크_타입, 선택_구역, 선택_세부위치, 세션_상태='진행중', 시작_일시 | "검사 시작" → 새 세션 생성 (당일 진행중 세션이 없을 때만). 화면 2에서 선택한 구역 + 세부 위치 포함 |
| READ | 검사_세션 | 세션_상태='완료', 탱크_타입, 시작_일시, 종료_일시 | 최근 세션 이력 (최근 3건, ORDER BY 종료_일시 DESC NULLS LAST) |
| READ | 검사_피드백 | 수정_일시 | 최근 세션 이력: 최종 수정 시각 (MAX per 세션) |

### 4.2 DTO / Model
> TODO

### 4.3 DataSource
- **Remote**: `DashboardRemoteDataSource` → API 참조: [API_SPEC.md](../../../데이터/API_SPEC.md) (`GET /api/dashboard/summary`, `POST /api/sessions`, `POST /api/auth/logout`)
- **Local**: 없음 (대시보드는 실시간 서버 응답 기반)

### 4.4 Repository 구현
> TODO: `SessionRepositoryImpl`, `DashboardRepositoryImpl`

---

## 5. 전이 조건 (Navigation)
| 이벤트 | 다음 화면 | 조건 |
|---|---|---|
| "검사 시작" (당일 진행중 세션 없음) | 화면 5 (카메라) | `POST /api/sessions` 200 OK → 신규 세션 생성 후 카메라 진입. SESS-001 요청 `tank_type`/`selected_sector`/`selected_subsector`는 Riverpod 상태에서 가져옴 |
| "검사 시작" (당일 진행중 세션 있음) | 화면 4 (검사 이력) | `POST /api/sessions` 409 DAILY_SESSION_EXISTS → 토스트 "오늘 이미 진행 중인 세션이 있습니다. '이어서 검사'를 이용해주세요" 표시 후 자동 이동 |
| AppBar "위치 변경" 아이콘 클릭 | 화면 2 (1단계: 탱크 유형 선택) | 탱크/위치 변경 의도. 화면 2에서 새 선택 후 "확인" 클릭 시 Riverpod 상태 갱신 + 화면 3 복귀. 뒤로가기로 변경 없이 복귀 가능 |
| 로그아웃 | 화면 1 (로그인) | `POST /api/auth/logout` 비동기 호출 + `flutter_secure_storage` JWT 삭제 (응답 실패해도 로컬 삭제 진행 — best-effort) |

---

## 6. 빈 상태 / 워크플로우 / 처리 흐름

### 6.1 빈 상태 (EmptyState)
완료된 세션이 0건일 때 "최근 세션 이력" 리스트 자리에 다음 EmptyState 를 표시:

| 항목 | 값 |
|---|---|
| 아이콘 | `history` (48px, `on-surface-variant`) |
| 제목 | "완료된 세션이 아직 없습니다" |
| 보조 텍스트 | "'검사 시작'을 눌러 첫 검사를 시작하세요" |

### 6.2 최근 세션 이력 항목 구성
```
┌─────────────────────────────────────────┐
│ 탱크 B                                   │
│            검사 시작: 2024.05.21 14:20   │
│            검사 종료: 2024.05.21 14:30   │
│            최종 수정: 2024.05.21 14:35   │  ← MAX(검사_피드백.수정_일시)
└─────────────────────────────────────────┘
```
- 불량: warning 아이콘 (빨강 배경)
- 양품: check_circle 아이콘 (초록 배경)

---

## 7. 디자인 참조
관련 토큰·컴포넌트: [디자인_시스템_명세서.md](../../디자인_시스템_명세서.md)
