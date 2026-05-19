import '../entities/inspector.dart';

class LoginResult {
  final String accessToken;
  final String refreshToken;
  final Inspector inspector;
  const LoginResult({required this.accessToken, required this.refreshToken, required this.inspector});
}

abstract class AuthRepository {
  Future<LoginResult> login({
    required int inspectorId,
    required String name,
    required String password,
  });

  Future<void> logout();
}
