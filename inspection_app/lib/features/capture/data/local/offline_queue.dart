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
  final String? sector;
  final String? subsector;
  final DateTime capturedAt;

  /// 'defect'(불량/저신뢰) | 'pass'(양품 고신뢰 — 오프라인 단말 종결분)
  final String kind;

  /// 양품 10% 재학습 샘플 대상 여부. true 일 때만 imagePath 가 보관되고 복구 시 S3 업로드됨.
  final bool needsSample;

  const OfflineQueueItem({
    required this.clientRequestId,
    required this.imagePath,
    required this.sessionId,
    required this.processId,
    required this.tankType,
    required this.onDeviceJson,
    this.sector,
    this.subsector,
    required this.capturedAt,
    this.kind = 'defect',
    this.needsSample = false,
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
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE pending_uploads (
            client_request_id TEXT PRIMARY KEY,
            image_path TEXT NOT NULL,
            session_id INTEGER NOT NULL,
            process_id INTEGER NOT NULL,
            tank_type TEXT NOT NULL,
            on_device_json TEXT NOT NULL,
            sector TEXT,
            subsector TEXT,
            captured_at TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'defect',
            needs_sample INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE pending_uploads ADD COLUMN sector TEXT');
          await db.execute('ALTER TABLE pending_uploads ADD COLUMN subsector TEXT');
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE pending_uploads ADD COLUMN kind TEXT NOT NULL DEFAULT 'defect'");
          await db.execute('ALTER TABLE pending_uploads ADD COLUMN needs_sample INTEGER NOT NULL DEFAULT 0');
        }
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
    String? sector,
    String? subsector,
    String kind = 'defect',
    bool needsSample = false,
  }) async {
    final clientId = _uuid.v4();

    // 전수 보관: C-B에서 양품·불량 모두 서버 재추론·이미지 동봉이 필수이므로
    // 큐의 모든 항목은 이미지를 보관한다. (needsSample 은 미사용 — 샘플링은 서버 결정)
    final docs = await getApplicationDocumentsDirectory();
    final queueDir = Directory(p.join(docs.path, 'queue_images'));
    if (!await queueDir.exists()) await queueDir.create(recursive: true);
    final storedPath = p.join(queueDir.path, '$clientId.jpg');
    await imageFile.copy(storedPath);

    final database = await db;
    await database.insert('pending_uploads', {
      'client_request_id': clientId,
      'image_path': storedPath,
      'session_id': sessionId,
      'process_id': processId,
      'tank_type': tankType,
      'on_device_json': onDeviceJson,
      if (sector != null) 'sector': sector,
      if (subsector != null) 'subsector': subsector,
      'captured_at': DateTime.now().toIso8601String(),
      'kind': kind,
      'needs_sample': needsSample ? 1 : 0,
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
          sector: r['sector'] as String?,
          subsector: r['subsector'] as String?,
          capturedAt: DateTime.parse(r['captured_at'] as String),
          kind: (r['kind'] as String?) ?? 'defect',
          needsSample: ((r['needs_sample'] as int?) ?? 0) == 1,
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
    // 비샘플링 양품은 보관 이미지가 없을 수 있음 — exists 체크로 안전 삭제
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'queue_images', '$clientRequestId.jpg');
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
