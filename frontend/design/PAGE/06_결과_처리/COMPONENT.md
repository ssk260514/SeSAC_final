# 화면 6: 결과 처리

> ← [MAIN.md](../MAIN.md) | Feature: `lib/features/result_review/`

## 1. 개요
- **목적**: AI 분석 결과와 조치 가이드를 검토. 필요 시 수정 후 저장. 검사 이력의 "검사 완료" 항목에서 재진입하여 언제든 수정 가능.
- **Feature 모듈**: `result_review`

### 진입 경로 (3가지)
```
1. 검사 이력 [탭2] → "검사 미완료" 불량 카드 → 정밀 분석 모달 → "결과 처리" 버튼 → 결과 처리 (최초 저장)
2. 검사 이력 [탭2] → "검사 완료" 카드 클릭 → 결과 처리 (저장된 결과 열람/수정)
3. Bottom Nav [탭3] → 결과 처리 직접 접근
```

---

## 2. Presentation Layer

### 2.1 UI 구성
| 영역 | 요소 | 타입 | 설명 |
|---|---|---|---|
| 상단 | AppBar | AppBar | 뒤로가기 + "결과 처리" + 상태 뱃지 ("확정 저장됨" 표시) |
| 본문 상단 | 검사 요약 카드 | Card (Row) | 썸네일(20×20) + "AI 판정: [결함유형]" + "신뢰도: [%]" |
| 본문 | 결함 유형 판정 | Card | 라벨 "결함 유형 판정 (Defect Type)" + DropdownButton |
| 본문 | 심각도 판정 | Card 내 | 라벨 "심각도 판정 (Severity Level)" + DropdownButton (경미/보통/심각) |
| 본문 | 조치 가이드 카드 | Card (primary tint) | smart_toy 아이콘 + "매뉴얼 기반 조치 가이드" + 조치 요약 (읽기 전용) |
| 본문 | 조치 내용 수정 | TextField (multiline) | 라벨 "조치 내용 수정" + 초기값 = 조치_상세. 편집모드에서만 수정 가능 |
| 본문 | 의견/메모 | TextField (multiline) | 라벨 "의견/메모" + 자유 형식 입력. 편집모드에서만 수정 가능 |
| 하단 플로팅 | "수정" 버튼 | OutlinedButton (flex-1) | 편집모드 활성화 |
| 하단 플로팅 | "저장" 버튼 | ElevatedButton (flex-1, primary) | 변경 내용 확정 저장 |
| 하단 | Bottom Navigation Bar | BottomNav | 4탭 (결과 처리 활성) |

### 2.2 Widget 트리 (개요)
> TODO: `ResultReviewScreen` / `DefectTypeDropdown` / `SeverityDropdown` / `ActionGuideCard` / `ActionEditField` / `FeedbackField` 분해

### 2.3 State & Provider
> TODO: `ResultReviewState` (편집모드 플래그, 결함_유형, 심각도, 조치_내용, 의견 등), `ResultReviewNotifier`

### 2.4 UI 이벤트 → Notifier 메서드 매핑
> TODO

---

## 3. Domain Layer

### 3.1 Entity
> TODO: `InspectionFeedback` (결과_ID, 검사원_ID, 세션_ID, 검사원_수정_여부, 수정된_결함_유형, 심각도, 의견, 최종_조치_내용, 수정_일시)

### 3.2 UseCase
> TODO: `LoadResultUseCase`, `SaveFeedbackUseCase` (INSERT/UPDATE 자동 판별), `EnableEditModeUseCase`

### 3.3 Repository (Interface)
> TODO: `FeedbackRepository`, `ModelRegistryRepository` (단일 모델의 `클래스_라벨` 30개 조회 — 드롭다운 데이터 소스)

---

## 4. Data Layer

### 4.1 ERD 매핑
| 작업 | 테이블 | 컬럼 | 설명 |
|---|---|---|---|
| READ | 검사_결과 | 품질_여부, 결함_유형, 신뢰도_점수, 상위_예측 | 검사 요약 카드 (AI 판정 결함 유형 + 신뢰도 표시) |
| READ | 모델_레지스트리 | 클래스_라벨 (30개 JSONB) | 결함 유형 드롭다운 선택지 — 통합 30클래스 (공정별 그룹 헤더·검색 UX 권장) |
| READ | 조치_권고 | 조치_요약, 조치_상세 | 매뉴얼 기반 조치 가이드 표시 + 조치 내용 초기값 |
| INSERT | 검사_피드백 | 결과_ID, 검사원_ID, 세션_ID, 검사원_수정_여부, 수정된_결함_유형, 심각도, 의견, 최종_조치_내용 | 최초 저장 (행 존재 = 확정 — N-13 보정으로 저장_상태 컬럼 제거됨) |
| UPDATE | 검사_피드백 | 수정된_결함_유형, 심각도, 최종_조치_내용, 검사원_수정_여부, 수정_일시 | 기존 결과 수정 |
| UPDATE | 검사_결과 | 결과_처리_상태='완료' | 저장 시 완료 처리 |

