# 13. 2주차 — TFLite 단말 추론 + 하이브리드 분기 + 오프라인 큐

> **이 단계가 끝나면**: 앱이 사진을 찍자마자 폰에서 자체적으로 분류하고, 양품 + 신뢰도 ≥ 0.85면 서버 호출 없이 종결하며, 불량이거나 신뢰도가 낮으면 서버로 전송합니다. 네트워크가 끊겨도 sqflite 큐에 적재되어 복구 시 자동 동기화됩니다.
>
> **예상 시간**: 5시간
>
> **중요도**: ★★★★ — 단말 추론은 2주차의 핵심 가치 제안입니다.

> **참조 명세서**: `아키텍처_명세서.md` 하이브리드 추론 섹션, `제품_정의서.md` §2-1 / §2-4, `API_SPEC.md` INFER-001 / INFER-003 / INFER-005

---

## 1. 사전 준비 — TFLite 모델 파일

이 단계는 **`best_model_v5_datamatch_full.tflite` 모델 파일이 준비되어 있다고 가정**합니다.

### 모델이 없는 경우 — 임시 대안

학습 팀이 아직 모델을 만들지 않았다면, 학습 단계로 돌아가지 않고도 이 매뉴얼을 따라가기 위해 **공개 데이터셋 기반 더미 모델**을 만들 수 있습니다.

옵션 A — TensorFlow Hub의 사전 학습 MobileNet 사용:

```powershell
cd C:\Users\yejin\Desktop\sesac_final\UsersyejinDesktopSeSAC_final\backend
python -c "
import urllib.request
url = 'https://storage.googleapis.com/tfhub-lite-models/iree/lite-model/mobilenet_v2_100_224_classification/5/metadata/1.tflite'
urllib.request.urlretrieve(url, 'best_model_v5_datamatch_full.tflite')
print('Downloaded')
"
```

이 모델은 ImageNet 1000 클래스용이라 우리 7개 클래스와는 다릅니다. **단지 파이프라인이 동작하는지 확인 용도**입니다. 실제 분류 정확도는 의미 없음. 진짜 모델은 학습 팀이 별도 .tflite를 제공할 때 교체.

옵션 B — 학습 팀이 만든 진짜 `best_model_v5_datamatch_full.tflite`를 받아서 사용 (권장)

어느 쪽이든 결과 파일을 다음 위치에 둡니다:

```
inspection_app\assets\models\best_model_v5_datamatch_full.tflite
```

`pubspec.yaml`의 assets에 `assets/models/`가 이미 포함되어 있으므로 추가 작업 불필요.

---

## 2. Flutter — `tflite_flutter` 추가

`pubspec.yaml`의 `dependencies:`에 추가:

```yaml
tflite_flutter: ^0.12.0
```

```powershell
flutter pub get
```

> ⚠️ `tflite_flutter`는 native 라이브러리를 다운로드합니다. Android: 자동. 빌드 시 첫 실행이 느릴 수 있음 (5~10분).

---

## 3. 단말 추론 서비스

### 3-1. `features/capture/data/local/tflite_inference_service.dart`

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteInferenceResult {
  final String defectType;
  final double confidence;
  final List<({String label, double confidence})> top3;
  final int inferenceMs;

  const TfliteInferenceResult({
    required this.defectType,
    required this.confidence,
    required this.top3,
    required this.inferenceMs,
  });

  bool get isPass => defectType.contains('양품');  // 통합 30클래스 공통 — 공정 무관
}


class TfliteInferenceService {
  Interpreter? _interpreter;
  late final List<String> _labels;

  /// 단일 통합 모델 클래스 라벨 (30개) — 진짜 모델의 metadata.json·`모델_레지스트리.클래스_라벨`과 일치해야 함
  static const _unifiedLabels = [
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
    if (_interpreter != null) return;
    _interpreter = await Interpreter.fromAsset('assets/models/best_model_v5_datamatch_full.tflite');
    _labels = _unifiedLabels;
  }

