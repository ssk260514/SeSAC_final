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
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'queue_images', '$clientRequestId.jpg');
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
