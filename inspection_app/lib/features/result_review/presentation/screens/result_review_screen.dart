import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../notifiers/result_review_notifier.dart';

class ResultReviewScreen extends ConsumerWidget {
  const ResultReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageId = int.tryParse(GoRouterState.of(context).uri.queryParameters['imageId'] ?? '');
    if (imageId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('결과 처리')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.assignment, size: 48, color: AppColors.onSurfaceVariant),
              const SizedBox(height: 8),
              const Text('선택된 검사 결과가 없습니다', style: AppTextStyles.h3),
              const SizedBox(height: 4),
              Text('검사 이력에서 항목을 선택해 결과를 처리하세요',
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextButton(onPressed: () => context.go(AppRoutes.history), child: const Text('검사 이력 보기')),
            ],
          ),
        ),
      );
    }
    return _ResultReviewBody(imageId: imageId);
  }
}


class _ResultReviewBody extends ConsumerStatefulWidget {
  final int imageId;
  const _ResultReviewBody({required this.imageId});

  @override
  ConsumerState<_ResultReviewBody> createState() => _ResultReviewBodyState();
}

class _ResultReviewBodyState extends ConsumerState<_ResultReviewBody> {
  String? _defectType;
  String? _severity;
  late final TextEditingController _actionDetailCtrl;
  late final TextEditingController _opinionCtrl;
  bool _initialized = false;

  static const _severities = ['경미', '보통', '심각'];

  @override
  void initState() {
    super.initState();
    _actionDetailCtrl = TextEditingController();
    _opinionCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _actionDetailCtrl.dispose();
    _opinionCtrl.dispose();
    super.dispose();
  }

