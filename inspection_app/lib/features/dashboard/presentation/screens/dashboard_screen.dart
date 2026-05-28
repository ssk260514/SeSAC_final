import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/storage/token_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../capture/presentation/providers/capture_providers.dart';
import '../../../tank_location/presentation/providers/tank_location_providers.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../notifiers/dashboard_notifier.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardNotifierProvider);
    final inspector = ref.watch(currentInspectorProvider);
    final tankLoc = ref.watch(selectedTankLocationProvider);

    // 진행중 세션이 있으면 currentSessionIdProvider 자동 복원 (앱 재시작 후에도 히스토리 화면이 작동하도록)
    ref.listen(dashboardNotifierProvider, (_, next) {
      final active = next.data?.activeSessionId;
      if (active != null && ref.read(currentSessionIdProvider) != active) {
        ref.read(currentSessionIdProvider.notifier).state = active;
        if (next.data?.activeTankType != null) {
          ref.read(selectedTankLocationProvider.notifier).state = SelectedTankLocation(
            tankType: next.data!.activeTankType,
            sector: next.data!.activeSector,
            subsector: next.data!.activeSubsector,
          );
        }
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person,
                  color: AppColors.onPrimaryContainer, size: 20),
            ),
            const SizedBox(width: 8),
            const Text('LNG Inspection', style: TextStyle(color: Colors.black)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_location_alt_outlined),
            tooltip: '탱크 타입 변경',
            onPressed: () => context.go(AppRoutes.tankLocation, extra: {'fromDashboard': true}),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () async {
              await ref.read(tokenStorageProvider).clear();
              // 인증 상태 초기화 — 미초기화 시 라우터가 '로그인됨'으로 오판해 탱크선택으로 튕김
              ref.read(currentInspectorProvider.notifier).state = null;
              if (!context.mounted) return;
              context.go(AppRoutes.login);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(dashboardNotifierProvider.notifier).refresh(),
        child: state.isLoading && state.data == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 프로필 카드
                  Card(
                    color: AppColors.surfaceContainerLowest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.secondaryContainer,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(Icons.person,
                                color: AppColors.onSecondaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(inspector?.name ?? '-',
                                    style: AppTextStyles.h3),
                                const SizedBox(height: 4),
                                Text(
                                  inspector?.department ?? '-',
                                  style: AppTextStyles.bodyMd.copyWith(
                                      color: AppColors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 현재 검사 위치 (있을 때만)
                  if (tankLoc.tankType != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryFixed,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '탱크 ${tankLoc.tankType} · ${tankLoc.sector} / ${tankLoc.subsector}',
                        style: AppTextStyles.labelBold
                            .copyWith(color: AppColors.onPrimaryContainer),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // 통계 카드 3개
                  if (state.data != null) _StatsRow(data: state.data!),
                  const SizedBox(height: 24),

                  // 검사 시작 버튼 — 진행중 세션 없을 때만 활성화, 클릭 시 세션 생성 + 카메라 이동
                  ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('검사 시작'),
                    onPressed: (state.data == null || state.data!.activeSessionId != null)
                        ? null
                        : () async {
                            if (tankLoc.tankType == null || tankLoc.sector == null || tankLoc.subsector == null) {
                              context.go(AppRoutes.tankLocation);
                              return;
                            }
                            try {
                              final session = await ref.read(tankLocationRepositoryProvider).createSession(
                                tankType: tankLoc.tankType!,
                                selectedSector: tankLoc.sector!,
                                selectedSubsector: tankLoc.subsector!,
                              );
                              if (!context.mounted) return;
                              ref.read(currentSessionIdProvider.notifier).state = session.sessionId;
                              ref.read(currentProcessIdProvider.notifier).state = 1;
                              ref.read(testShotCountProvider.notifier).state = 0; // [테스트 전용] 새 세션 카운트 리셋
                              context.go(AppRoutes.capture);
                            } on DailySessionExistsFailure catch (f) {
                              ref.read(currentSessionIdProvider.notifier).state = f.existingSessionId;
                              ref.read(currentProcessIdProvider.notifier).state = 1;
                              ref.read(testShotCountProvider.notifier).state = 0; // [테스트 전용] 새 세션 카운트 리셋
                              if (!context.mounted) return;
                              context.go(AppRoutes.capture);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
                              );
                            }
                          },
                  ),
                  const SizedBox(height: 24),

                  // 최근 세션 이력
                  const Text('최근 세션 이력', style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  if (state.data == null || state.data!.recentSessions.isEmpty)
                    const _EmptyRecent()
                  else
                    ...state.data!.recentSessions
                        .map((s) => _RecentSessionTile(s)),

                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(state.errorMessage!,
                        style:
                            const TextStyle(color: AppColors.error)),
                  ],
                ],
              ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final DashboardSummary data;
  const _StatsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(label: '세션 번호', value: '#${data.sessionNumber}'),
        const SizedBox(width: 8),
        _StatCard(label: '총 이미지', value: '${data.todayImages}장'),
        const SizedBox(width: 8),
        _StatCard(
            label: '양품률',
            value: '${data.todayPassRate.toStringAsFixed(1)}%'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value, style: AppTextStyles.h2),
          ],
        ),
      ),
    );
  }
}

class _RecentSessionTile extends StatelessWidget {
  final SessionSummary s;
  const _RecentSessionTile(this.s);

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy.MM.dd HH:mm');
    final successContainer = context.semanticColors.successContainer;
    final onSuccessContainer = context.semanticColors.onSuccessContainer;

    return Card(
      color: AppColors.surfaceContainerLowest,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              s.hasDefect ? AppColors.errorContainer : successContainer,
          child: Icon(
            s.hasDefect ? Icons.warning : Icons.check_circle,
            color: s.hasDefect ? AppColors.error : onSuccessContainer,
          ),
        ),
        title: Text('탱크 ${s.tankType}', style: AppTextStyles.h3),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('검사 시작: ${fmt.format(s.startedAt)}',
                style: AppTextStyles.bodyMd),
            if (s.endedAt != null)
              Text('검사 종료: ${fmt.format(s.endedAt!)}',
                  style: AppTextStyles.bodyMd),
            if (s.lastModifiedAt != null)
              Text('최종 수정: ${fmt.format(s.lastModifiedAt!)}',
                  style: AppTextStyles.bodyMd),
          ],
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.history,
              size: 48, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            '완료된 세션이 아직 없습니다',
            style: AppTextStyles.bodyLg
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            "'검사 시작'을 눌러 첫 검사를 시작하세요",
            style: AppTextStyles.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
