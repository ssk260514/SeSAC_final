# Post-MVP 백로그 (4주 종료 이후)

> **목적**: 4주 MVP 운영(파일럿 종료 시점) 이후 추가 도입을 검토할 항목을 **단일 문서**로 정리. `명세서/제품_정의서.md` §4-3 `[Post-MVP]` + 본 프로젝트 진행 중 발견된 후보(매뉴얼 갱신·Evidently 정식 도입·§8 재정합 등)를 통합.
>
> **사용 시점**: 4주차 회고(`docs/회고_템플릿.md`) 작성 시 다음 페이즈 우선순위 선정의 후보 풀로 사용.
>
> **참조**: `명세서/제품_정의서.md` §4-3 · `tutorial/20_4주차_모니터링과_파일럿.md` §6 · `명세서/계획 변경 내용.md` §8 · 본 plan file "추후 작업 (팀원과)"

---

## 1. 우선순위 매트릭스

| 카테고리 | 항목 수 | 시점 트리거 |
|---|---|---|
| 🅰️ 운영 안정성 | 3 | 파일럿 종료 직후 — 4주차 회고에서 도입 결정 |
| 🅱️ 사용성·확장 | 4 | 사내 정책·현장 요구 확인 후 |
| 🅲️ 코드 완성도 | 2 | 옵션 2·3 완료 후 (`backend` 라우터 + `inspection_app` 구현) |
| 🅳️ 학습·모델 | 3 | 학습팀 답 도착 또는 데이터 누적 후 |

---

## 2. 🅰️ 운영 안정성

### 2-1. 단일 모델 재학습 자동화 파이프라인
- **출처**: `tutorial/17_3주차_양품샘플링과_오프라인배치.md` §1-1 (양품 누적 → 재학습) + `tutorial/20` §1-1
- **도입 조건**: 양품 샘플 + 검사원 수정 데이터 누적 ≥ 10,000장 (4주 파일럿 기준)
- **작업 내용**: S3 `samples/` + DB `검사_피드백` → 학습 데이터셋 자동 생성 → MobileNetV3 재학습 → ONNX/TFLite 변환 → 16번 OTA-002로 자동 게시
- **재정합 대상**: 학습팀 답 도착 시 `docs/학습팀_답_재정합_절차.md` 실행
- **예상 규모**: 8~12시간 (ML 엔지니어 1명)

### 2-2. Evidently AI 정식 도입
- **출처**: `tutorial/20_4주차_모니터링과_파일럿.md` §4 (Stage 2)
- **도입 조건**: §3 단순 대시보드(SQL 뷰)가 안정 동작 + 30클래스 중 drift 의심 클래스 식별
- **작업 내용**: `backend/ml/monitoring/evidently_report.py` 신규 + Data Drift·Class Imbalance·Confidence Drift 리포트 자동 생성
- **예상 규모**: 4~6시간

### 2-3. GPU 메모리 자동 알람
- **출처**: `tutorial/20_4주차_모니터링과_파일럿.md` §3-3 (NVIDIA-smi cron) + `아키텍처_명세서.md` Part 7 위험 대응
- **도입 조건**: 4주 파일럿 중 GPU 메모리 14GB 초과 사례 1건 이상 발생
- **작업 내용**: CloudWatch Logs 또는 Prometheus + Alertmanager 로 12GB 임계값 알람
- **예상 규모**: 2~3시간

---

## 3. 🅱️ 사용성·확장 (제품_정의서 §4-3 기반)

### 3-1. iOS 빌드
- **출처**: `명세서/제품_정의서.md` §4-3
- **도입 조건**: 안드로이드 안정화 후 (P0/P1 버그 0건 4주 유지)
- **작업 내용**: Flutter iOS 빌드 환경 셋업·CocoaPods·서명 인증서·App Store Connect 등록. `flutterfire configure` 시 iOS 추가
- **예상 규모**: 16~24시간

### 3-2. 세션 중단(abort) 기능
- **출처**: `명세서/제품_정의서.md` §4-3 / `기능_명세서.md` SESS-003 (현재 '진행중'→'완료'만)
- **도입 조건**: 파일럿 중단 사례 발생 확인 후
- **작업 내용**: `검사_세션.세션_상태` enum 에 '중단' 추가 + `DELETE /api/sessions/{id}` 또는 `PATCH /api/sessions/{id}/abort` 신규
- **예상 규모**: 3~5시간

### 3-3. Redis 토큰 블랙리스트
- **출처**: `명세서/제품_정의서.md` §4-3 / `명세서/API_SPEC.md` AUTH-003 logout 안내
- **도입 조건**: 보안 정책 재검토 후 (현재는 MDM 원격 wipe 로 1차 방어)
- **작업 내용**: Redis 인스턴스 추가 + `AuthInterceptor` (`tutorial/19` §5) 의 로그아웃 시 access·refresh JWT JTI 를 블랙리스트 등록 + 검증 미들웨어 추가
- **예상 규모**: 5~7시간

### 3-4. CloudFront 썸네일 + 다국어 리소스 + 푸시 알림 서버
- **출처**: `명세서/제품_정의서.md` §4-3 (3건 묶음)
- **도입 조건**:
  - CloudFront: 카드 렌더링 성능 병목 확인 후 (현재 원본 S3 URL 사용)
  - 다국어: 현장 필요도 확인 후 (UI 드롭다운은 1주차에 추가됨, 리소스 미적용)
  - 푸시 알림: 현장 요청 확인 후 (UI 토글은 1주차에 추가됨, 서버 미구현)
