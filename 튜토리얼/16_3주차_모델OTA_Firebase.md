# 16. 3주차 — 모델 OTA (Firebase ML로 모델만 무선 갱신)

> **이 단계가 끝나면**: 앱(APK)을 다시 설치하지 않고도 AI 모델 파일만 무선으로 갱신할 수 있습니다. 앱 시작 시 서버에 최신 모델 버전을 묻고, 새 버전이 있으면 Firebase ML에서 백그라운드 다운로드 → SHA-256 검증 → 다음 시작 시 적용됩니다.
>
> **예상 시간**: 5시간

> ⚠️ **단일 모델 전제**: 이 프로젝트는 6공정별 6개 모델이 아니라 **단일 통합 모델 1개**(`best_model_v5_datamatch_full`, 30클래스 = 불량 19 + 양품 11)를 사용합니다. 따라서 OTA도 "공정별 버전 관리"가 아니라 **모델 1개의 버전만** 관리합니다. `GET /api/model/version`에 `process_id` 파라미터가 **없습니다**.

> **참조 명세서**: [`아키텍처_명세서.md`](../명세서/아키텍처_명세서.md) Part 4 3주차 (L162~165)·영역 D, [`API_SPEC.md`](../명세서/API_SPEC.md) OTA-001 / OTA-002, [`기능_명세서.md`](../명세서/기능_명세서.md) §5-1·§5-2, [`계획 변경 내용.md`](../명세서/계획%20변경%20내용.md) §6-3

---

## 1. 왜 OTA인가 — 두 채널 분리 (앱 ↔ 모델)

AI 모델은 데이터가 쌓일수록 자주 재학습합니다(2~3주마다). 그런데 APK를 매번 다시 빌드·배포·설치하려면 사내 IT 팀·검사원 모두 번거롭습니다. **앱 코드(APK)는 사내 MDM, 모델 파일(.tflite)은 Firebase ML** 로 채널을 분리하면, 모델만 자주 갱신하고 앱은 드물게 갱신할 수 있습니다 (아키텍처_명세서 영역 D).

```
앱 시작
  → GET /api/model/version          (사내 FastAPI에 "최신 모델 버전?" 질의)
  → 응답: {version, firebase_model_name, file_hash(SHA-256), class_labels}
  → 로컬 캐시 버전과 비교 → 새 버전?
       YES → Firebase ML에서 백그라운드 다운로드 → SHA-256 검증
              → 일치: 다음 앱 시작 시 적용 (검사 중 교체 금지)
              → 불일치/실패: 기존 모델 유지
       NO  → 그대로 진행
```

> 💡 **왜 "다음 시작 시 적용"인가**: 검사 중에 모델을 바꾸면 같은 세션 안에서 분류 기준이 달라져 데이터가 일관되지 않습니다. 안전하게 앱 재기동 타이밍에 교체합니다.

---

## 2. 사전 준비

- 13번(단말 TFLite 추론)·14번(백엔드 RAG + 정밀 분석) 완료된 상태
- `best_model_v5_datamatch_full.tflite` (30클래스) 파일이 학습 팀에서 준비됨
- 별도 Google 계정 (회사 메인 계정과 분리 — 아키텍처_명세서 영역 D 보안 분리)
- `backend/app/core/config.py` 의 `ADMIN_API_KEY` 설정 완료 (`.env` 에 `ADMIN_API_KEY=...`)

---

## 3. Firebase 프로젝트 생성·연동

### 3-1. Firebase 프로젝트 만들기

1. https://console.firebase.google.com 접속 (분리된 Google 계정으로 로그인)
2. **프로젝트 추가** → 이름 `lng-inspection-ml` → 만들기
3. 좌측 메뉴 **Machine Learning** → **Custom** 탭 → **모델 추가**
4. 모델 이름: `best_model_v5_datamatch_full` → 같은 이름의 `.tflite` 파일 업로드

> ⚠️ **보안 분리 원칙** (아키텍처_명세서 영역 D): Firebase에는 **모델 가중치 파일만** 올립니다. 매뉴얼 텍스트·검사 결과·라벨 매핑(`metadata.json` = 0번이 무슨 클래스인지 표)은 **절대 올리지 않습니다**. 라벨 매핑은 사내 DB(`모델_레지스트리.클래스_라벨`)에만 둡니다.

### 3-2. Flutter 앱에 Firebase 연결

**Windows**
```powershell
cd C:\Users\yejin\Desktop\sesac_final\UsersyejinDesktopSeSAC_final\inspection_app
dart pub global activate flutterfire_cli
flutterfire configure --project=lng-inspection-ml
```