  /// 224×224 RGB로 전처리 후 추론
  Future<TfliteInferenceResult> infer(File imageFile) async {
    final sw = Stopwatch()..start();

    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('이미지 디코딩 실패');
    }
    final resized = img.copyResize(decoded, width: 224, height: 224);

    // ImageNet 정규화: mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225]
    final input = List.generate(1, (_) => List.generate(224, (y) {
      return List.generate(224, (x) {
        final pixel = resized.getPixel(x, y);
        return [
          (pixel.r / 255.0 - 0.485) / 0.229,
          (pixel.g / 255.0 - 0.456) / 0.224,
          (pixel.b / 255.0 - 0.406) / 0.225,
        ];
      });
    }));

    // 출력: [1, num_classes]
    final output = List.filled(_labels.length, 0.0).reshape([1, _labels.length]);
    _interpreter!.run(input, output);

    final probs = (output[0] as List).cast<double>();
    // Softmax (모델이 logit을 내면 적용. 이미 softmax되어 있으면 그대로 OK)
    final maxLogit = probs.reduce((a, b) => a > b ? a : b);
    final exps = probs.map((p) => _exp(p - maxLogit)).toList();
    final sumExp = exps.reduce((a, b) => a + b);
    final normalized = exps.map((e) => e / sumExp).toList();

    final indexed = List.generate(_labels.length, (i) => MapEntry(i, normalized[i]));
    indexed.sort((a, b) => b.value.compareTo(a.value));

    final top3 = indexed.take(3).map((e) => (label: _labels[e.key], confidence: e.value)).toList();

