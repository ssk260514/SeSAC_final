# 화면 5: 카메라 촬영 화면

> ← [MAIN.md](../MAIN.md) | Feature: `lib/features/capture/`

## 1. 개요
- **목적**: 부품 이미지 촬영 → 카메라 유지 + 백그라운드 추론 → 연속 촬영 가능
- **Feature 모듈**: `capture`

---

## 2. Presentation Layer

### 2.1 UI 구성
| 영역 | 요소 | 타입 | 설명 |
|---|---|---|---|
| 전체 | 카메라 프리뷰 | CameraPreview | 전체 화면 카메라 (`camera` 패키지) |
| 전체 오버레이 | 비네팅 효과 | Container (gradient) | radial gradient 어두운 테두리 |
| 상단 오버레이 | 세션 정보 | Container (반투명 pill) | "탱크 B - 외부 / 지지대" 형식 (탱크_타입 + 선택_구역 + 선택_세부위치). schema 저장값을 그대로 표시하여 표기 일관성 유지 |
| 상단 오버레이 우측 | 플래시 제어 | IconButton | flash_auto 아이콘 (흰색, 반투명 원형 배경) |
| 중앙 오버레이 | 촬영 가이드 | Container (border) | 테두리 사각형 (primary-container/60, rounded-lg) |
| 하단 왼쪽 | 검사 이력 썸네일 | GestureDetector + Image | 최근 촬영 이미지 썸네일(12×12, rounded) + "검사 이력" 라벨 |
| 하단 중앙 | 셔터 버튼 | FloatingActionButton (대형) | 원형 셔터 버튼 (흰색 외곽 + primary-container 내부) |
| 하단 오른쪽 | 카메라 전환 | IconButton | flip_camera_ios 아이콘 (전면/후면 전환) |

### 2.2 Widget 트리 (개요)
> TODO: `CameraScreen` / `CameraPreviewWidget` / `ShutterButton` / `SessionInfoPill` / `HistoryThumbnail` 분해

### 2.3 State & Provider
> TODO: `CaptureState`, `CaptureNotifier`, 카메라 컨트롤러 Provider, 모델 로딩 Provider, 오프라인 큐 상태

### 2.4 UI 이벤트 → Notifier 메서드 매핑
> TODO

---

## 3. Domain Layer

### 3.1 Entity
> TODO: `CapturedImage`, `InferenceResult` (단말/서버) — `신뢰도_임계값`은 전역 상수 `kPassThreshold = 0.85`로 분리 (공정별 차등 없음, 단일 모델)

### 3.2 UseCase
> TODO: `CapturePhotoUseCase`, `RunOnDeviceInferenceUseCase`, `SubmitServerInferenceUseCase`, `EnqueueOfflineInferenceUseCase`, `UpdateSessionStatsUseCase`

### 3.3 Repository (Interface)
> TODO: `InferenceRepository`, `OfflineQueueRepository`, `ImageRepository`

---

## 4. Data Layer

### 4.1 ERD 매핑
| 작업 | 테이블 | 컬럼 | 설명 |
|---|---|---|---|
| INSERT | 검사_이미지 | 세션_ID, 이미지_경로, 촬영_일시 | 촬영 이미지 저장 (탱크 유형은 세션 JOIN으로 조회) |
| INSERT | 검사_결과 | 이미지_ID, 공정_ID, 모델_ID, 추론_위치=단말, 대표_여부=true, 품질_여부, 결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms, 결과_처리_상태 | 단말 추론 결과 (양품: 대표=true/완료, 불량: 대표=false/미완료). `결함_유형`은 단일 모델의 클래스 라벨(예: "표면양품-도장"), `품질_여부`는 클래스명에 `"양품"` 포함 여부로 파생 (통합 30클래스 공통) |
| INSERT | 검사_결과 | (불량+네트워크 시) 추론_위치=서버, 대표_여부=true, 동일 컬럼 | 서버 추론 결과 (대표=true, 단말 1행 + 서버 1행 = 2행) |
| INSERT | 검사_결과 | (오프라인 시) 추론_위치=단말, 대표_여부=true, 사람_재확인_필요=true, 결과_처리_상태=미완료 | 오프라인 단말 결과 (대표=true, 네트워크 복구 후 서버 행이 대표로 전환) |
| UPDATE | 검사_세션 | 총_이미지_수, 양품_수, 불량_수 | 세션 통계 갱신 |
| INSERT | 조치_권고 | 결과_ID, 조치_요약, 조치_상세 | 불량 시 서버가 매뉴얼 직접 조회 결과(`매뉴얼.조치_요약`/`조치_상세`)를 그대로 복사 → 권고_ID RETURNING |
| INSERT | 조치_권고_매뉴얼 | 권고_ID, 매뉴얼_ID, 순위, 유사도_점수=1.0 | 매칭 청크 각각 1행 (1~3행 INSERT) — 출처 추적성 보존 |
| READ | 공정 | 신뢰도_임계값 | **단말** 양품 자동 종결 기준 (이 값 이상 + 양품일 때만 단말에서 종료). 서버 측 사람 재확인 분기는 `서버_재확인_임계값`을 사용 (INFER-002 참조). ※ 전역 단일값 (공정별 차등 없음) |

