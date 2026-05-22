import 'dart:async';
import 'dart:convert';

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
      form.files.add(MapEntry(
        'images',
        await MultipartFile.fromFile(it.imagePath, filename: '${it.clientRequestId}.jpg'),
      ));
      metadata.add({
        'client_request_id': it.clientRequestId,
        'session_id': it.sessionId,
        'process_id': it.processId,
        'tank_type': it.tankType,
        'captured_at': it.capturedAt.toIso8601String(),
        'on_device_result': jsonDecode(it.onDeviceJson),
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
        }
      }
      return success;
    } on DioException {
      return 0;
    }
  }
}