    sw.stop();
    return TfliteInferenceResult(
      defectType: top3.first.label,
      confidence: top3.first.confidence,
      top3: top3,
      inferenceMs: sw.elapsedMilliseconds,
    );
  }

  double _exp(double x) {
    // dart:math.exp 직접 사용 가능
    return (x < -50) ? 0.0 : (x > 50 ? 5.18e21 : _expImpl(x));
  }

  double _expImpl(double x) {
    // dart:math.exp 사용
    return (x).exp();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

// dart:math 의 exp을 깔끔하게 쓰기 위한 extension
extension on double {
  double exp() => __dartExp(this);
}

double __dartExp(double x) {
  // 단순 wrapper — math.exp을 직접 사용
  return _math.exp(x);
}

// ignore: library_prefixes
import 'dart:math' as _math;
```

> ⚠️ 위 코드의 끝부분 import는 파일 **맨 위**로 옮겨야 합니다. Dart는 import를 파일 최상단에 모아야 컴파일됩니다. 위 코드를 옮기면서 정리:

**정리된 버전** — `tflite_inference_service.dart` 전체를 다음으로 대체:

```dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteInferenceResult {
  final String defectType;
  final double confidence;
  final List<({String label, double confidence})> top3;
  final int inferenceMs;

  const TfliteInferenceResult({
    required this.defectType,
    required this.confidence,
    required this.top3,
    required this.inferenceMs,
  });

  bool get isPass => defectType.contains('양품');  // 통합 30클래스 공통 — 공정 무관
}


class TfliteInferenceService {
  Interpreter? _interpreter;

  static const List<String> _labels = [
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
    if (_interpreter != null) return;
    _interpreter = await Interpreter.fromAsset('assets/models/best_model_v5_datamatch_full.tflite');
    _interpreter!.allocateTensors();  // 텐서 메모리 명시 할당
  }

  Future<TfliteInferenceResult> infer(File imageFile) async {
    await init();
    final sw = Stopwatch()..start();

    final decoded = img.decodeImage(await imageFile.readAsBytes());
    if (decoded == null) throw Exception('이미지 디코딩 실패');
    final resized = img.copyResize(decoded, width: 384, height: 384);

    // Float32List로 입력 버퍼 구성 — TFLite가 직접 읽는 typed buffer
    final inputBuffer = Float32List(384 * 384 * 3);
    int idx = 0;
    for (int y = 0; y < 384; y++) {
      for (int x = 0; x < 384; x++) {
        final p = resized.getPixel(x, y);
        inputBuffer[idx++] = (p.r.toDouble() / 255.0 - 0.485) / 0.229;
        inputBuffer[idx++] = (p.g.toDouble() / 255.0 - 0.456) / 0.224;
        inputBuffer[idx++] = (p.b.toDouble() / 255.0 - 0.406) / 0.225;
      }
    }

    // List.generate로 출력 버퍼 구성 — TFLite가 outputList[0]에 직접 씀
    // ⚠️ List.filled().reshape() 는 TFLite가 쓴 값이 원본에 반영되지 않아 항상 0 반환
    final outputList = List.generate(1, (_) => List.filled(_labels.length, 0.0));
    _interpreter!.run(
      inputBuffer.reshape([1, 384, 384, 3]),
      outputList,
    );
    final probs = (outputList[0] as List).cast<double>();

    final maxLogit = probs.reduce(math.max);
    final exps = probs.map((p) => math.exp(p - maxLogit)).toList();
    final sumExp = exps.reduce((a, b) => a + b);
    final normalized = exps.map((e) => e / sumExp).toList();

    final indexed = List.generate(_labels.length, (i) => MapEntry(i, normalized[i]))
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = indexed
        .take(3)
        .map((e) => (label: _labels[e.key], confidence: e.value))
        .toList();

    sw.stop();
    return TfliteInferenceResult(
      defectType: top3.first.label,
      confidence: top3.first.confidence,
      top3: top3,
      inferenceMs: sw.elapsedMilliseconds,
    );
  }

  void dispose() => _interpreter?.close();
}
```

> 💡 **`reshape` extension은 어디서?** `tflite_flutter` 패키지에 같이 들어 있는 `ListShape` extension이 List에 `reshape` 메서드를 추가합니다. import만으로 자동 노출.

### 3-2. Provider

`features/capture/presentation/providers/capture_providers.dart` 에 추가:

```dart
import '../../data/local/tflite_inference_service.dart';

final tfliteServiceProvider = Provider<TfliteInferenceService>((ref) {
  final s = TfliteInferenceService();
  ref.onDispose(() => s.dispose());
  return s;
});
```

---

## 4. 오프라인 큐 — sqflite

### 4-1. `features/capture/data/local/offline_queue.dart`

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class OfflineQueueItem {
  final String clientRequestId;
  final String imagePath;
  final int sessionId;
  final int processId;
  final String tankType;
  final String onDeviceJson;
  final DateTime capturedAt;

  const OfflineQueueItem({
    required this.clientRequestId,
    required this.imagePath,
    required this.sessionId,
    required this.processId,
    required this.tankType,
    required this.onDeviceJson,
    required this.capturedAt,
  });
}


class OfflineQueueDb {
  Database? _db;
  static const _uuid = Uuid();

  Future<Database> get db async {
    if (_db != null) return _db!;
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'offline_queue.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE pending_uploads (
            client_request_id TEXT PRIMARY KEY,
            image_path TEXT NOT NULL,
            session_id INTEGER NOT NULL,
            process_id INTEGER NOT NULL,
            tank_type TEXT NOT NULL,
            on_device_json TEXT NOT NULL,
            captured_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<String> enqueue({
    required File imageFile,
    required int sessionId,
    required int processId,
    required String tankType,
    required String onDeviceJson,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final queueDir = Directory(p.join(docs.path, 'queue_images'));
    if (!await queueDir.exists()) await queueDir.create(recursive: true);

    final clientId = _uuid.v4();
    final newPath = p.join(queueDir.path, '$clientId.jpg');
    await imageFile.copy(newPath);

    final database = await db;
    await database.insert('pending_uploads', {
      'client_request_id': clientId,
      'image_path': newPath,
      'session_id': sessionId,
      'process_id': processId,
      'tank_type': tankType,
      'on_device_json': onDeviceJson,
      'captured_at': DateTime.now().toIso8601String(),
    });
    return clientId;
  }

  Future<List<OfflineQueueItem>> all({int limit = 50}) async {
    final database = await db;
    final rows = await database.query('pending_uploads', limit: limit, orderBy: 'captured_at ASC');
    return rows.map((r) => OfflineQueueItem(
          clientRequestId: r['client_request_id'] as String,
          imagePath: r['image_path'] as String,
          sessionId: r['session_id'] as int,
          processId: r['process_id'] as int,
          tankType: r['tank_type'] as String,
          onDeviceJson: r['on_device_json'] as String,
          capturedAt: DateTime.parse(r['captured_at'] as String),
        )).toList();
  }

  Future<int> count() async {
    final database = await db;
    final res = await database.rawQuery('SELECT COUNT(*) as c FROM pending_uploads');
    return (res.first['c'] as int?) ?? 0;
  }

  Future<void> remove(String clientRequestId) async {
    final database = await db;
    await database.delete('pending_uploads', where: 'client_request_id = ?', whereArgs: [clientRequestId]);
    // 이미지 파일도 삭제
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'queue_images', '$clientRequestId.jpg');
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
```

Provider:

```dart
// capture_providers.dart 에 추가
import '../../data/local/offline_queue.dart';
final offlineQueueProvider = Provider<OfflineQueueDb>((_) => OfflineQueueDb());
```

---

## 5. Repository — 하이브리드 분기 + 오프라인 큐

`features/capture/data/repositories/capture_repository_impl.dart` 를 다음 버전으로 교체:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/capture_result.dart';
import '../../domain/repositories/capture_repository.dart';
import '../datasources/capture_remote_data_source.dart';
import '../local/offline_queue.dart';
import '../local/tflite_inference_service.dart';


/// 단말 양품 종결 임계값 (공정.신뢰도_임계값과 동일 — 추후 백엔드 응답으로 가져오도록 동적화)
const double _kPassThreshold = 0.85;


class CaptureRepositoryImpl implements CaptureRepository {
  final CaptureRemoteDataSource remote;
  final TfliteInferenceService tflite;
  final OfflineQueueDb queue;
  final Dio dio;

  CaptureRepositoryImpl({
    required this.remote,
    required this.tflite,
    required this.queue,
    required this.dio,
  });

  @override
  Future<CaptureResult> uploadAndInspect({
    required File imageFile,
    required int sessionId,
    required int processId,
    required String tankType,
  }) async {
    // 1) 단말 1차 추론
    final local = await tflite.infer(imageFile);

    // 2) 양품 + 신뢰도 충분 → 서버 호출 없음, /api/inspect/local-result만
    if (local.isPass && local.confidence >= _kPassThreshold) {
      try {
        await dio.post('/inspect/local-result', data: {
          'session_id': sessionId,
          'process_id': processId,
          'tank_type': tankType,
          'defect_type': local.defectType,
          'confidence': local.confidence,
          'top3_predictions': local.top3.map((e) => {'class': e.label, 'confidence': e.confidence}).toList(),
          'inference_ms': local.inferenceMs,
          'is_sampling': false,
          'captured_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {
        // 양품인데 메타 기록 실패: 큐로 보낼 필요 없음 (DB 손실보다 트래픽 절약 우선)
      }
      return CaptureResult(
        imageId: -1, resultId: -1,
        defectType: local.defectType,
        confidence: local.confidence,
        isDefect: false,
        heatmapUrl: null,
      );
    }

    // 3) 불량 또는 저신뢰도 → 서버 정밀 분석
    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity.any((r) => r != ConnectivityResult.none);

    final onDeviceJson = jsonEncode({
      'defect_type': local.defectType,
      'confidence': local.confidence,
      'inference_ms': local.inferenceMs,
      'top3_predictions': local.top3.map((e) => {'class': e.label, 'confidence': e.confidence}).toList(),
    });

    if (!isOnline) {
      // 오프라인 → 큐에 적재
      await queue.enqueue(
        imageFile: imageFile,
        sessionId: sessionId,
        processId: processId,
        tankType: tankType,
        onDeviceJson: onDeviceJson,
      );
      throw const QueuedOfflineFailure();
    }

    try {
      final dto = await remote.uploadAndInspectWithDevice(
        imageFile: imageFile,
        sessionId: sessionId,
        processId: processId,
        tankType: tankType,
        onDeviceJson: onDeviceJson,
      );
      return dto.toEntity();
    } on DioException catch (e) {
      // 일시 네트워크 오류 → 오프라인 큐로
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        await queue.enqueue(
          imageFile: imageFile,
          sessionId: sessionId,
          processId: processId,
          tankType: tankType,
          onDeviceJson: onDeviceJson,
        );
        throw const QueuedOfflineFailure();
      }
      if ((e.response?.statusCode ?? 0) >= 500) throw const ServerFailure();
      throw const UnknownFailure();
    }
  }
}


// ⚠️ Failure는 sealed class라 외부에서 implements 불가.
// core/error/failure.dart 에 QueuedOfflineFailure를 extends로 추가해야 함:
//
// class QueuedOfflineFailure extends Failure {
//   const QueuedOfflineFailure()
//       : super('오프라인 — 검사 결과를 저장했습니다. 네트워크 복구 시 자동으로 업로드됩니다.');
// }
```

### 5-1. DataSource에 device 결과 동봉 메서드 추가

`features/capture/data/datasources/capture_remote_data_source.dart` 에 추가:

```dart
Future<InspectResponseDto> uploadAndInspectWithDevice({
  required File imageFile,
  required int sessionId,
  required int processId,
  required String tankType,
  required String onDeviceJson,
}) async {
  final form = FormData.fromMap({
    'image': await MultipartFile.fromFile(imageFile.path, filename: 'capture.jpg'),
    'session_id': sessionId,
    'process_id': processId,
    'tank_type': tankType,
    'on_device_result': onDeviceJson,
  });
  final res = await dio.post('/inspect', data: form, options: Options(contentType: 'multipart/form-data'));
  return InspectResponseDto.fromJson(res.data as Map<String, dynamic>);
}
```

### 5-2. Provider 갱신

`capture_providers.dart`:

```dart
final captureRepositoryProvider = Provider<CaptureRepository>(
  (ref) => CaptureRepositoryImpl(
    remote: ref.watch(captureRemoteProvider),
    tflite: ref.watch(tfliteServiceProvider),
    queue: ref.watch(offlineQueueProvider),
    dio: ref.watch(dioProvider),
  ),
);
```

---

## 6. 오프라인 큐 자동 flush

### 6-1. `features/capture/data/local/offline_sync_service.dart`

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import 'offline_queue.dart';

class OfflineSyncService {
  final OfflineQueueDb queue;
  final Dio dio;
  StreamSubscription? _sub;

  OfflineSyncService({required this.queue, required this.dio});

  void start() {
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) flush();
    });
    // 앱 시작 시도 한 번
    flush();
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<int> flush() async {
    final items = await queue.all(limit: 50);
    if (items.isEmpty) return 0;

    // INFER-005: 배치 업로드 (멱등성 키)
    final form = FormData();
    final metadata = <Map<String, dynamic>>[];
    for (final it in items) {
      form.files.add(MapEntry('images', await MultipartFile.fromFile(it.imagePath, filename: '${it.clientRequestId}.jpg')));
      metadata.add({
        'client_request_id': it.clientRequestId,
        'session_id': it.sessionId,
        'process_id': it.processId,
        'tank_type': it.tankType,
        'captured_at': it.capturedAt.toIso8601String(),
        'on_device_result': jsonDecode(it.onDeviceJson),
      });
    }
    form.fields.add(MapEntry('metadata', jsonEncode(metadata)));

    try {
      final res = await dio.post('/inspect/offline-batch', data: form, options: Options(contentType: 'multipart/form-data'));
      final results = (res.data['results'] as List).cast<Map<String, dynamic>>();
      var success = 0;
      for (final r in results) {
        if (r['status'] == 'success') {
          await queue.remove(r['client_request_id'] as String);
          success++;
        }
      }
      return success;
    } on DioException {
      return 0; // 다음 트리거에서 재시도
    }
  }
}
```

### 6-2. Provider + main.dart에서 시작

`capture_providers.dart`:

```dart
import '../../data/local/offline_sync_service.dart';

final offlineSyncProvider = Provider<OfflineSyncService>((ref) {
  final svc = OfflineSyncService(
    queue: ref.watch(offlineQueueProvider),
    dio: ref.watch(dioProvider),
  );
  ref.onDispose(svc.stop);
  return svc;
});
```

`lib/main.dart`의 `InspectionApp` 에 한 번 시작:

```dart
class InspectionApp extends ConsumerStatefulWidget {
  const InspectionApp({super.key});
  @override
  ConsumerState<InspectionApp> createState() => _InspectionAppState();
}

class _InspectionAppState extends ConsumerState<InspectionApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(offlineSyncProvider).start());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'LNG Inspection',
      theme: AppTheme.light(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

---

## 7. 백엔드 수정

### 7-0. `/inspect` 엔드포인트 버그 수정 (동작 확인 중 발견)

`app/api/inspect.py`의 기존 `POST /inspect`에 두 가지 수정이 필요합니다.

**① `검사_이미지` INSERT 컬럼 오류 수정**

존재하지 않는 컬럼(`탱크_타입`, `선택_구역`, `선택_세부위치`)을 제거:

```python
# 수정 전 (500 에러 발생)
INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 탱크_타입, 선택_구역, 선택_세부위치, 촬영_일시)
VALUES (:sid, :path, :tt, :sec, :sub, NOW())

# 수정 후
INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 촬영_일시)
VALUES (:sid, :path, NOW())
```

**② 단말 결과 INSERT 추가**

`on_device_result`가 전송됐을 때 단말 row를 DB에 저장하는 블록 추가 (없으면 단말 결과가 DB에 기록되지 않음):

```python
# 4-a) 단말 결과 INSERT (on_device_result가 있을 때)
if on_device_result:
    import json as _json
    dev = _json.loads(on_device_result)
    await db.execute(text("""
        INSERT INTO 검사_결과 (
            이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
            결함_유형, 신뢰도_점수, 상위_예측, 추론_지연_ms,
            사람_재확인_필요, 결과_처리_상태
        ) VALUES (
            :iid, :pid, '단말', false, :ok,
            :dtype, :conf, CAST(:top3 AS JSONB), :ms,
            false, '완료'
        )
    """), {
        "iid": image_id, "pid": process_id,
        "ok": "양품" in dev.get("defect_type", ""),
        "dtype": dev.get("defect_type", ""),
        "conf": dev.get("confidence", 0),
        "top3": _json.dumps(dev.get("top3_predictions", [])),
        "ms": dev.get("inference_ms", 0),
    })
