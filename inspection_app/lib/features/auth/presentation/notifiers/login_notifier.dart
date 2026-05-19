import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/inspector.dart';
import '../providers/auth_providers.dart';

part 'login_notifier.freezed.dart';

@freezed
class LoginState with _$LoginState {
  const factory LoginState({
    @Default(false) bool isLoading,
    String? errorMessage,
    Inspector? inspector,
  }) = _LoginState;
}

class LoginNotifier extends StateNotifier<LoginState> {
  final Ref ref;
  LoginNotifier(this.ref) : super(const LoginState());

  Future<bool> login({
    required int inspectorId,
    required String name,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final result = await ref.read(loginUseCaseProvider).execute(
            inspectorId: inspectorId,
            name: name,
            password: password,
          );
      state = state.copyWith(isLoading: false, inspector: result.inspector);
      ref.read(currentInspectorProvider.notifier).state = result.inspector;
      return true;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: '알 수 없는 오류가 발생했습니다.');
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

final loginNotifierProvider = StateNotifierProvider<LoginNotifier, LoginState>(
  (ref) => LoginNotifier(ref),
);
