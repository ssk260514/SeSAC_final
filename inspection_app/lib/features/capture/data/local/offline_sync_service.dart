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

  Future<int> flush() async {
    final items = await queue.all(limit: 50);
    if (items.isEmpty) return 0;

    final form = FormData();
    final metadata = <Map<String, dynamic>>[];
    for (final it in items) {
      // 이미지는 보관된 항목만 동봉(불량 + 10% 샘플 양품). 비샘플링 양품은 메타만 전송.
      // 서버는 파일명(client_request_id)으로 메타와 이미지를 매칭한다.
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
        'needs_sample': it.needsSample,
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
      var success = 0;
      for (final r in results) {
        if (r['status'] == 'success') {
          await queue.remove(r['client_request_id'] as String);
          success++;
        } else if (r['status'] == 'skipped') {
          // 멱등성 체크로 서버가 이미 처리한 것으로 인지 — 로컬 큐에서도 제거
          await queue.remove(r['client_request_id'] as String);
        }
      }
      return success;
    } on DioException {
      return 0;
    }
  }
}
