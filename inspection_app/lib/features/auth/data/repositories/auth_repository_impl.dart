import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/storage/token_storage.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/login_request_dto.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remote;
  final TokenStorage tokenStorage;

  AuthRepositoryImpl({required this.remote, required this.tokenStorage});

  @override
  Future<LoginResult> login({
    required int inspectorId,
    required String name,
    required String password,
  }) async {
    try {
      final dto = await remote.login(LoginRequestDto(
        inspector_id: inspectorId,
        name: name,
        password: password,
      ));
      final result = dto.toResult();
      await tokenStorage.saveTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        inspectorId: result.inspector.inspectorId,
      );
      return result;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await remote.logout();
    } catch (_) {
      // best-effort: 서버 실패해도 로컬 토큰은 지움
    } finally {
      await tokenStorage.clear();
    }
  }

  Failure _mapError(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final Map? detail = data is Map ? data['detail'] as Map? : null;
    final errorCode = detail?['error'];

    if (status == 401 && errorCode == 'AUTH_FAILED') {
      return const AuthFailure();
    }
    if (status == 403 && errorCode == 'INACTIVE_ACCOUNT') {
      return const InactiveAccountFailure();
    }
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure();
    }
    if (status != null && status >= 500) {
      return const ServerFailure();
    }
    return const UnknownFailure();
  }
}
