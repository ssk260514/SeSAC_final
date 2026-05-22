import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspection_app/core/storage/token_storage.dart';
import 'package:inspection_app/main.dart';

// 테스트용 가짜 TokenStorage (플랫폼 채널 불필요)
class _FakeTokenStorage extends Fake implements TokenStorage {
  @override
  Future<String?> getAccessToken() async => null;
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<int?> getInspectorId() async => null;
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int inspectorId,
    required String inspectorName,
    String? inspectorDepartment,
  }) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('앱 시작 시 로그인 화면이 표시된다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
        ],
        child: const InspectionApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 로그인 화면 핵심 요소 확인
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('검사원 ID'), findsOneWidget);
  });
}
