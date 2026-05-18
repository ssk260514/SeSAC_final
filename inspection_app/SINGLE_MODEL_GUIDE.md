# 단일 통합 모델 기준 — inspection_app 구현 가이드

> **배경**: 6공정별 6개 모델 → **단일 통합 모델 1개(30클래스)** 전환. 현재 `lib/` 는 `core/`(network·router·storage·theme·error)·placeholder screen 7개·로컬 `core/` 인프라만 존재합니다. Clean Architecture·TFLite 서비스·DTO·Riverpod notifier는 **전부 미구현**. 본 문서는 향후 06~14번 튜토리얼을 따라 구현할 때 단일 모델 정합을 보장하는 가이드입니다.
>
> **확정 사항**: 모델 파일 `assets/models/best_model_v5_datamatch_full.tflite` (30클래스), 양품 판별 `defectType.contains('양품')`, 신뢰도 임계값 전역 0.85, `currentProcessIdProvider`는 위치/RAG 메타용(모델 선택 무관).
>
> **참조**: `명세서/계획 변경 내용.md` §7, `frontend/design/PAGE/{02,05,06}_*/COMPONENT.md`, `tutorial/{09,11,13,14}`.

---

## 1. 구현 전 — 현 코드 변경 0

- `lib/core/network/dio_client.dart`, `core/router/*`, `core/theme/*`, `core/storage/*`, `core/error/*`, `lib/features/*/presentation/screens/*_screen.dart` (7개 placeholder) — 6모델 가정 코드 0건. **변경 필요 없음**
- `pubspec.yaml`·`android/`·`assets/fonts` — 변경 없음 (`assets/models/` 경로 불변)

## 2. 향후 구현 가이드 (06~14 튜토리얼 따라 작성 시)

### 2-1. `lib/features/capture/data/local/tflite_inference_service.dart`
```dart
class TfliteInferenceService {
  Interpreter? _interpreter;

  /// 단일 통합 모델 30클래스 (DB `모델_레지스트리.클래스_라벨` 및 학습팀 metadata.json과 일치 필수)
  static const List<String> _unifiedLabels = [
    // 표면처리 (0~12)
    '균열-도장', '균열-보온재', '도장흐름-도장', '도막떨어짐-도장', '도막분리-도장',
    '스크래치-모재', '스크래치-도장', '스크래치-보온재', '보온재손상-보온재', '탱크클리닝불량-모재',
    '표면양품-모재', '표면양품-도장', '표면양품-보온재',
    // 용접 (13~15)
    '용접불량-조인트', '용접블로우홀-조인트', '용접양품-조인트',
    // 절단 (16~19)
    '절단불량-모재', '절단불량-보온재', '절단양품-모재', '절단양품-보온재',
    // 케이블 (20~25)
    '케이블설치불량-케이블그랜드', '케이블손상-케이블', '바인딩불량-케이블타이',
    '케이블설치양품-케이블그랜드', '케이블양품-케이블', '바인딩양품-케이블타이',
    // 파이프 (26~27)
    '볼트체결불량-파이프', '볼트체결양품-파이프',
    // 폼스프레이 (28~29)
    '폼스프레이불량-우레탄폼', '폼스프레이양품-우레탄폼',
  ];

  Future<void> init() async {
    _interpreter ??= await Interpreter.fromAsset(
      'assets/models/best_model_v5_datamatch_full.tflite',
    );
  }

  // ...
}
```

### 2-2. 양품/불량 판별 (모든 feature 공통)
```dart
bool get isPass => defectType.contains('양품');  // 통합 30클래스 공통 — 공정 무관
// isDefect 가 필요하면: !defectType.contains('양품')
```

### 2-3. 신뢰도 임계값 (전역 상수)
```dart
// lib/core/constants.dart 또는 features/capture/domain/constants.dart
const double kPassThreshold = 0.85;       // 단말 양품 자동 종결 컷오프
const double kServerRecheckThreshold = 0.70;
```
`공정.신뢰도_임계값` DB 조회 코드 작성 금지. 전역 상수를 사용.

### 2-4. `lib/features/result_review/` (화면 6)
- 결함 유형 드롭다운 데이터 소스: **30클래스 통합** (PROC-001 의 `defect_types`를 그대로 사용 또는 `모델_레지스트리.클래스_라벨` API 추가)
- 항목이 많으므로 공정별 그룹 헤더 + 검색 필드 UX 권장 (디자인 시스템 명세서 §6.3.3 참조)

### 2-5. `lib/features/capture/presentation/providers/`
```dart
final currentProcessIdProvider = StateProvider<int>((ref) => 1);
// process_id는 위치 기록·RAG 매뉴얼 범위 한정용 메타. 모델 선택과 무관.
```

### 2-6. `lib/features/tank_location/` (화면 2)
- TFLite 모델 로드는 단일 모델 1회만 (최초 진입 시 백그라운드 init)
- 공정별 "모델 미준비" 경고 분기 작성 금지 — 단일 모델은 항상 준비됨

### 2-7. `assets/models/` 디렉터리
- 현재 `.gitkeep` 만 존재
- 학습팀이 `best_model_v5_datamatch_full.tflite` 산출물 도착 시 이 디렉터리에 배치
- `pubspec.yaml` 의 `flutter.assets`에 `assets/models/` 등록은 03번 튜토리얼에서 이미 처리됨

---

## 3. 학습팀 답 도착 시 재정합 대상

§8 미해결 항목 답 도착 시 다음을 갱신:
- `tflite_inference_service.dart` 의 `_unifiedLabels` 순서·내용
- `assets/models/best_model_v5_datamatch_full.tflite` 실제 가중치 파일
- 클래스 ID 0~29 매핑이 학습팀 출력 인덱스와 일치하는지 검증

---

## 4. 참조

- 영향 분석서: [명세서/계획 변경 내용.md](../명세서/계획%20변경%20내용.md) §7 · §9
- TFLite 서비스 구현 예시: [tutorial/13_2주차_TFLite_단말_추론.md](../tutorial/13_2주차_TFLite_단말_추론.md)
- 카메라/촬영 통합: [tutorial/09_화면5_카메라_촬영.md](../tutorial/09_화면5_카메라_촬영.md)
- 결과 처리 드롭다운: [tutorial/11_화면6_결과처리.md](../tutorial/11_화면6_결과처리.md)
- 백엔드 RAG/분류기: [tutorial/14_2주차_백엔드_RAG_정밀분석.md](../tutorial/14_2주차_백엔드_RAG_정밀분석.md)
- 백엔드 가이드: [backend/app/SINGLE_MODEL_GUIDE.md](../backend/app/SINGLE_MODEL_GUIDE.md)
