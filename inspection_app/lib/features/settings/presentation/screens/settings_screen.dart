import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/storage/token_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../auth/data/datasources/auth_remote_data_source.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../notifiers/settings_notifier.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final inspector = ref.watch(currentInspectorProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 프로필 카드
                Card(
                  color: AppColors.surfaceContainerLowest,
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.secondaryContainer,
                      child: Icon(Icons.person, color: AppColors.onSecondaryContainer),
                    ),
                    title: Text(inspector?.name ?? '-', style: AppTextStyles.h3),
                    subtitle: Text(
                      inspector?.department ?? '-',
                      style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 앱 설정 섹션
                const Text('앱 설정', style: AppTextStyles.h3),
                const SizedBox(height: 8),
                Card(
                  color: AppColors.surfaceContainerLowest,
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_outlined),
                        title: const Text('푸시 알림'),
                        value: state.pushNotification,
                        onChanged: notifier.setPush,
                      ),
                      const Divider(height: 1, color: AppColors.outlineVariant),
                      ListTile(
                        leading: const Icon(Icons.language),
                        title: const Text('언어 설정'),
                        trailing: DropdownButton<String>(
                          value: state.language,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 'ko', child: Text('한국어')),
                            DropdownMenuItem(value: 'en', child: Text('English')),
                          ],
                          onChanged: (v) {
                            if (v != null) notifier.setLanguage(v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 시스템 정보
                const Text('시스템 정보', style: AppTextStyles.h3),
                const SizedBox(height: 8),
                Card(
                  color: AppColors.surfaceContainerLowest,
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('앱 버전'),
                        trailing: Text(state.appVersion, style: AppTextStyles.codeData),
                      ),
                      const Divider(height: 1, color: AppColors.outlineVariant),
                      ListTile(
                        title: const Text('이용약관 및 개인정보처리방침'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // Post-MVP: url_launcher로 연결
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 로그아웃
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('로그아웃'),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('로그아웃'),
                        content: const Text('정말 로그아웃하시겠습니까?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('취소'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('로그아웃'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    try {
                      await AuthRemoteDataSource(ref.read(dioProvider)).logout();
                    } catch (_) {}
                    ref.read(currentInspectorProvider.notifier).state = null;
                    await ref.read(tokenStorageProvider).clear();
                    if (!context.mounted) return;
                    context.go(AppRoutes.login);
                  },
                ),
              ],
            ),
    );
  }
}
