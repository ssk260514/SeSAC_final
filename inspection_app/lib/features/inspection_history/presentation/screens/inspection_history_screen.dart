import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../domain/entities/result_card.dart';
import '../notifiers/inspection_history_notifier.dart';
import '../widgets/detail_modal.dart';

class InspectionHistoryScreen extends ConsumerWidget {
  const InspectionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // watch로 현재 값도 즉시 감지 — listen만 쓰면 화면 진입 전 실패를 놓침
    final uploadFailure = ref.watch(uploadFailureProvider);
    if (uploadFailure != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('업로드 실패: $uploadFailure'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        ref.read(uploadFailureProvider.notifier).state = null;
      });
    }

    final sessionId = ref.watch(currentSessionIdProvider);
    if (sessionId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('검사 이력')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_camera, size: 48, color: AppColors.onSurfaceVariant),
              const SizedBox(height: 8),
              Text('진행 중인 세션이 없습니다', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: () => context.go(AppRoutes.dashboard), child: const Text('대시보드로')),
            ],
          ),
        ),
      );
    }

    final state = ref.watch(inspectionHistoryNotifierProvider(sessionId));
    final notifier = ref.read(inspectionHistoryNotifierProvider(sessionId).notifier);
    final canEndSession = state.cards.where((c) => c.resultStatus == '미완료').isEmpty && state.cards.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('검사 이력')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<FilterType>(
              segments: const [
                ButtonSegment(value: FilterType.all, label: Text('전체')),
                ButtonSegment(value: FilterType.completed, label: Text('검사 완료')),
                ButtonSegment(value: FilterType.incomplete, label: Text('검사 미완료')),
              ],
              selected: {state.filter},
              onSelectionChanged: (s) => notifier.setFilter(s.first),
            ),
          ),

          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '오류: ${state.errorMessage}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),

          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.cards.isEmpty
                    ? _emptyStateContent(state.filter)
                    : RefreshIndicator(
                        onRefresh: notifier.refresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: state.cards.length,
                          itemBuilder: (_, i) => _Card(card: state.cards[i], onTap: () => _onCardTap(context, state.cards[i])),
                        ),
                      ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('이어서 검사'),
                  onPressed: () {
                    ref.read(currentProcessIdProvider.notifier).state = 1;
                    context.go(AppRoutes.capture);
                  },
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('세션 완료'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canEndSession ? AppColors.primary : AppColors.outline,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: !canEndSession ? null : () async {
                    final ok = await notifier.endSession();
                    if (!context.mounted) return;
                    if (ok) {
                      ref.read(currentSessionIdProvider.notifier).state = null;
                      context.go(AppRoutes.dashboard);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ref.read(inspectionHistoryNotifierProvider(sessionId)).errorMessage ?? '실패')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onCardTap(BuildContext context, ResultCard card) {
    // 모든 카드는 먼저 분석 결과 모달을 보여준다.
    //   - 서버 정밀분석 완료/미완료: 서버 결과 + 매뉴얼 기반 조치 가이드 + "결과 처리" 버튼(→ /result)
    //   - 단말 자동 종결(양품·오프라인): 단말 결과 + "닫기" 버튼
    // 모달 내부에서 hasServer 여부로 표시·버튼을 분기한다.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DetailModal(imageId: card.imageId),
    );
  }

  Widget _emptyStateContent(FilterType f) {
    final (icon, title, sub) = switch (f) {
      FilterType.all => (Icons.photo_camera, '아직 촬영한 이미지가 없습니다', "'이어서 검사'를 눌러 촬영을 시작하세요"),
      FilterType.completed => (Icons.assignment_turned_in, '완료된 검사 결과가 없습니다', '결과 처리가 끝난 항목이 여기에 표시됩니다'),
      FilterType.incomplete => (Icons.check_circle, '미완료 검사 결과가 없습니다', '모든 결과가 처리되었습니다'),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(title, style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text(sub, style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}


class _Card extends StatelessWidget {
  final ResultCard card;
  final VoidCallback onTap;
  const _Card({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm');
    final barColor = card.resultStatus == '미완료'
        ? AppColors.outline
        : (card.isDefect ? AppColors.error : const Color(0xFF2E7D32));
    final tagText = card.resultStatus == '미완료' ? '검사 미완료' : '검사 완료';
    final tagColor = card.resultStatus == '미완료' ? AppColors.outline : AppColors.primary;
    final verdictText = card.resultStatus == '미완료' ? '판정 대기' : (card.isDefect ? '불량품 (Fail)' : '양품 (Pass)');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: barColor),
                const SizedBox(width: 12),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(verdictText, style: AppTextStyles.h3),
                            Text(fmt.format(card.capturedAt), style: AppTextStyles.caption),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          card.resultStatus == '미완료' && !card.hasServerResult ? '분석 대기 중' : card.defectType,
                          style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(tagText, style: AppTextStyles.labelBold.copyWith(color: tagColor)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
