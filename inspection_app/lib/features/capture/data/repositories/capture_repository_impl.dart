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

    // 2) 양품 + 신뢰도 충분 → 단말 자동 종결 UX.
    //    C-B: 온라인은 동기 /inspect 로 서버 재추론·검증(불일치는 서버가 미완료로 기록),
    //    오프라인은 큐. 촬영 화면은 어느 경우든 auto-close(결과화면 미진입).
    if (local != null && local.isPass && local.confidence >= _kPassThreshold) {
      final onDeviceJson = jsonEncode({
        'defect_type': local.defectType,
        'confidence': local.confidence,
        'inference_ms': local.inferenceMs,
        'top3_predictions': local.top3.map((e) => {'class': e.label, 'confidence': e.confidence}).toList(),
      });

      final passResult = CaptureResult(
        imageId: -1,
        resultId: -1,
        defectType: local.defectType,
        confidence: local.confidence,
        isDefect: false,
        heatmapUrl: null,
      );

      final connectivity = await Connectivity().checkConnectivity();
      final isOnline = connectivity.any((r) => r != ConnectivityResult.none);

      // 오프라인 양품 → 큐 적재(복구 시 동기화). 단말 자동 종결이므로 성공으로 보이게 처리.
      if (!isOnline) {
        await queue.enqueue(
          imageFile: imageFile,
          sessionId: sessionId,
          processId: processId,
          tankType: tankType,
          onDeviceJson: onDeviceJson,
          sector: sector,
          subsector: subsector,
          kind: 'pass',
        );
        return passResult;
      }

      // 온라인 양품 → 불량 경로와 동일하게 동기 /inspect(서버 재추론·검증·S3·random10%).
      // 서버가 불량으로 flip 해도 촬영 시점엔 표시하지 않고 auto-close. 검사 이력에 미완료로 노출.
      try {
        await remote.uploadAndInspectWithDevice(
          imageFile: imageFile,
          sessionId: sessionId,
          processId: processId,
          tankType: tankType,
          onDeviceJson: onDeviceJson,
          sector: sector,
          subsector: subsector,
        );
      } on DioException catch (e) {
        // 네트워크 실패 → 큐 적재 후 성공으로 처리(자동 종결 UX 유지)
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          await queue.enqueue(
            imageFile: imageFile,
            sessionId: sessionId,
            processId: processId,
            tankType: tankType,
            onDeviceJson: onDeviceJson,
            sector: sector,
            subsector: subsector,
            kind: 'pass',
          );
        }
        // 그 외 서버 오류도 양품 auto-close 유지 — 조용히 넘어감
      }
      return passResult;
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
}