- **예상 규모**: 항목당 4~8시간

---

## 4. 🅲️ 코드 완성도 (본 plan 추후 작업)

### 4-1. backend 라우터 6개 실제 구현
- **출처**: 본 plan file "추후 작업 (팀원과)" 옵션 2 · `backend/app/SINGLE_MODEL_GUIDE.md` §2
- **도입 조건**: 1주차 MVP 실제 운영 시작 전 필수
- **작업 내용**: tank·inspect·session·result·settings·ota 6 라우터 작성 + ORM models·schemas·services
- **예상 규모**: 16~24시간 (옵션 2 plan)

### 4-2. inspection_app Clean Architecture 구현
- **출처**: 본 plan file "추후 작업 (팀원과)" 옵션 3 · `inspection_app/SINGLE_MODEL_GUIDE.md` §2
- **도입 조건**: 옵션 4-1 (backend 라우터) 부분 완료 + 학습팀 모델 파일 도착
- **작업 내용**: 7 feature × 3-layer (presentation·domain·data) + TFLite 서비스 + Riverpod notifier + `assets/models/best_model_v5_datamatch_full.tflite` 배치
- **예상 규모**: 30~40시간 (옵션 3 plan)

---

## 5. 🅳️ 학습·모델

### 5-1. 학습팀 답 도착 후 5곳 + α 재정합
- **출처**: `명세서/계획 변경 내용.md` §8 #1·#2·#5·#6 + `docs/학습팀_답_재정합_절차.md`
- **도입 조건**: 학습팀이 클래스 ID 0~29 실제 출력 순서·박리-도장 흡수 여부·30클래스 검증 결과·tflite 크기 실측치 전달
- **작업 내용**: `docs/학습팀_답_재정합_절차.md` Step 1~4 따라하기 → `scripts/check_single_model_integrity.ps1` 통과 확인
- **예상 규모**: 2~3시간

### 5-2. RAG 매뉴얼 콘텐츠 갱신 (박리-도장 폐기 반영)
- **출처**: `tutorial/14_2주차_백엔드_RAG_정밀분석.md` L293 `박리-도장 발견 시: ...` 매뉴얼 콘텐츠 — 30클래스 체계에서 박리-도장은 폐기 (사용자 §8 #1 결정)
- **도입 조건**: 학습팀 매뉴얼 자료 갱신 후
- **작업 내용**: `매뉴얼` 테이블의 `박리-도장` 관련 청크를 `도막떨어짐-도장`·`도막분리-도장` 매뉴얼로 교체. BGE-M3 임베딩 재생성 후 pgvector 적재
- **예상 규모**: 3~5시간 (매뉴얼 ETL 1회 재실행)

### 5-3. 클래스별 데이터 불균형 보정 — Focal Loss·클래스 가중치 튜닝
- **출처**: `명세서/아키텍처_명세서.md` 영역 A (Focal Loss·클래스 가중치) + `tutorial/20` §3-2 클래스별 수정률
- **도입 조건**: 파일럿 종료 후 클래스별 수정률 ≥ 30% 클래스 식별
- **작업 내용**: ML 팀이 클래스 가중치 재조정 → 단일 모델 재학습 → 16번 OTA로 게시
- **예상 규모**: ML 작업 8~16시간 + 배포 2시간

---

## 6. 도입 순서 권장

```
파일럿 종료 (4주차 끝)
    │
    ├─→ 5-1 학습팀 답 재정합 (즉시, 학습팀 답 도착 시)
    ├─→ 2-3 GPU 알람 (운영 안정성 즉시)
    ├─→ 4-1 backend 라우터 (1주차 MVP 실제 운영 전제)
    │      ↓
    └─→ 4-2 inspection_app Flutter 구현
           ↓
    ─→ 2-1 재학습 자동화 (데이터 누적 후)
    ─→ 2-2 Evidently 정식 도입
    ─→ 5-2 RAG 매뉴얼 갱신 (학습팀 매뉴얼 자료 후)
    ─→ 5-3 클래스 불균형 보정 (파일럿 데이터 분석 후)
    │
사용성 확장 (정책·현장 요구 확인 후)
    ─→ 3-2 세션 중단 / 3-3 Redis 블랙리스트 (보안·운영 요청 시)
    ─→ 3-1 iOS 빌드 (Android 안정화 후)
    ─→ 3-4 CloudFront / 다국어 / 푸시 알림 (각 트리거 조건 만족 시)
```

---

## 7. 참조

- 원본 Post-MVP: [명세서/제품_정의서.md](../명세서/제품_정의서.md) §4-3
- 학습팀 재정합: [docs/학습팀_답_재정합_절차.md](학습팀_답_재정합_절차.md)
- 회고 시 사용: [docs/회고_템플릿.md](회고_템플릿.md)
- 인수인계 시 사용: [docs/인수인계_템플릿.md](인수인계_템플릿.md)
- 정합 회귀 검증: [scripts/check_single_model_integrity.ps1](../scripts/check_single_model_integrity.ps1) / [.sh](../scripts/check_single_model_integrity.sh)
- 단일 모델 가이드: [backend/app/SINGLE_MODEL_GUIDE.md](../backend/app/SINGLE_MODEL_GUIDE.md) · [inspection_app/SINGLE_MODEL_GUIDE.md](../inspection_app/SINGLE_MODEL_GUIDE.md)
