import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../providers/dashboard_providers.dart';

part 'dashboard_notifier.freezed.dart';

@freezed
class DashboardState with _$DashboardState {
  const factory DashboardState({
    @Default(true) bool isLoading,
    DashboardSummary? data,
    String? errorMessage,
  }) = _DashboardState;
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final Ref ref;
  DashboardNotifier(this.ref) : super(const DashboardState()) {
    refresh();
  }

  Future<void> refresh() async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = await ref.read(dashboardRepositoryProvider).getSummary();
      if (!mounted) return; // autoDispose 후 응답이 늦게 도착하면 무시
      state = state.copyWith(isLoading: false, data: data);
    } on Failure catch (f) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: f.message);
    }
  }
}

final dashboardNotifierProvider =
    StateNotifierProvider.autoDispose<DashboardNotifier, DashboardState>(
  (ref) => DashboardNotifier(ref),
);