  void _initFromState(ResultReviewState state) {
    if (_initialized || state.raw == null) return;
    // 서버 분석분은 server_result, 단말 자동종결분은 device_result 로 폴백 (대표 행)
    final server = state.raw!['server_result'] as Map<String, dynamic>?;
    final device = state.raw!['device_result'] as Map<String, dynamic>?;
    final primary = server ?? device;
    final action = state.raw!['action_guide'] as Map<String, dynamic>?;
    final feedback = state.raw!['feedback'] as Map<String, dynamic>?;

    _defectType = feedback?['modified_defect_type']?.toString() ?? primary?['defect_type']?.toString();
    _severity = feedback?['severity']?.toString();
    _actionDetailCtrl.text = feedback?['final_action_content']?.toString() ?? action?['detail']?.toString() ?? '';
    _opinionCtrl.text = feedback?['opinion']?.toString() ?? '';
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(resultReviewNotifierProvider(widget.imageId));
    final notifier = ref.read(resultReviewNotifierProvider(widget.imageId).notifier);

    if (!state.isLoading) _initFromState(state);

    final server = state.raw?['server_result'] as Map<String, dynamic>?;
    final device = state.raw?['device_result'] as Map<String, dynamic>?;
    final primary = server ?? device;          // 서버 분석분 우선, 없으면 단말 결과
    final action = state.raw?['action_guide'] as Map<String, dynamic>?;
    final feedback = state.raw?['feedback'] as Map<String, dynamic>?;
    final isEdit = state.isEditMode;
    final top3 = (primary?['top3_predictions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    const defectChoices = [
      // 용접 (0~2)
      '용접불량-조인트', '용접블로우홀-조인트', '용접양품-조인트',
      // 절단 (3~6)
      '절단불량-모재', '절단불량-보온재', '절단양품-모재', '절단양품-보온재',
      // 케이블 (7~12)
      '바인딩불량-케이블타이', '바인딩양품-케이블타이',
      '케이블설치불량-케이블그랜드', '케이블설치양품-케이블그랜드',
      '케이블손상-케이블', '케이블양품-케이블',
      // 파이프 (13~14)
      '볼트체결불량-파이프', '볼트체결양품-파이프',
      // 폼스프레이 (15~16)
      '폼스프레이불량-우레탄폼', '폼스프레이양품-우레탄폼',
      // 표면처리 (17~29)
      '균열-도장', '균열-보온재', '도막떨어짐-도장', '도막분리-도장', '도장흐름-도장',
      '보온재손상-보온재', '스크래치-도장', '스크래치-모재', '스크래치-보온재', '탱크클리닝불량-모재',
      '표면양품-도장', '표면양품-모재', '표면양품-보온재',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('결과 처리'),
        actions: [
          if (feedback != null && !isEdit)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: const Text('확정 저장됨'),
                backgroundColor: context.semanticColors.successContainer,
                labelStyle: TextStyle(color: context.semanticColors.onSuccessContainer, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 검사 요약 카드
                Card(
                  color: AppColors.surfaceContainerLowest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.image),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('AI 판정: ${primary?['defect_type'] ?? '-'}', style: AppTextStyles.h3),
                              const SizedBox(height: 4),
                              Text('신뢰도: ${((primary?['confidence'] ?? 0) * 100).toStringAsFixed(1)}%',
                                  style: AppTextStyles.codeData),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 추론 결과 (Top-3) — 모달과 동일한 단말/서버 추론 상위 3개
                if (top3.isNotEmpty) ...[
                  Text('추론 결과 (Top-3 Predictions)', style: AppTextStyles.labelBold),
                  const SizedBox(height: 8),
                  ...top3.asMap().entries.map((e) {
                    final rank = e.key + 1;
                    final conf = ((e.value['confidence'] as num?)?.toDouble()) ?? 0;
                    final isTop = rank == 1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.value['class']?.toString() ?? '-',
                                  style: isTop ? AppTextStyles.labelBold : AppTextStyles.bodyMd),
                              Text('${(conf * 100).toStringAsFixed(1)}%', style: AppTextStyles.codeData),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: conf.toDouble().clamp(0.0, 1.0),
                              minHeight: isTop ? 12 : 10,
                              backgroundColor: AppColors.outlineVariant,
                              color: isTop ? AppColors.primaryContainer : AppColors.outline,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],

                // 결함 유형 판정
                Text('결함 유형 판정 (Defect Type)', style: AppTextStyles.labelBold),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _defectType,
                  decoration: const InputDecoration(),
                  items: defectChoices.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: isEdit ? (v) => setState(() => _defectType = v) : null,
                ),
                const SizedBox(height: 16),

                // 심각도
                Text('심각도 판정 (Severity Level)', style: AppTextStyles.labelBold),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _severity,
                  decoration: const InputDecoration(hintText: '심각도를 선택하세요'),
                  items: _severities.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: isEdit ? (v) => setState(() => _severity = v) : null,
                ),
                const SizedBox(height: 16),

                // 매뉴얼 기반 조치 가이드 (읽기 전용)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryContainer),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.smart_toy, color: AppColors.onPrimaryContainer, size: 20),
                          const SizedBox(width: 8),
                          Text('매뉴얼 기반 조치 가이드', style: AppTextStyles.labelBold),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(action?['summary']?.toString() ?? '-', style: AppTextStyles.bodyMd),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 조치 내용 수정
                Text('조치 내용 수정', style: AppTextStyles.labelBold),
                const SizedBox(height: 8),
                TextField(
                  controller: _actionDetailCtrl,
                  enabled: isEdit,
                  maxLines: 6,
                  decoration: const InputDecoration(),
                ),
                const SizedBox(height: 16),

                // 의견/메모
                Text('의견/메모', style: AppTextStyles.labelBold),
                const SizedBox(height: 8),
                TextField(
                  controller: _opinionCtrl,
                  enabled: isEdit,
                  maxLines: 3,
                  decoration: const InputDecoration(),
                ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: feedback != null && !isEdit ? () => notifier.enableEdit() : null,
                        child: const Text('수정'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isEdit && _defectType != null && _severity != null && _actionDetailCtrl.text.trim().isNotEmpty
                            ? () async {
                                final sessionId = ref.read(currentSessionIdProvider) ?? 0;
                                final ok = await notifier.save(
                                  sessionId: sessionId,
                                  modifiedDefectType: _defectType,
                                  severity: _severity!,
                                  opinion: _opinionCtrl.text,
                                  finalActionContent: _actionDetailCtrl.text,
                                  recommendationId: action?['recommendation_id'] as int?,
                                  actionDetail: _actionDetailCtrl.text,
                                );
                                if (!context.mounted) return;
                                if (ok) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('저장되었습니다.')),
                                  );
                                  context.go(AppRoutes.history);
                                }
                              }
                            : null,
                        child: const Text('저장'),
                      ),
                    ),
                  ],
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(state.errorMessage!, style: const TextStyle(color: AppColors.error)),
                ],
              ],
            ),
    );
  }
}