> 🍏 **macOS**
> ```bash
> cd ~/Desktop/final/inspection_app
> dart pub global activate flutterfire_cli
> export PATH="$PATH":"$HOME/.pub-cache/bin"
> flutterfire configure --project=lng-inspection-ml
> ```

명령이 끝나면 `lib/firebase_options.dart` 가 자동 생성됩니다.

`pubspec.yaml` 의존성 추가:

```yaml
  firebase_core: ^3.6.0
  firebase_ml_model_downloader: ^0.3.4+8
  crypto: ^3.0.5
  shared_preferences: ^2.3.2
```

```powershell
flutter pub get
```

---

## 4. 백엔드 — 모델 버전 API (OTA-001 / OTA-002)

> **단일 모델이므로 `process_id` 없음.** `모델_레지스트리` 에서 `모델_유형='TFLITE' AND 활성_여부=true` 인 **단 1개** 행을 반환합니다.

### 4-1. `backend/app/api/ota.py` (신규)

```python
from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.core.db import get_db
from app.core.config import settings
from app.api.deps import get_current_inspector_id

router = APIRouter()


@router.get("/model/version")
async def get_model_version(
    _: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    """단일 통합 모델의 최신 활성 TFLITE 정보. process_id 파라미터 없음 (OTA-001)."""
    row = (await db.execute(text("""
        SELECT 모델_ID, 모델_버전, 파일_경로, 파일_해시, 클래스_라벨
        FROM 모델_레지스트리
        WHERE 모델_유형 = 'TFLITE' AND 활성_여부 = true
        LIMIT 1
    """))).first()
    if row is None:
        raise HTTPException(status_code=404, detail={"error": "MODEL_NOT_READY"})
    return {
        "model_id": row[0],
        "version": row[1],
        "firebase_model_name": "best_model_v5_datamatch_full",
        "file_hash": row[3],        # "sha256:..."
        "class_labels": row[4],     # {"0":"균열-도장", ... "29":"폼스프레이양품-우레탄폼"}
    }


@router.patch("/admin/models/{model_id}/activate")
async def activate_model(
    model_id: int,
    x_admin_api_key: str = Header(default=""),
    db: AsyncSession = Depends(get_db),
):
    """검증 완료 모델 활성화 (OTA-002). 단일 모델 — 동일 모델_유형 내 기존 활성 1개 자동 비활성."""
    if x_admin_api_key != settings.ADMIN_API_KEY:
        raise HTTPException(status_code=401, detail={"error": "ADMIN_AUTH_FAILED"})

    target = (await db.execute(text("""
        SELECT 모델_유형 FROM 모델_레지스트리 WHERE 모델_ID = :id
    """), {"id": model_id})).first()
    if target is None:
        raise HTTPException(status_code=404, detail={"error": "NOT_FOUND"})
    model_type = target[0]

    # 단일 모델 정책: 공정_ID 조건 없음 — 모델_유형별 활성 1개만 (계획 변경 내용 §6-3)
    await db.execute(text("""
        UPDATE 모델_레지스트리 SET 활성_여부 = false
        WHERE 모델_유형 = :mt AND 활성_여부 = true
    """), {"mt": model_type})
    await db.execute(text("""
        UPDATE 모델_레지스트리 SET 활성_여부 = true WHERE 모델_ID = :id
    """), {"id": model_id})
    await db.commit()
    return {"activated": {"model_id": model_id, "model_type": model_type}}
```

> 💡 **6모델 구조와의 차이**: 기존 명세(API_SPEC OTA-002)는 `WHERE 공정_ID=? AND 모델_유형=?` 로 공정별 활성 모델을 관리했지만, 단일 모델에서는 `WHERE 모델_유형=?` 만으로 충분합니다. `공정_ID`는 메타로만 남고 NULL 허용 컬럼입니다 (`계획 변경 내용.md` §6-3, `backend/app/SINGLE_MODEL_GUIDE.md` §1).

### 4-2. `backend/app/main.py` 에 라우터 등록

```python
from app.api import ota
app.include_router(ota.router, prefix="/api", tags=["ota"])
```

### 4-3. 새 모델 버전 등록 (운영자 절차)

재학습된 모델을 배포할 때:

1. Firebase Console에서 `best_model_v5_datamatch_full` Custom 모델 파일을 새 `.tflite`로 교체 게시
2. SHA-256 해시 계산:
   **Windows**
   ```powershell
   (Get-FileHash best_model_v5_datamatch_full.tflite -Algorithm SHA256).Hash
   ```
   > 🍏 **macOS**
   > ```bash
   > shasum -a 256 best_model_v5_datamatch_full.tflite
   > ```
