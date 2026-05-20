import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/datasources/settings_remote_data_source.dart';

part 'settings_notifier.freezed.dart';

@freezed
class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(true) bool isLoading,
    @Default(true) bool pushNotification,
    @Default('ko') String language,
    @Default('-') String appVersion,
    String? errorMessage,
  }) = _SettingsState;
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final Ref ref;
  SettingsNotifier(this.ref) : super(const SettingsState()) {
    _load();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);

    // 앱 버전은 API 성공 여부와 무관하게 항상 표시
    final pkg = await PackageInfo.fromPlatform();
    state = state.copyWith(appVersion: 'v${pkg.version}');

    try {
      final ds = SettingsRemoteDataSource(ref.read(dioProvider));
      final data = await ds.get();
      state = state.copyWith(
        isLoading: false,
        pushNotification: data['push_notification'] ?? true,
        language: data['language'] ?? 'ko',
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> setPush(bool v) async {
    state = state.copyWith(pushNotification: v);
    await SettingsRemoteDataSource(ref.read(dioProvider))
        .patch(push: v, language: state.language);
  }

  Future<void> setLanguage(String v) async {
    state = state.copyWith(language: v);
    await SettingsRemoteDataSource(ref.read(dioProvider))
        .patch(push: state.pushNotification, language: v);
  }
}

final settingsNotifierProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(ref),
);
