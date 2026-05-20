import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/dio_client.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../data/datasources/inspection_history_remote_data_source.dart';
import '../../domain/entities/result_card.dart';

part 'inspection_history_notifier.freezed.dart';

enum FilterType { all, completed, incomplete }

@freezed
class InspectionHistoryState with _$InspectionHistoryState {
  const factory InspectionHistoryState({
    @Default(FilterType.all) FilterType filter,
    @Default(false) bool isLoading,
    @Default([]) List<ResultCard> cards,
    String? errorMessage,
  }) = _InspectionHistoryState;
}

final inspectionHistoryNotifierProvider =
    StateNotifierProvider.autoDispose.family<InspectionHistoryNotifier, InspectionHistoryState, int>(
  (ref, sessionId) => InspectionHistoryNotifier(ref, sessionId),
);

class InspectionHistoryNotifier extends StateNotifier<InspectionHistoryState> {
  final Ref ref;
  final int sessionId;
  InspectionHistoryNotifier(this.ref, this.sessionId) : super(const InspectionHistoryState()) {
    refresh();
    ref.listen(completedCapturesProvider, (prev, next) {
      if (next > (prev ?? 0)) refresh();
    });
  }

  void setFilter(FilterType f) {
    state = state.copyWith(filter: f);
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final ds = InspectionHistoryRemoteDataSource(ref.read(dioProvider));
      final statusParam = switch (state.filter) {
        FilterType.all => 'all',
        FilterType.completed => '완료',
        FilterType.incomplete => '미완료',
      };
      debugPrint('[History] refresh() sessionId=$sessionId status=$statusParam');
      final dtos = await ds.listResults(sessionId, statusParam);
      debugPrint('[History] refresh() cards=${dtos.length}');
      state = state.copyWith(isLoading: false, cards: dtos.map((d) => d.toEntity()).toList());
    } catch (e, st) {
      debugPrint('[History] refresh() ERROR: $e\n$st');
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> endSession() async {
    try {
      await InspectionHistoryRemoteDataSource(ref.read(dioProvider)).endSession(sessionId);
      return true;
    } on Failure catch (f) {
      state = state.copyWith(errorMessage: f.message);
      return false;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }
}