3. DB에 새 행 INSERT (비활성 상태):
   ```sql
   INSERT INTO 모델_레지스트리 (공정_ID, 모델_버전, 모델_유형, 파일_경로, 파일_해시, 클래스_라벨, 활성_여부)
   VALUES (NULL, 'v2', 'TFLITE', 'firebase://best_model_v5_datamatch_full',
           'sha256:계산한해시', '{"0":"균열-도장", ..., "29":"폼스프레이양품-우레탄폼"}', false);
   ```
   > `공정_ID = NULL` (단일 모델, 모델 선택에 미사용). `클래스_라벨` 은 30개 전체.
4. 검증 후 활성화: `PATCH /api/admin/models/{새 model_id}/activate` (`X-Admin-API-Key` 헤더 필수)

---

## 5. Flutter — OTA 다운로더

### 5-1. `lib/features/capture/data/local/model_ota_service.dart` (신규)

```dart
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:firebase_ml_model_downloader/firebase_ml_model_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/dio_client.dart';

class ModelOtaService {
  ModelOtaService(this.dio);
  final Dio dio;

  static const _firebaseModelName = 'best_model_v5_datamatch_full';
  static const _prefVersionKey = 'active_model_version';
  static const _prefPathKey = 'pending_model_path';

  /// 앱 시작 시 호출. 새 버전이 있으면 백그라운드 다운로드 + SHA-256 검증.
  /// 반환: 새 모델 준비됨 여부 (true면 "다음 시작 시 적용" 알림)
  Future<bool> checkAndDownload() async {
    final res = await dio.get('/model/version');
    final serverVersion = res.data['version'] as String;
    final expectedHash =
        (res.data['file_hash'] as String).replaceFirst('sha256:', '').toLowerCase();

    final prefs = await SharedPreferences.getInstance();
    final localVersion = prefs.getString(_prefVersionKey);
    if (localVersion == serverVersion) return false; // 이미 최신

    // Firebase ML 백그라운드 다운로드
    final model = await FirebaseModelDownloader.instance.getModel(
      _firebaseModelName,
      FirebaseModelDownloadType.latestModel,
      FirebaseModelDownloadConditions(androidWifiRequired: false),
    );

    // SHA-256 검증
    final bytes = await File(model.file.path).readAsBytes();
    final actualHash = sha256.convert(bytes).toString().toLowerCase();
    if (actualHash != expectedHash) {
      // 검증 실패 → 기존 모델 유지 (이번 버전 적용 안 함)
      return false;
    }

    // 검증 성공 → 다음 시작 시 적용되도록 경로만 저장 (검사 중 교체 금지)
    final docs = await getApplicationDocumentsDirectory();
    final dest = File('${docs.path}/$_firebaseModelName.tflite');
    await File(model.file.path).copy(dest.path);
    await prefs.setString(_prefVersionKey, serverVersion);
    await prefs.setString(_prefPathKey, dest.path);
    return true;
  }

  /// 다음 앱 시작 시 TFLite 서비스가 호출 — 적용할 모델 경로 (null이면 assets 번들 사용)
  Future<String?> resolveActiveModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPathKey);
  }
}

final modelOtaServiceProvider = Provider<ModelOtaService>(
  (ref) => ModelOtaService(ref.watch(dioProvider)),
);
```

> 💡 **왜 SHA-256 검증인가**: Firebase가 다운로드한 파일이 망 중간에 변조되거나 손상됐을 수 있습니다. 서버 DB의 해시와 일치하지 않으면 그 모델은 **사용하지 않고** 기존 모델을 유지합니다 (안전 우선).

### 5-2. TFLite 서비스가 OTA 모델을 우선 사용

13번에서 만든 `tflite_inference_service.dart` 의 `init()` 을 수정 — OTA로 받은 모델이 있으면 그걸 우선, 없으면 assets 번들 모델을 사용:

```dart
Future<void> init() async {
  if (_interpreter != null) return;
  final otaPath = await ref.read(modelOtaServiceProvider).resolveActiveModelPath();
  if (otaPath != null && await File(otaPath).exists()) {
    _interpreter = await Interpreter.fromFile(File(otaPath));
  } else {
    _interpreter = await Interpreter.fromAsset(
      'assets/models/best_model_v5_datamatch_full.tflite',
    );
  }
}
```

> ⚠️ 13번 단계에서 모델 파일명을 **`best_model_v5_datamatch_full.tflite`** 로, 라벨 배열을 `_unifiedLabels`(30개) 로 이미 작성했어야 합니다 (`계획 변경 내용.md` §5-4 참조). 안 됐다면 13번부터 점검.

### 5-3. 앱 시작 시 OTA 체크

`lib/main.dart` 의 `_InspectionAppState.initState()` 에 추가:

