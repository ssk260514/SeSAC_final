# 화면 1: 로그인 화면

> ← [MAIN.md](../MAIN.md) | Feature: `lib/features/auth/`

## 1. 개요
- **목적**: 검사원 본인 인증 후 앱 진입
- **Feature 모듈**: `auth`

---

## 2. Presentation Layer

### 2.1 UI 구성
| 영역 | 요소 | 타입 | 설명 |
|---|---|---|---|
| 상단 | 앱 아이콘 | Container + Icon | factory 아이콘 (primary-container 배경) |
| 상단 | 앱 타이틀 | Text (h1) | "Industrial Smart Inspection" |
| 상단 | 부제 | Text (body) | "LNG 시설 안전 점검 시스템" |
| 중앙 | 검사원 ID 입력 | TextField | `검사원.검사원_ID` — 인증 식별자 |
| 중앙 | 성함 입력 | TextField | 검사원 이름 |
| 중앙 | 비밀번호 입력 | TextField (obscure) | `검사원.비밀번호_해시`와 bcrypt 비교 |
| 하단 | 로그인 버튼 | ElevatedButton (full-width) | 인증 요청 |
| 하단 | 저작권 텍스트 | Text (body, muted) | "© 2026 LNG Safety Solutions Corp." |

### 2.2 Widget 트리 (개요)
> TODO: 페이지별 설계 보강 단계에서 작성 (Screen / Form / 입력 필드 위젯 분해)

### 2.3 State & Provider

#### 원본 상태 관리 명세 (Migration 자료)
- JWT 액세스 토큰 → `flutter_secure_storage` 저장
- 리프레시 토큰 → `flutter_secure_storage` 저장
- 검사원 정보 (검사원 ID, 이름, 부서) → 앱 전역 상태 (Riverpod)
- 부서는 로그인 화면에서 입력하지 않고, 인증 성공 후 DB에서 READ하여 자동 저장

#### 클린 아키텍처 구조화
> TODO: `AuthState`, `AuthNotifier`, `authNotifierProvider` 정의 작성

### 2.4 UI 이벤트 → Notifier 메서드 매핑
> TODO

---

## 3. Domain Layer

### 3.1 Entity
> TODO: `Inspector` (검사원_ID, 이름, 부서, 활성_여부, 마지막_로그인_일시)

### 3.2 UseCase
> TODO: `LoginUseCase`, `LogoutUseCase`, `RefreshTokenUseCase`

### 3.3 Repository (Interface)
> TODO: `AuthRepository`

---

## 4. Data Layer

### 4.1 ERD 매핑
| 작업 | 테이블 | 컬럼 | 설명 |
|---|---|---|---|
| READ | 검사원 | 검사원_ID, 비밀번호_해시 | bcrypt 비교 인증 |
| READ | 검사원 | 이름, 활성_여부 | 입력값 검증 + 활성 계정 확인 |
| READ | 검사원 | 부서 | 로그인 성공 후 DB에서 자동 로드 → Riverpod 저장 |
| UPDATE | 검사원 | 마지막_로그인_일시 | 로그인 성공 시 갱신 |

### 4.2 DTO / Model
> TODO

### 4.3 DataSource
- **Remote**: `AuthRemoteDataSource` → API 참조: [API_SPEC.md](../../../데이터/API_SPEC.md) (AUTH-001 로그인, AUTH-002 로그아웃, AUTH-003 토큰 갱신)
- **Local**: `AuthLocalDataSource` → `flutter_secure_storage` (`jwt_access`, `jwt_refresh` 키)

### 4.4 Repository 구현
> TODO: `AuthRepositoryImpl`

---

## 5. 전이 조건 (Navigation)
| 이벤트 | 다음 화면 | 조건 |
|---|---|---|
| 로그인 성공 | 화면 2 (탱크 유형 및 위치 선택) | 활성_여부 == true |
| 로그인 실패 | 화면 1 (유지) | 에러 메시지 표시 |
| 비활성 계정 | 화면 1 (유지) | "관리자에게 문의" 메시지 |

---

## 6. 빈 상태 / 워크플로우 / 처리 흐름
해당 없음.

---

## 7. 디자인 참조
관련 토큰·컴포넌트: [디자인_시스템_명세서.md](../../디자인_시스템_명세서.md)