```

---

### 7-1. INFER-005 오프라인 배치

`app/api/inspect.py` 에 추가:

```python
@router.post("/inspect/offline-batch")
async def offline_batch(
    images: list[UploadFile] = File(...),
    metadata: str = Form(...),
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    import json
    metas = json.loads(metadata)
    if len(metas) != len(images):
        raise HTTPException(status_code=400, detail={"error": "METADATA_IMAGE_COUNT_MISMATCH"})
    if len(metas) > 50:
        raise HTTPException(status_code=400, detail={"error": "BATCH_SIZE_LIMIT_EXCEEDED"})

    results = []
    for img_file, meta in zip(images, metas):
        try:
            # MVP: 단순히 INFER-002와 동일한 더미 로직 + client_request_id 기록
            # 실제 운영에서는 client_request_id를 별도 테이블에 기록하여 중복 INSERT 방지
            _WEIGHTS = [3 if "양품" in c else 1 for c in _CLASSES]
            top1 = random.choices(_CLASSES, weights=_WEIGHTS)[0]  # 30클래스: 양품 비중 ↑
            conf = round(random.uniform(0.55, 0.99), 3)
            is_defect_flag = _is_defect(top1)

            img_row = (await db.execute(text("""
                INSERT INTO 검사_이미지 (세션_ID, 이미지_경로, 촬영_일시)
                VALUES (:sid, :path, NOW())
                RETURNING 이미지_ID
            """), {"sid": meta["session_id"], "path": f"local://batch/{meta['client_request_id']}.jpg"})).first()
            image_id = img_row[0]

            res_row = (await db.execute(text("""
                INSERT INTO 검사_결과 (이미지_ID, 공정_ID, 추론_위치, 대표_여부, 품질_여부,
                    결함_유형, 신뢰도_점수, 추론_지연_ms, 결과_처리_상태)
                VALUES (:iid, :pid, '서버', true, :ok, :dtype, :conf, :ms, '미완료')
                RETURNING 결과_ID
            """), {
                "iid": image_id, "pid": meta["process_id"], "ok": not is_defect_flag,
                "dtype": top1, "conf": conf, "ms": random.randint(900, 1500),
            })).first()

            await db.execute(text("""
                UPDATE 검사_세션 SET 총_이미지_수 = 총_이미지_수 + 1,
                                  양품_수 = 양품_수 + :p,
                                  불량_수 = 불량_수 + :d
                WHERE 세션_ID = :sid
            """), {"sid": meta["session_id"], "p": 0 if is_defect_flag else 1, "d": 1 if is_defect_flag else 0})

            results.append({
                "client_request_id": meta["client_request_id"],
                "status": "success",
                "image_id": image_id,
                "server_result": {"result_id": res_row[0], "defect_type": top1, "confidence": conf,
                                  "inference_ms": random.randint(900, 1500), "needs_human_review": False},
            })
        except Exception as e:
            results.append({"client_request_id": meta["client_request_id"], "status": "failed",
                            "error_code": "INFERENCE_ERROR", "error_message": str(e)})

    await db.commit()
    success_count = sum(1 for r in results if r["status"] == "success")
    return {
        "batch_size": len(metas),
        "succeeded_count": success_count,
        "failed_count": len(metas) - success_count,
        "results": results,
    }
```

> ⚠️ 운영 환경에서는 **`client_request_id`를 unique 컬럼**으로 가진 별도 테이블 (`멱등성_요청` 등)을 두어 중복 처리해야 합니다. 위 MVP는 단순화.

---

## 8. 동작 확인

### 시나리오 A — 단말 양품 종결 (서버 호출 없음)

1. 양품으로 분류될 만한 사진 촬영 (실기기 권장)
2. uvicorn 콘솔: **`POST /api/inspect`는 호출 안 됨**, **`POST /api/inspect/local-result`만 호출됨** ✅
3. DB:
   ```sql
   SELECT 추론_위치, 결함_유형, 신뢰도_점수 FROM 검사_결과 ORDER BY 결과_ID DESC LIMIT 1;
   ```
   `추론_위치 = '단말'`, `대표_여부 = true`, `결과_처리_상태 = '완료'`

### 시나리오 B — 단말 불량 → 서버 정밀 분석

1. 불량 사진 촬영
2. uvicorn 콘솔: **`POST /api/inspect` 호출됨** ✅
3. 서버가 단말 결과를 받아 `검사_결과` 2행 (단말 + 서버) 생성

### 시나리오 C — 오프라인 큐

1. 폰을 비행기 모드 또는 백엔드 일시 중지
2. 불량 사진 촬영 → 토스트 "오프라인 — ... 자동 업로드됩니다"
3. DB의 `pending_uploads` 테이블에 행이 추가됨 (단말 sqflite)
4. 비행기 모드 해제 → connectivity_plus 트리거 → `OfflineSyncService.flush()` 호출 → `POST /api/inspect/offline-batch` 발생
5. PostgreSQL에 행이 들어가고 sqflite 큐가 비워짐

> 💡 폰 sqflite 내부를 직접 보고 싶다면: 에뮬레이터에서 `adb shell run-as com.shipyard.inspection_app cat /data/data/com.shipyard.inspection_app/app_flutter/offline_queue.db | sqlite3 -` (복잡하므로 처음에는 카운터·로그로만 확인)

---

## 자주 발생하는 오류와 해결

### "Failed to load model best_model_v5_datamatch_full.tflite"

- `pubspec.yaml`의 `assets: - assets/models/`가 들어있는지 확인
- `flutter pub get` + `flutter clean` + 재실행
- 파일 경로가 정확히 `assets/models/best_model_v5_datamatch_full.tflite`인지

### `Bad state: failed precondition`
- 모델의 입력 shape과 코드의 이미지 크기가 다를 때 발생
- `best_model_v5_datamatch_full.tflite`의 입력 shape은 `[1, 384, 384, 3]` — 224가 아닌 **384**
- `tflite_inference_service.dart`의 `copyResize`, `Float32List`, for loop, `reshape` 모두 384로 맞춰야 함

### TFLite 입력 shape mismatch

- 모델이 기대하는 입력이 다를 수 있음. 진짜 모델이라면 `metadata.json`의 input shape 확인
- 일반 ImageNet MobileNet은 `[1, 224, 224, 3]` (Height-Width-Channel)

### 추론 결과가 항상 같은 클래스

- 모델이 ImageNet 사전학습 그대로면 표면처리 클래스랑 무관. 진짜 모델로 교체 필요

### sqflite 'database is locked'

- 트랜잭션 안에서 다른 트랜잭션을 호출하지 마세요
- `flush()` 중에 `enqueue()`가 동시 호출되면 락. 락이 풀린 후 자동 재시도되므로 처음에는 무시 OK

### connectivity_plus가 변화 감지 안 함

- 안드로이드 권한 `ACCESS_NETWORK_STATE`가 manifest에 있는지 확인 (03번 단계에서 추가했음)

---

## ✅ 다음 단계로 가기 전 체크리스트

- [ ] `assets/models/best_model_v5_datamatch_full.tflite` 파일이 존재한다 (진짜 모델 또는 더미)
- [ ] 양품 + 신뢰도 ≥ 0.85일 때 `POST /api/inspect`가 호출되지 않는다
- [ ] 양품 시 `POST /api/inspect/local-result`만 호출된다
- [ ] 불량 시 `POST /api/inspect` (이미지 + on_device_result 동봉) 호출
- [ ] 비행기 모드에서 촬영 시 토스트 "오프라인 — ..." 표시
- [ ] sqflite의 `pending_uploads` 테이블에 행이 쌓인다
- [ ] 네트워크 복구 시 `POST /api/inspect/offline-batch`가 자동 호출되어 큐가 비워진다
- [ ] DB의 `검사_결과.추론_위치`가 단말/서버 두 종류로 들어간다 (불량 케이스)

다음 단계 **[14*2주차*백엔드*RAG*정밀분석.md](14_2주차_백엔드_RAG_정밀분석.md)** 로 이동하세요.