```dart
@override
void initState() {
  super.initState();
  Future.microtask(() async {
    ref.read(offlineSyncProvider).start();  // 13번에서 추가한 것
    final updated = await ref.read(modelOtaServiceProvider).checkAndDownload();
    if (updated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 AI 모델이 준비되었습니다. 다음 앱 시작 시 적용됩니다.')),
      );
    }
  });
}
```

> 문구는 명세서(`화면_명세서.md` 공통 UI "모델 OTA 알림") 원문 그대로 사용 — 요약·치환 금지.

---

## 6. 동작 확인

1. 백엔드 실행 → `GET /api/model/version` (Swagger에서 토큰 인증 후) → `{version, firebase_model_name, file_hash, class_labels}` 반환. 응답에 **`process_id` 필드 없음** 확인
2. 앱 첫 실행 → 로컬 버전 없음 → Firebase 다운로드 → SHA-256 일치 → "새 AI 모델이 준비되었습니다" 토스트 표시
3. 앱 재시작 → OTA로 받은 모델로 추론 (assets 번들 대신)
4. DB에서 새 모델 INSERT + `PATCH /api/admin/models/{id}/activate` (`X-Admin-API-Key` 헤더) → 기존 활성 자동 비활성, 새 것 활성
5. 클래스_라벨이 **30개**인지 확인:
   ```sql
   SELECT jsonb_object_keys(클래스_라벨) FROM 모델_레지스트리 WHERE 활성_여부 = true;
   ```
   → 0부터 29까지 30행 반환되어야 함

---

## 자주 발생하는 오류와 해결

### Firebase 모델 다운로드 실패 ("model not found")
- Firebase Console의 Custom 모델 이름이 코드의 `_firebaseModelName`(`best_model_v5_datamatch_full`)과 **정확히 일치**하는지 확인
- 프로젝트 ID 매칭 — `firebase_options.dart` 가 올바른 프로젝트(`lng-inspection-ml`)를 가리키는지

### SHA-256 불일치로 계속 거부됨
- DB의 `파일_해시` 가 실제 게시된 `.tflite` 의 해시와 다름. `Get-FileHash`/`shasum -a 256` 으로 재계산 후 DB UPDATE
- 해시 문자열 대소문자 — 비교 시 `.toLowerCase()` 통일 (위 코드에 이미 적용)

### `GET /api/model/version` 이 404 `MODEL_NOT_READY`
- `모델_레지스트리` 에 `모델_유형='TFLITE' AND 활성_여부=true` 행이 없음. 02번 시드 또는 OTA-002 활성화 API 확인

### `flutterfire configure` 실패
- `dart pub global activate flutterfire_cli` 실행 후 PATH 환경변수에 다음을 추가:
  - Windows: `%LOCALAPPDATA%\Pub\Cache\bin`
  - macOS/Linux: `$HOME/.pub-cache/bin`

### 검사 도중 모델이 바뀐 것 같음
- 본 구현은 `pending_model_path` 만 저장하고 **다음 앱 시작 시** 교체합니다. `init()` 호출 시점이 정상인지(`_interpreter == null` 일 때만) 확인.

---

## ✅ 다음 단계로 가기 전 체크리스트

- [ ] Firebase 프로젝트에 `best_model_v5_datamatch_full` Custom 모델이 게시됨
- [ ] `GET /api/model/version` 이 `process_id` 없이 단일 모델 정보를 반환한다
- [ ] 응답 `class_labels` 가 **30개** 다 (불량 19 + 양품 11)
- [ ] 응답 JSON 안에 `process_id` 필드가 없다
- [ ] 앱 시작 시 새 버전 감지 → 백그라운드 다운로드 → SHA-256 검증 동작
- [ ] 검증 실패 시 기존 모델이 유지된다 (앱이 깨지지 않음)
- [ ] "새 AI 모델이 준비되었습니다. 다음 앱 시작 시 적용됩니다." 토스트가 표시됨
- [ ] `PATCH /api/admin/models/{id}/activate` 가 `X-Admin-API-Key` 로 동작하고 기존 활성 모델을 자동 비활성화한다
- [ ] OTA-002 트랜잭션에 `공정_ID` 조건이 없음을 코드로 확인 (`WHERE 모델_유형 = :mt` 만)
- [ ] Firebase 에 모델 가중치 외 다른 데이터(매뉴얼·라벨 매핑)는 올라가 있지 않다 (보안 분리)
- [ ] 13번에서 `_unifiedLabels` 30개 + `best_model_v5_datamatch_full.tflite` 가 정합되어 있다

다음 단계 **[17_3주차_양품샘플링과_오프라인배치.md](17_3주차_양품샘플링과_오프라인배치.md)** 로 이동하세요.
