import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/router/app_router.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/entities/inspector.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/capture/presentation/providers/capture_providers.dart';
import 'features/capture/data/local/model_ota_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 모델 OTA는 S3 presigned URL로 전환됨 — Firebase 초기화 불필요.

  // 앱 시작 전 SecureStorage에서 inspector 복구 시도
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final tokenStorage = TokenStorage(storage);
  Inspector? initialInspector;

  final token = await tokenStorage.getAccessToken();
  if (token != null) {
    final id   = await tokenStorage.getInspectorId();
    final name = await tokenStorage.getInspectorName();
    final dept = await tokenStorage.getInspectorDepartment();
    if (id != null && name != null) {
      initialInspector = Inspector(inspectorId: id, name: name, department: dept);
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        if (initialInspector != null)
          currentInspectorProvider.overrideWith((ref) => initialInspector!),
      ],
      child: const InspectionApp(),
    ),
  );
}

class InspectionApp extends ConsumerStatefulWidget {
  const InspectionApp({super.key});

  @override
  ConsumerState<InspectionApp> createState() => _InspectionAppState();
}

class _InspectionAppState extends ConsumerState<InspectionApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.read(offlineSyncProvider).start();
      try {
        final updated = await ref.read(modelOtaServiceProvider).checkAndDownload();
        if (updated && mounted) {
          _scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('새 AI 모델이 준비되었습니다. 다음 앱 시작 시 적용됩니다.')),
          );
        }
      } catch (_) {
        // 모델 OTA 실패는 앱 동작에 영향 없음 — 기존 모델 유지 (안전 우선)
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'LNG Inspection',
      theme: AppTheme.light(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