### 4.2 DTO / Model
> TODO

### 4.3 DataSource
- **Remote**: `InferenceRemoteDataSource` → API 참조: [API_SPEC.md](../../../데이터/API_SPEC.md) (INFER-001 단건 추론, INFER-005 오프라인 배치 flush)
- **Local**: `ImageLocalDataSource` (단말 파일 시스템)
- **Local**: `OfflineQueueLocalDataSource` → sqflite (client_request_id UUID v4 멱등성 키)
- **Local**: TFLite 모델 (`tflite_flutter`)

### 4.4 Repository 구현
> TODO: `InferenceRepositoryImpl` (단말 추론 + 서버 분기 + 오프라인 큐 처리)

---

## 5. 전이 조건 (Navigation)
| 이벤트 | 다음 화면 | 조건 |
|---|---|---|
| "검사 이력" 썸네일 클릭 | 화면 4 (검사 이력, 탭2) | - |

---

## 6. 빈 상태 / 워크플로우 / 처리 흐름

### 6.1 촬영 후 처리 흐름
```
셔터 버튼 클릭
    │
    ▼
카메라 화면 유지 (연속 촬영 가능)
    │
    ▼
[백그라운드 처리 — Isolate/compute()]
    │
    ▼
이미지 전처리 (384×384, ImageNet 정규화)
    │
    ▼
온디바이스 추론 (tflite_flutter, 100~300ms)
    │
    ├─ 양품(클래스명에 "양품" 포함) AND 신뢰도 ≥ 신뢰도_임계값(전역 0.85)
    │     │
    │     ▼
    │   검사_이미지 INSERT (세션_ID, 이미지_경로, 촬영_일시)
    │   검사_결과 INSERT (추론_위치=단말, 대표_여부=true, 결함_유형, 품질_여부=true, 신뢰도_점수, 상위_예측, 결과_처리_상태=완료)
    │   검사_세션.총_이미지_수 += 1, 양품_수 += 1
    │   검사 이력에 '양품 (Pass)' 카드 추가 (결과 처리 불필요 → 자동 완료)
    │   10% 샘플링 체크 → 랜덤 업로드
    │
    ├─ 불량 OR 신뢰도 < 임계값 (네트워크 연결됨)
    │     │
    │     ▼
    │   서버 POST /api/inspect (이미지 + 단말 결과)
    │   검사_이미지 INSERT (세션_ID, 이미지_경로, 촬영_일시)
    │   검사_결과 INSERT × 2 (단말 1행: 대표_여부=false + 서버 1행: 대표_여부=true, 결과_처리_상태=미완료)
    │   검사_세션.총_이미지_수 += 1, 불량_수 += 1
    │   검사 이력에 '불량 (Fail)' 카드 추가
    │
    └─ 불량 OR 신뢰도 < 임계값 (네트워크 끊김)
          │
          ▼
        로컬 큐(sqflite) 저장 — client_request_id(UUID v4) 발급하여 항목별 멱등성 키로 보유
        검사_이미지 INSERT (세션_ID, 이미지_경로, 촬영_일시)
        검사_결과 INSERT (추론_위치=단말, 대표_여부=true, 사람_재확인_필요=true, 결과_처리_상태=미완료)
        검사_세션.총_이미지_수 += 1, 불량_수 += 1
        검사 이력에 '분석 대기' 카드 추가
        → 네트워크 복구 시 INFER-005 (POST /api/inspect/offline-batch) 자동 flush — 3주차 구현 (MVP 1주차에는 미구현, 큐 잔존)

* 검사원은 카메라에서 계속 촬영하면서, 이력 탭으로 전환하여 결과 확인 가능
* 카메라 나가기: 하단 "검사 이력" 썸네일 클릭 → 검사 이력 탭으로 이동
* 오프라인 큐 flush 트리거 (3주차): (a) 앱 시작 시, (b) 네트워크 ONLINE 전환 감지 시(`connectivity_plus`), (c) 화면 4 진입 시. 50건 초과 시 청크 분할 순차 호출
```

---

## 7. 디자인 참조
관련 토큰·컴포넌트: [디자인_시스템_명세서.md](../../디자인_시스템_명세서.md)
