# 화면 2: 탱크 유형 및 위치 선택 화면

> ← [MAIN.md](../MAIN.md) | Feature: `lib/features/tank_location/`

## 1. 개요
- **목적**: 탱크 유형(B/C) 선택 → 구역 + 세부 위치 선택 → 탱크 유형-공정 자동 매핑 → 대시보드 진입
- **Feature 모듈**: `tank_location`

---

## 2. Presentation Layer

### 2.1 UI 구성

#### 1단계: 탱크 유형 선택
| 영역 | 요소 | 타입 | 설명 |
|---|---|---|---|
| 상단 | AppBar | AppBar | "탱크 유형 선택" + 뒤로가기 (→ 로그인) |
| 본문 | 탱크 B 카드 | GestureDetector + Card | 아이콘(propane_tank) + "탱크 B (Type B)" + chevron |
| 본문 | 탱크 C 카드 | GestureDetector + Card | 아이콘(propane_tank) + "탱크 C (Type C)" + chevron |

#### 2단계: 위치 선택
| 영역 | 요소 | 타입 | 설명 |
|---|---|---|---|
| 상단 | AppBar | AppBar | "위치 선택" + 뒤로가기 (→ 1단계) |
| 본문 | 구역 드롭다운 | DropdownButton | 선택한 탱크 유형에 매핑된 구역(Sector) 목록 |
| 본문 | 세부 위치 드롭다운 | DropdownButton | 선택한 구역 하위의 세부 위치 목록 |
| 하단 | "확인" 버튼 | ElevatedButton (full-width) | 구역 + 세부 위치 선택 완료 → 대시보드 진입 |

### 2.2 Widget 트리 (개요)
> TODO

### 2.3 State & Provider

#### 원본 상태 관리 명세 (Migration 자료)
- 선택값 (`tank_type`, `selected_sector`, `selected_subsector`) → 앱 전역 상태 (Riverpod) + `flutter_secure_storage` 영속화 (검사원 정보와 동일 패턴)
- 다음 앱 시작 시 자동 복원 — 검사원이 동일 탱크 반복 검사 시 화면 2 재진입 불필요. SESS-001 요청의 3개 필드는 항상 Riverpod 상태에서 가져옴
- 위치 변경 의도 시: 화면 3 AppBar의 "위치 변경" 아이콘으로 화면 2 재진입 → 새 선택 후 "확인" 클릭 시 Riverpod 상태 갱신 + `flutter_secure_storage` 갱신 → 화면 3 복귀
- 진행중 세션이 있는 동안 선택값 변경은 권장되지 않음 (변경해도 진행중 세션의 `검사_세션.선택_구역`/`선택_세부위치`는 불변. 새 선택값은 다음 세션부터 적용)

#### 탱크 유형-공정 자동 매핑 로직
- 1단계: 탱크 유형 카드 클릭 시 `tank_type`을 서버에 전송
- 서버가 해당 탱크 유형에 매핑된 구역 + 세부 위치 목록과 `공정_ID`를 반환
- 2단계: 구역 + 세부 위치 선택 완료 시 앱은 단일 통합 모델(`best_model_v5_datamatch_full.tflite`)을 백그라운드에서 로드 준비 (공정 무관, 최초 1회)
- 검사원이 직접 공정을 선택할 필요 없음

#### 클린 아키텍처 구조화
> TODO: `TankLocationState`, `TankLocationNotifier`, `tankLocationNotifierProvider` 정의 작성

### 2.4 UI 이벤트 → Notifier 메서드 매핑
> TODO

---

## 3. Domain Layer

### 3.1 Entity
> TODO: `InspectionSector` (탱크_타입, 구역_코드 JSONB, 공정_ID), `Process` (공정_ID, 공정_이름, 활성_여부 — 신뢰도_임계값은 전역 상수로 분리), `ModelRegistry` (모델_유형, 파일_경로, 활성_여부 — 공정_ID 제거, 단일 모델)

### 3.2 UseCase
> TODO: `FetchSectorsByTankTypeUseCase`, `SaveTankLocationUseCase`, `PrepareModelUseCase`

### 3.3 Repository (Interface)
> TODO: `TankLocationRepository`, `ModelRegistryRepository`

---

## 4. Data Layer

### 4.1 ERD 매핑
| 작업 | 테이블 | 컬럼 | 설명 |
|---|---|---|---|
| READ | 검사_구역 | 탱크_타입 | 1단계: B/C 목록 (PK, 2행) |
| READ | 검사_구역 | 구역_코드 (nested JSONB) | 2단계 드롭다운 — 1단계: JSONB의 key 목록(구역명), 2단계: 선택된 key의 value 배열(세부 위치 목록) |
| READ | 검사_구역 | 공정_ID (FK) | 탱크 유형→공정 자동 매핑 |
| READ | 공정 | 공정_이름, 활성_여부 | 매핑된 공정 활성 확인 |
| READ | 모델_레지스트리 | 모델_유형, 파일_경로, 활성_여부 | 단일 TFLite 모델 로드 (공정_ID 조건 없음) |

### 4.2 DTO / Model
> TODO

### 4.3 DataSource
- **Remote**: `TankLocationRemoteDataSource` → API 참조: [API_SPEC.md](../../../데이터/API_SPEC.md)
- **Local**: `TankLocationLocalDataSource` → `flutter_secure_storage` (`tank_type`, `selected_sector`, `selected_subsector`)
- **Local**: TFLite 모델 파일 캐시 (S3 presigned URL OTA — 3차 변경, `tutorial/21`)

### 4.4 Repository 구현
> TODO: `TankLocationRepositoryImpl`, `ModelRegistryRepositoryImpl`

---

## 5. 전이 조건 (Navigation)
| 이벤트 | 다음 화면 | 조건 |
|---|---|---|
| 탱크 유형 카드 클릭 | 화면 2 (2단계: 위치 선택) | 해당 탱크 유형에 매핑된 위치 존재 |
| 위치 선택 "확인" 클릭 (최초 진입) | 화면 3 (대시보드) | 로그인 직후 최초 진입 — Riverpod 상태 INSERT + 영속화 |
| 위치 선택 "확인" 클릭 (재진입) | 화면 3 (대시보드) | 화면 3 "위치 변경" 아이콘으로 재진입한 경우 — Riverpod 상태 UPDATE + 영속화 |
| 뒤로가기 (2단계) | 화면 2 (1단계) | - |
| 뒤로가기 (1단계, 최초 진입) | 화면 1 (로그인) | 로그인 직후 최초 진입 케이스 |
| 뒤로가기 (1단계, 재진입) | 화면 3 (대시보드) | 메인 앱에서 "위치 변경"으로 재진입한 경우 — Riverpod 상태 변경 없이 화면 3 복귀 |

---

## 6. 빈 상태 / 워크플로우 / 처리 흐름
해당 없음.

---

## 7. 디자인 참조
관련 토큰·컴포넌트: [디자인_시스템_명세서.md](../../디자인_시스템_명세서.md)
