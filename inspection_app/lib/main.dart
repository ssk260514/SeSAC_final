import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/router/app_router.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/entities/inspector.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/capture/presentation/providers/capture_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(offlineSyncProvider).start());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'LNG Inspection',
      theme: AppTheme.light(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
