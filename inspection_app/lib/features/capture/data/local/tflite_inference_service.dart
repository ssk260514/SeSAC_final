import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'model_ota_service.dart';

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

  bool get isPass => defectType.contains('양품');
}


class TfliteInferenceService {
  TfliteInferenceService({this.otaService});
  final ModelOtaService? otaService;

  Interpreter? _interpreter;

  static const List<String> _labels = [
    // 용접 (0~2)
    '용접불량-조인트', '용접블로우홀-조인트', '용접양품-조인트',
    // 절단 (3~6)
    '절단불량-모재', '절단불량-보온재', '절단양품-모재', '절단양품-보온재',
    // 케이블 (7~12)
    '바인딩불량-케이블타이', '바인딩양품-케이블타이',
    '케이블설치불량-케이블그랜드', '케이블설치양품-케이블그랜드',
    '케이블손상-케이블', '케이블양품-케이블',
    // 파이프 (13~14)
    '볼트체결불량-파이프', '볼트체결양품-파이프',
    // 폼스프레이 (15~16)
    '폼스프레이불량-우레탄폼', '폼스프레이양품-우레탄폼',
    // 표면처리 (17~29)
    '균열-도장', '균열-보온재', '도막떨어짐-도장', '도막분리-도장', '도장흐름-도장',
    '보온재손상-보온재', '스크래치-도장', '스크래치-모재', '스크래치-보온재', '탱크클리닝불량-모재',
    '표면양품-도장', '표면양품-모재', '표면양품-보온재',
  ];

  Future<void> init() async {
    if (_interpreter != null) return;
    final otaPath = await otaService?.resolveActiveModelPath();
    if (otaPath != null && await File(otaPath).exists()) {
      _interpreter = Interpreter.fromFile(File(otaPath));
    } else {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/best_model_v5_datamatch_full.tflite',
      );
    }
    _interpreter!.allocateTensors();

    // 모델 실제 입출력 shape 진단 — 콘솔에서 확인 후 이 블록 제거
    final inShape  = _interpreter!.getInputTensor(0).shape;
    final outShape = _interpreter!.getOutputTensor(0).shape;
    // ignore: avoid_print
    print('[TFLite] input shape : $inShape');   // 예: [1, 224, 224, 3] 또는 [1, 384, 384, 3]
    // ignore: avoid_print
    print('[TFLite] output shape: $outShape');  // 예: [1, 30] — 30이 아니면 라벨 배열과 불일치
  }

  Future<TfliteInferenceResult> infer(File imageFile) async {
    await init();
    final sw = Stopwatch()..start();

    final decoded = img.decodeImage(await imageFile.readAsBytes());
    if (decoded == null) throw Exception('이미지 디코딩 실패');
    final resized = img.copyResize(decoded, width: 384, height: 384,
        interpolation: img.Interpolation.linear);

    // 모델 입력: NCHW [1, 3, 384, 384] — PyTorch 네이티브 채널 우선 배치
    const h = 384, w = 384;
    final inputBuffer = Float32List(3 * h * w);
    const means = [0.485, 0.456, 0.406];
    const stds  = [0.229, 0.224, 0.225];
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = resized.getPixel(x, y);
        final pixelIdx = y * w + x;
        inputBuffer[0 * h * w + pixelIdx] = (p.r.toDouble() / 255.0 - means[0]) / stds[0];
        inputBuffer[1 * h * w + pixelIdx] = (p.g.toDouble() / 255.0 - means[1]) / stds[1];
        inputBuffer[2 * h * w + pixelIdx] = (p.b.toDouble() / 255.0 - means[2]) / stds[2];
      }
    }

    final outputList = List.generate(1, (_) => List.filled(_labels.length, 0.0));
    _interpreter!.run(
      inputBuffer.reshape([1, 3, h, w]),
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
