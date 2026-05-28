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
    flush();
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// 큐가 빌 때까지 10건씩 청크로 offline-batch 전송. 온라인 유지 중에도 누적분이
  /// 다음 재연결까지 미전송되지 않도록 단일 flush() 내부에서 반복한다.
  Future<int> flush() async {
    var total = 0;
    while (true) {
      final items = await queue.all(limit: 10);
      if (items.isEmpty) break;

      final form = FormData();
      final metadata = <Map<String, dynamic>>[];
      for (final it in items) {
        // 전수 보관 — 모든 항목 이미지 동봉. 서버는 파일명(client_request_id)으로 매칭.
        if (it.imagePath.isNotEmpty && await File(it.imagePath).exists()) {
          form.files.add(MapEntry(
            'images',
            await MultipartFile.fromFile(it.imagePath, filename: '${it.clientRequestId}.jpg'),
          ));
        }
        metadata.add({
          'client_request_id': it.clientRequestId,
          'session_id': it.sessionId,
          'process_id': it.processId,
          'tank_type': it.tankType,
          'captured_at': it.capturedAt.toIso8601String(),
          'on_device_result': jsonDecode(it.onDeviceJson),
          'kind': it.kind,
          if (it.sector != null) 'sector': it.sector,
          if (it.subsector != null) 'subsector': it.subsector,
        });
      }
      form.fields.add(MapEntry('metadata', jsonEncode(metadata)));

      try {
        final res = await dio.post(
          '/inspect/offline-batch',
          data: form,
          options: Options(contentType: 'multipart/form-data'),
        );
        final results = (res.data['results'] as List).cast<Map<String, dynamic>>();
        var progressed = false;
        for (final r in results) {
          final status = r['status'];
          // success/skipped(멱등 중복)만 제거. failed(예: 일시적 INFERENCE_ERROR)는
          // 큐에 남겨 다음 재연결에 재시도(데이터 유실 방지).
          if (status == 'success') {
            await queue.remove(r['client_request_id'] as String);
            total++;
            progressed = true;
          } else if (status == 'skipped') {
            await queue.remove(r['client_request_id'] as String);
            progressed = true;
          }
        }
        if (!progressed) break; // 이 청크에서 제거된 항목 없음(전부 failed/빈 결과) — 무한루프 방지
      } on DioException {
        break; // 네트워크 오류 — 다음 재연결에 재시도
      }
    }
    return total;
  }
}