### 4.2 DTO / Model
> TODO

### 4.3 DataSource
- **Remote**: `FeedbackRemoteDataSource` → API 참조: [API_SPEC.md](../../../데이터/API_SPEC.md)
- **Local**: 없음

### 4.4 Repository 구현
> TODO: `FeedbackRepositoryImpl`

---

## 5. 전이 조건 (Navigation)
| 이벤트 | 다음 화면 | 조건 |
|---|---|---|
| "저장" 클릭 | 화면 4 (검사 이력, 탭2) | 저장 완료 |
| 뒤로가기 | 이전 화면 | 미저장 변경 있으면 확인 다이얼로그 |

---

## 6. 빈 상태 / 워크플로우 / 처리 흐름

### 6.1 워크플로우 A: 최초 저장 (검사 이력 "검사 미완료" 불량 카드에서 진입)
```
검사 이력 [탭2] → "검사 미완료" 불량 카드 → 정밀 분석 모달
    │
    ▼
"결과 처리" 버튼 클릭 → 결과 처리 [탭3]
    │  (결함 유형은 AI 판정값으로 초기 설정, 심각도는 검사원 직접 선택 — 디폴트 미선택)
    │  (조치 내용은 매뉴얼 사전 작성 텍스트로 초기 설정)
    ▼
결함 유형/심각도/조치 내용 확인 → "저장" 클릭
    │
    ▼
최초 저장 완료 → 검사 이력 [탭2]으로 이동
    (해당 건은 "검사 완료" 상태로 변경, 검사 이력에 유지)
```

### 6.2 워크플로우 B: 기존 결과 수정 (검사 이력 "검사 완료" 카드에서 진입)
```
검사 이력 [탭2] → "검사 완료" 카드 클릭 → 결과 처리 [탭3] (읽기 전용)
    │
    ▼
"수정" 클릭 → 편집모드 활성화 (드롭다운/textarea 편집 가능)
    │
    ▼
내용 수정 → "저장" 클릭
    │
    ▼
수정 저장 완료 → 검사 이력 [탭2]으로 이동
```

### 6.3 편집모드 상태 전이
```
진입 시 (읽기 전용 — 저장된 결과 표시)
    │
    ├─ 기본 상태: 드롭다운 disabled, textarea readOnly
    │
    ├─ "수정" 버튼 클릭
    │     → 드롭다운 enabled, textarea editable
    │     → 결함 유형/심각도/조치 내용 변경 가능
    │
    └─ "저장" 버튼 클릭
          → 변경 내용 서버 저장 (확정)
          → 결함유형 변경 여부에 따라 검사원_수정_여부 자동 결정:
              수정됨 → 검사원_수정_여부 = true
              미수정 → 검사원_수정_여부 = false (DEFAULT)
              ※ 심각도는 항상 검사원 입력값이므로 비교 대상 아님
          → 검사 이력 탭으로 이동
```

### 6.4 입력 검증
| 필드 | 검증 규칙 |
|---|---|
| 결함 유형 | 필수 (통합 30클래스 중 선택 — 단일 모델, 공정 무관) |
| 심각도 | 필수 (경미/보통/심각) |
| 조치 내용 | 저장 시 비어있으면 안 됨 |
| 의견/메모 | 선택사항 |

### 6.5 빈 상태 (EmptyState)
Bottom Nav [탭3] 로 직접 진입 시 선택된 검사 결과가 없으면 다음 EmptyState 를 표시:

| 항목 | 값 |
|---|---|
| 아이콘 | `assignment` (48px, `on-surface-variant`) |
| 제목 | "선택된 검사 결과가 없습니다" |
| 보조 텍스트 | "검사 이력에서 항목을 선택해 결과를 처리하세요" |
| 보조 액션 (옵션) | Text Button "검사 이력 보기" → 화면 4 (탭2) |

---

## 7. 디자인 참조
관련 토큰·컴포넌트: [디자인_시스템_명세서.md](../../디자인_시스템_명세서.md)
