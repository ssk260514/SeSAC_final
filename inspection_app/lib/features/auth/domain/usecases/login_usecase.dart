import '../repositories/auth_repository.dart';

class LoginUseCase {
  final AuthRepository repo;
  LoginUseCase(this.repo);

  Future<LoginResult> execute({
    required int inspectorId,
    required String name,
    required String password,
  }) {
    return repo.login(inspectorId: inspectorId, name: name, password: password);
  }
}
