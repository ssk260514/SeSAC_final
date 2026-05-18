# 화면 7: 설정

> ← [MAIN.md](../MAIN.md) | Feature: `lib/features/settings/`

## 1. 개요
- **목적**: 앱 설정 관리, 시스템 정보 확인, 로그아웃
- **Feature 모듈**: `settings`

---

## 2. Presentation Layer

### 2.1 UI 구성
| 영역 | 요소 | 타입 | 설명 |
|---|---|---|---|
| 상단 | AppBar | AppBar | 뒤로가기 + "설정" |
| 본문 | 앱 설정 카드 | Card | 섹션 제목: "앱 설정" |
| 앱 설정 | 푸시 알림 | Row | notifications 아이콘 + "푸시 알림" + Switch (토글) |
| 앱 설정 | 언어 설정 | Row | language 아이콘 + "언어 설정" + DropdownButton (한국어/English) |
| 본문 | 시스템 정보 카드 | Card | 섹션 제목: "시스템 정보" |
| 시스템 정보 | 앱 버전 | Row | "앱 버전" + "v1.4.2" (code-data 스타일) |
| 시스템 정보 | 이용약관 | Row + chevron | "이용약관 및 개인정보처리방침" → 외부 링크 |
| 본문 | 로그아웃 버튼 | OutlinedButton (full-width, error 색상) | logout 아이콘 + "로그아웃" |
| 하단 | Bottom Navigation Bar | BottomNav | 4탭 (설정 활성) |

### 2.2 Widget 트리 (개요)
> TODO

### 2.3 State & Provider
> TODO: `SettingsState` (푸시_알림, 언어), `SettingsNotifier`, `settingsNotifierProvider`

### 2.4 UI 이벤트 → Notifier 메서드 매핑
> TODO

---

## 3. Domain Layer

### 3.1 Entity
> TODO: `UserSettings` (검사원_ID, 푸시_알림, 언어, 수정_일시)

### 3.2 UseCase
> TODO: `FetchSettingsUseCase`, `UpdateSettingsUseCase` (UPSERT), `LogoutUseCase`

### 3.3 Repository (Interface)
> TODO: `SettingsRepository`

---

## 4. Data Layer

### 4.1 ERD 매핑
| 작업 | 테이블 | 컬럼 | 설명 |
|---|---|---|---|
| READ | 사용자_설정 | 푸시_알림, 언어 (WHERE 검사원_ID) | 화면 진입 시 `GET /api/settings`로 조회. 행이 없으면 DEFAULT(푸시_알림=true, 언어='ko') 사용 |
| WRITE | 사용자_설정 | INSERT or UPDATE (검사원_ID, 푸시_알림, 언어, 수정_일시) | 토글/드롭다운 변경 시 `PATCH /api/settings` 호출. UPSERT 동작 |

> `앱 버전`은 Flutter 앱의 빌드 정보(`PackageInfo`)에서 직접 조회. DB 미연동.

### 4.2 DTO / Model
> TODO

### 4.3 DataSource
- **Remote**: `SettingsRemoteDataSource` → API 참조: [API_SPEC.md](../../../데이터/API_SPEC.md) (`GET /api/settings`, `PATCH /api/settings`, `POST /api/auth/logout`)
- **Local**: `PackageInfo` (앱 버전 조회)

### 4.4 Repository 구현
> TODO: `SettingsRepositoryImpl`

---

## 5. 전이 조건 (Navigation)
| 이벤트 | 다음 화면 | 조건 |
|---|---|---|
| 로그아웃 | 화면 1 (로그인) | `POST /api/auth/logout` 비동기 호출 + `flutter_secure_storage` JWT 삭제 (응답 실패해도 로컬 삭제 진행 — best-effort) |
| 뒤로가기 | 화면 3 (대시보드) | - |

---

## 6. 빈 상태 / 워크플로우 / 처리 흐름
해당 없음.

---

## 7. 디자인 참조
관련 토큰·컴포넌트: [디자인_시스템_명세서.md](../../디자인_시스템_명세서.md)
