import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';

/// 백엔드 베이스 URL
/// - 에뮬레이터: http://10.0.2.2:8000/api
/// - 실기기: PC의 Wi-Fi LAN IP
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api',
);

/// 토큰 자동 첨부 + 401 자동 갱신 인터셉터
class AuthInterceptor extends QueuedInterceptor {
  final TokenStorage tokenStorage;
  final Dio refreshDio;
  final void Function() onUnauthorized;

  AuthInterceptor({
    required this.tokenStorage,
    required this.refreshDio,
    required this.onUnauthorized,
  });

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (!options.path.endsWith('/auth/login') &&
        !options.path.endsWith('/auth/refresh')) {
      final token = await tokenStorage.getAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final refresh = await tokenStorage.getRefreshToken();
      if (refresh == null) {
        onUnauthorized();
        return handler.next(err);
      }
      try {
        final res = await refreshDio.post(
          '$kApiBaseUrl/auth/refresh',
          data: {'refresh_token': refresh},
        );
        final newAccess = res.data['access_token'] as String;
        final refreshOld = await tokenStorage.getRefreshToken();
        final inspectorId = await tokenStorage.getInspectorId();
        final inspectorName = await tokenStorage.getInspectorName();
        if (refreshOld != null && inspectorId != null && inspectorName != null) {
          await tokenStorage.saveTokens(
            accessToken: newAccess,
            refreshToken: refreshOld,
            inspectorId: inspectorId,
            inspectorName: inspectorName,
          );
        }

        final retryOpts = err.requestOptions;
        retryOpts.headers['Authorization'] = 'Bearer $newAccess';
        final retryRes = await refreshDio.fetch(retryOpts);
        return handler.resolve(retryRes);
      } catch (_) {
        onUnauthorized();
        return handler.next(err);
      }
    }
    handler.next(err);
  }
}

final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);

  final dio = Dio(BaseOptions(
    baseUrl: kApiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'Content-Type': 'application/json'},
  ));

  final refreshDio = Dio(BaseOptions(baseUrl: kApiBaseUrl));

  dio.interceptors.add(AuthInterceptor(
    tokenStorage: tokenStorage,
    refreshDio: refreshDio,
    onUnauthorized: () {
      tokenStorage.clear();
      // 인증 상태도 초기화해야 라우터(refreshListenable)가 로그인으로 리다이렉트한다.
      // 이게 없으면 토큰 만료 후에도 라우터가 "로그인됨"으로 착각해 빈 화면에 고착된다.
      ref.read(currentInspectorProvider.notifier).state = null;
    },
  ));

  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
    request: true,
    requestHeader: false,
    responseHeader: false,
    error: true,
  ));

  return dio;
});
