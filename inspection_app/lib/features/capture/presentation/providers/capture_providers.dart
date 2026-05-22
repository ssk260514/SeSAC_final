import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/datasources/capture_remote_data_source.dart';
import '../../data/local/tflite_inference_service.dart';
import '../../data/local/offline_queue.dart';
import '../../data/local/offline_sync_service.dart';
import '../../data/repositories/capture_repository_impl.dart';
import '../../domain/repositories/capture_repository.dart';

final tfliteServiceProvider = Provider<TfliteInferenceService>((ref) {
  final s = TfliteInferenceService();
  ref.onDispose(() => s.dispose());
  return s;
});

final offlineQueueProvider = Provider<OfflineQueueDb>((_) => OfflineQueueDb());

final offlineSyncProvider = Provider<OfflineSyncService>((ref) {
  final svc = OfflineSyncService(
    queue: ref.watch(offlineQueueProvider),
    dio: ref.watch(dioProvider),
  );
  ref.onDispose(svc.stop);
  return svc;
});

final captureRemoteProvider = Provider((ref) => CaptureRemoteDataSource(ref.watch(dioProvider)));
final captureRepositoryProvider = Provider<CaptureRepository>(
  (ref) => CaptureRepositoryImpl(
    remote: ref.watch(captureRemoteProvider),
    tflite: ref.watch(tfliteServiceProvider),
    queue: ref.watch(offlineQueueProvider),
    dio: ref.watch(dioProvider),
  ),
);

/// 현재 세션 ID — 카메라 진입 시 외부에서 set
final currentSessionIdProvider = StateProvider<int?>((_) => null);

/// 현재 공정 ID
final currentProcessIdProvider = StateProvider<int?>((_) => null);

/// 백그라운드 업로드 큐 카운터 (UI 표시용)
final pendingUploadsProvider = StateProvider<int>((_) => 0);
final completedCapturesProvider = StateProvider<int>((_) => 0);

/// 업로드 실패 메시지 — 화면 이탈 후 실패해도 이력 화면에서 SnackBar 표시 가능
final uploadFailureProvider = StateProvider<String?>((_) => null);
