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
    // 1) 단말 1차 추론 (TFLite 모델 없으면 서버 직행)
    TfliteInferenceResult? local;
    try {
      local = await tflite.infer(imageFile);
    } catch (_) {
      local = null;
    }

    // 2) 양품 + 신뢰도 충분 → 서버 호출 없음, /api/inspect/local-result만
    if (local != null && local.isPass && local.confidence >= _kPassThreshold) {
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
      } catch (_) {}
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

    final onDeviceJson = local == null ? null : jsonEncode({
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
      );
      return dto.toEntity();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        await queue.enqueue(
          imageFile: imageFile,
          sessionId: sessionId,
          processId: processId,
          tankType: tankType,
          onDeviceJson: onDeviceJson ?? '',
        );
        throw const QueuedOfflineFailure();
      }
      if ((e.response?.statusCode ?? 0) >= 500) throw const ServerFailure();
      throw const UnknownFailure();
    }
  }
}
