sealed class Failure {
  final String message;
  const Failure(this.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = '서버에 연결할 수 없습니다.']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'ID 또는 비밀번호가 올바르지 않습니다.']);
}

class InactiveAccountFailure extends Failure {
  const InactiveAccountFailure([super.message = '비활성 계정입니다. 관리자에게 문의하세요.']);
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = '서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.']);
}

class ConflictFailure extends Failure {
  final Map<String, dynamic>? data;
  const ConflictFailure(super.message, {this.data});
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = '알 수 없는 오류가 발생했습니다.']);
}

class DailySessionExistsFailure extends Failure {
  final int existingSessionId;
  const DailySessionExistsFailure(this.existingSessionId)
      : super("오늘 이미 진행 중인 세션이 있습니다. '이어서 검사'를 이용해주세요.");
}
