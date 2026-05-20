import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../providers/result_review_providers.dart';

part 'result_review_notifier.freezed.dart';

@freezed
class ResultReviewState with _$ResultReviewState {
  const factory ResultReviewState({
    @Default(true) bool isLoading,
    @Default(false) bool isEditMode,
    Map<String, dynamic>? raw,
    String? errorMessage,
    String? savedToast,
  }) = _ResultReviewState;
}

final resultReviewNotifierProvider = StateNotifierProvider.family<ResultReviewNotifier, ResultReviewState, int>(
  (ref, imageId) => ResultReviewNotifier(ref, imageId),
);

class ResultReviewNotifier extends StateNotifier<ResultReviewState> {
  final Ref ref;
  final int imageId;
  ResultReviewNotifier(this.ref, this.imageId) : super(const ResultReviewState()) {
    _load();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = await ref.read(resultReviewRemoteProvider).getImageDetail(imageId);
      final hasFeedback = data['feedback'] != null;
      state = state.copyWith(isLoading: false, raw: data, isEditMode: !hasFeedback);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void enableEdit() => state = state.copyWith(isEditMode: true);

  Future<bool> save({
    required int sessionId,
    String? modifiedDefectType,
    required String severity,
    String? opinion,
    required String finalActionContent,
    int? recommendationId,
    String? actionDetail,
  }) async {
    final server = state.raw?['server_result'] as Map<String, dynamic>?;
    final resultId = server?['result_id'] as int?;
    if (resultId == null) {
      state = state.copyWith(errorMessage: '서버 결과가 없어 저장할 수 없습니다.');
      return false;
    }

    try {
      await ref.read(resultReviewRemoteProvider).saveFeedback(
        resultId: resultId,
        sessionId: sessionId,
        modifiedDefectType: modifiedDefectType,
        severity: severity,
        opinion: opinion,
        finalActionContent: finalActionContent,
      );
      if (recommendationId != null && actionDetail != null) {
        await ref.read(resultReviewRemoteProvider).updateRecommendation(recommendationId, actionDetail);
      }
      state = state.copyWith(savedToast: '저장되었습니다.', isEditMode: false);
      await _load();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: '저장 실패: $e');
      return false;
    }
  }
}
