# 디자인 폴더 작업 가이드 (CLAUDE.md)

이 폴더에서 작업할 때 Claude 가 따라야 할 규칙입니다.

---

## 1. 폴더 구조 및 역할

```
frontend/
├── 바이블/                       # 제품·기능·아키텍처 (상위 설계)
│   ├── 제품_정의서.md
│   ├── 기능_명세서.md
│   └── 아키텍처_명세서.md
├── 데이터/                       # API 계약
│   └── API_SPEC.md
└── 디자인/                       # ◀ 이 폴더
    ├── 디자인_시스템_명세서.md   # 토큰·컴포넌트의 최종 기준 (수치·HEX·폰트)
    ├── CLAUDE.md                  # 본 가이드
    └── PAGE/
        ├── MAIN.md                # 화면 흐름·공통 요소 인덱스
        └── NN_<이름>/COMPONENT.md # 페이지별 상세 명세 (×7)
```

---

## 2. 클린 아키텍처 원칙

Flutter 앱은 **Clean Architecture (3-layer, feature-first)** 로 구현합니다.

### 2.1 Feature 단위
각 화면(=`COMPONENT.md`) = 1개의 feature 모듈.

```
lib/features/<feature>/
├── presentation/   # Widget, Riverpod Notifier, State 객체, Route
├── domain/         # Entity, UseCase, Repository (abstract)
└── data/           # DTO, DataSource(Remote/Local), Repository 구현
```

공통은 `lib/core/`(network/storage/theme/error), `lib/shared/`(공용 위젯·모델) 에 둠.

### 2.2 화면 → Feature 이름 매핑
| 화면 | Feature 이름 |
|---|---|
| 화면 1: 로그인 | `auth` |
| 화면 2: 탱크 유형/위치 선택 | `tank_location` |
| 화면 3: 대시보드 | `dashboard` |
| 화면 4: 검사 이력 + 정밀 분석 모달 | `inspection_history` |
| 화면 5: 카메라 | `capture` |
| 화면 6: 결과 처리 | `result_review` |
| 화면 7: 설정 | `settings` |

### 2.3 의존성 방향 (필수)
```
presentation → domain ← data
```
- `domain` 은 외부 의존성 없음 (순수 Dart, Flutter import 금지)
- `presentation` / `data` 모두 `domain` 의 추상화(Repository, UseCase)에 의존
- DI: **Riverpod Provider** 로 Repository 구현체를 추상 타입에 바인딩
- 데이터 흐름: Widget → Notifier → UseCase → Repository(추상) → RepositoryImpl → DataSource

### 2.4 State 관리
- **Riverpod** (`flutter_riverpod`) + `StateNotifier`
- 화면별 State 클래스는 immutable (e.g. `freezed`)
- 화면 간 공유 상태(`auth`, `tank_location`)는 글로벌 Provider, 단일 화면 상태는 화면별 Provider

---

## 3. 문서 작성 규칙

### 3.1 텍스트·라벨·문구
- **화면명세서 (각 `COMPONENT.md`) 가 텍스트의 최종 기준**입니다. 문구·라벨·뱃지 텍스트·토스트 메시지는 원문 그대로 사용 (요약·치환 금지)
- 한국어 + 영문 병기 (예: "정밀 분석 결과", "Top-3 Predictions") 도 원문 그대로

### 3.2 디자인 토큰·수치
- 컬러 HEX, 폰트 크기, 간격, 그림자 등 **수치는 `디자인_시스템_명세서.md` 가 최종 기준**입니다
- `code.html` 의 수치는 채택하지 않음 (참조용)
- `COMPONENT.md` 에서 토큰을 인용할 때는 토큰 ID (예: `primary-container`, `on-surface-variant`) 로 표기, 직접 HEX 사용 금지

### 3.3 페이지 추가/수정
- 새 화면 추가 시: `PAGE/NN_<이름>/COMPONENT.md` 생성 + `MAIN.md` 화면 목록 표에 행 추가 + 화면 흐름도 갱신
- 기존 화면 변경 시: 해당 `COMPONENT.md` 만 수정. `MAIN.md` 는 흐름·공통이 바뀔 때만 수정
- `COMPONENT.md` 템플릿 (§1~§7) 헤더 구조는 모든 페이지 동일하게 유지

### 3.4 클린 아키텍처 섹션 채우기
현재 `COMPONENT.md` 의 §2.2~§2.4, §3, §4.2~§4.4 는 `> TODO` 상태입니다. 페이지별 설계 보강 단계에서 다음을 채웁니다:
- §2.2 Widget 트리 (Screen / 주요 하위 위젯)
- §2.3 State & Provider (State 클래스, Notifier, Provider 이름)
- §2.4 UI 이벤트 → Notifier 메서드 매핑 (표)
- §3 Domain Layer (Entity, UseCase, Repository Interface)
- §4.2 DTO/Model, §4.3 DataSource 추가 상세, §4.4 Repository 구현

---

## 4. 참조 경로 가이드 (상대경로)

작업 중 다른 명세서를 인용할 때:

| from | to | 상대경로 |
|---|---|---|
| `디자인/PAGE/NN_xxx/COMPONENT.md` | `디자인_시스템_명세서.md` | `../../디자인_시스템_명세서.md` |
| `디자인/PAGE/NN_xxx/COMPONENT.md` | `데이터/API_SPEC.md` | `../../../데이터/API_SPEC.md` |
| `디자인/PAGE/NN_xxx/COMPONENT.md` | `바이블/기능_명세서.md` | `../../../바이블/기능_명세서.md` |
| `디자인/PAGE/NN_xxx/COMPONENT.md` | `PAGE/MAIN.md` | `../MAIN.md` |
| `디자인/디자인_시스템_명세서.md` | `바이블/기능_명세서.md` | `../바이블/기능_명세서.md` |
| `디자인/디자인_시스템_명세서.md` | `PAGE/MAIN.md` | `PAGE/MAIN.md` |

---

## 5. 작업 시 체크리스트

`COMPONENT.md` 수정 후:
- [ ] `MAIN.md` 의 화면 목록·흐름도가 변경 사항을 반영하는가?
- [ ] 새로 추가한 텍스트·라벨이 한국어 원문 형식을 유지하는가?
- [ ] 새로 추가한 색상·간격이 디자인 토큰 ID 로 인용되었는가?
- [ ] §3·§4 의 Entity/UseCase/Repository 이름이 §2.3 의 Provider 이름과 정합하는가?
- [ ] API 호출은 `API_SPEC.md` 의 ID (AUTH-001, SESS-001, INFER-001 등) 로 명시되었는가?
