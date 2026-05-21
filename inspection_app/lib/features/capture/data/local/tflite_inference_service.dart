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

  bool get isPass => defectType.contains('양품');
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
    _interpreter!.allocateTensors();
  }

  Future<TfliteInferenceResult> infer(File imageFile) async {
    await init();
    final sw = Stopwatch()..start();

    final decoded = img.decodeImage(await imageFile.readAsBytes());
    if (decoded == null) throw Exception('이미지 디코딩 실패');
    final resized = img.copyResize(decoded, width: 224, height: 224);

    // Float32List로 입력 버퍼 구성 — TFLite가 직접 읽는 typed buffer
    final inputBuffer = Float32List(224 * 224 * 3);
    int idx = 0;
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final p = resized.getPixel(x, y);
        inputBuffer[idx++] = (p.r.toDouble() / 255.0 - 0.485) / 0.229;
        inputBuffer[idx++] = (p.g.toDouble() / 255.0 - 0.456) / 0.224;
        inputBuffer[idx++] = (p.b.toDouble() / 255.0 - 0.406) / 0.225;
      }
    }

    // List.generate로 출력 버퍼 구성 — TFLite가 outputList[0]에 직접 씀
    final outputList = List.generate(1, (_) => List.filled(_labels.length, 0.0));
    _interpreter!.run(
      inputBuffer.reshape([1, 224, 224, 3]),
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
