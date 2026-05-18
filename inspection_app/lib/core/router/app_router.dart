import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/tank_location/presentation/screens/tank_location_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/inspection_history/presentation/screens/inspection_history_screen.dart';
import '../../features/capture/presentation/screens/capture_screen.dart';
import '../../features/result_review/presentation/screens/result_review_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import 'app_shell.dart';

class AppRoutes {
  static const login = '/login';
  static const tankLocation = '/tank-location';
  static const dashboard = '/dashboard';
  static const history = '/history';
  static const capture = '/capture';
  static const result = '/result';
  static const settings = '/settings';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.tankLocation,
        builder: (context, state) => const TankLocationScreen(),
      ),
      GoRoute(
        path: AppRoutes.capture,
        builder: (context, state) => const CaptureScreen(),
      ),

      // Bottom Nav 4탭을 공유하는 ShellRoute
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: AppRoutes.history,
            builder: (context, state) => const InspectionHistoryScreen(),
          ),
          GoRoute(
            path: AppRoutes.result,
            builder: (context, state) => const ResultReviewScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],

    // 추후 인증 가드를 여기에 추가 (06번 단계)
    // redirect: (context, state) { ... }
  );
});
