import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/capture_result.dart';
import '../../domain/repositories/capture_repository.dart';
import '../datasources/capture_remote_data_source.dart';
import '../local/offline_queue.dart';
import '../local/tflite_inference_service.dart';

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
    String? sector,
    String? subsector,
  }) async {
    // 1) 단말 1차 추론
    TfliteInferenceResult? local;
    try {
      local = await tflite.infer(imageFile);
    } catch (_) {
      local = null;
    }

    // 2) 양품 + 신뢰도 충분 → 단말 자동 종결. 서버엔 메타만(local-result), 10%만 S3 샘플.
    if (local != null && local.isPass && local.confidence >= _kPassThreshold) {
      final capturedAt = DateTime.now().toIso8601String();
      final needsSample = Random().nextDouble() < 0.10; // 10% 재학습 샘플 대상

      final connectivity = await Connectivity().checkConnectivity();
      final isOnline = connectivity.any((r) => r != ConnectivityResult.none);

      // 오프라인 양품 → 큐에 적재해 복구 시 동기화 (카운터 + 10% 샘플 모두 보존).
      // 양품은 단말 자동 종결이므로 사용자에겐 성공으로 보이게 QueuedOfflineFailure 를 던지지 않음.
      if (!isOnline) {
        await queue.enqueue(
          imageFile: imageFile,
          sessionId: sessionId,
          processId: processId,
          tankType: tankType,
          onDeviceJson: jsonEncode({
            'defect_type': local.defectType,
            'confidence': local.confidence,
            'inference_ms': local.inferenceMs,
            'top3_predictions': local.top3.map((e) => {'class': e.label, 'confidence': e.confidence}).toList(),
          }),
          sector: sector,
          subsector: subsector,
          kind: 'pass',
          needsSample: needsSample,
        );
        return CaptureResult(
          imageId: -1,
          resultId: -1,
          defectType: local.defectType,
          confidence: local.confidence,
          isDefect: false,
          heatmapUrl: null,
        );
      }

      // 온라인 양품 → 현행: 10% S3 샘플(best-effort) + local-result 메타 기록
      if (needsSample) {
        unawaited(_uploadSampleAsync(
          local,
          imageFile,
          sessionId: sessionId,
          processId: processId,
          capturedAt: capturedAt,
        ));
      }

      try {
        await dio.post('/inspect/local-result', data: {
          'session_id': sessionId,
          'process_id': processId,
          'tank_type': tankType,
          if (sector != null) 'sector': sector,
          if (subsector != null) 'subsector': subsector,
          'defect_type': local.defectType,
          'confidence': local.confidence,
          'top3_predictions': local.top3.map((e) => {'class': e.label, 'confidence': e.confidence}).toList(),
          'inference_ms': local.inferenceMs,
          'is_sampling': false,
          'captured_at': capturedAt,
        });
      } catch (_) {}
      return CaptureResult(
        imageId: -1,
        resultId: -1,
        defectType: local.defectType,
        confidence: local.confidence,
        isDefect: false,
        heatmapUrl: null,
      );
    }

    // 3) 불량 또는 저신뢰도 → 서버 정밀 분석
    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity.any((r) => r != ConnectivityResult.none);

    final String? onDeviceJson = local == null ? null : jsonEncode({
      'defect_type': local.defectType,
      'confidence': local.confidence,
      'inference_ms': local.inferenceMs,
      'top3_predictions': local.top3.map((e) => {'class': e.label, 'confidence': e.confidence}).toList(),
    });

    if (!isOnline) {
      await queue.enqueue(
        imageFile: imageFile,
        sessionId: sessionId,
        processId: processId,
        tankType: tankType,
        onDeviceJson: onDeviceJson ?? '',
        sector: sector,
        subsector: subsector,
      );
      throw const QueuedOfflineFailure();
    }

    try {
      final dto = await remote.uploadAndInspectWithDevice(
        imageFile: imageFile,
        sessionId: sessionId,
        processId: processId,
        tankType: tankType,
        onDeviceJson: onDeviceJson ?? '',
        sector: sector,
        subsector: subsector,
      );
      return dto.toEntity();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        await queue.enqueue(
          imageFile: imageFile,
          sessionId: sessionId,
          processId: processId,
          tankType: tankType,
          onDeviceJson: onDeviceJson ?? '',
          sector: sector,
          subsector: subsector,
        );
        throw const QueuedOfflineFailure();
      }
      if ((e.response?.statusCode ?? 0) >= 500) throw const ServerFailure();
      throw const UnknownFailure();
    }
  }

  Future<void> _uploadSampleAsync(
    TfliteInferenceResult result,
    File imageFile, {
    required int sessionId,
    required int processId,
    required String capturedAt,
  }) async {
    try {
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(imageFile.path, filename: 'sample.jpg'),
        'session_id': sessionId.toString(),
        'process_id': processId.toString(),
        'defect_type': result.defectType,
        'confidence': result.confidence,
        'captured_at': capturedAt,
      });
      await dio.post('/inspect/sample-upload', data: form,
          options: Options(contentType: 'multipart/form-data'));
    } catch (_) {
      // best-effort — 실패해도 사용자 경험에 영향 없음
    }
  }
}
