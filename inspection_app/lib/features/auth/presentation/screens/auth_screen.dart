import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../notifiers/login_notifier.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(loginNotifierProvider.notifier).login(
      inspectorId: int.parse(_idCtrl.text.trim()),
      name: _nameCtrl.text.trim(),
      password: _pwCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      context.go(AppRoutes.tankLocation);
    } else {
      final msg = ref.read(loginNotifierProvider).errorMessage ?? '로그인 실패';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  // 상단: 앱 아이콘 + 타이틀 + 부제
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.factory, size: 40, color: AppColors.onPrimaryContainer),
                  ),
                  const SizedBox(height: 24),
                  const Text('Industrial Smart Inspection', style: AppTextStyles.h1, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'LNG 시설 안전 점검 시스템',
                    style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // 검사원 ID
                  TextFormField(
                    controller: _idCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '검사원 ID',
                      hintText: '예: 1',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '검사원 ID를 입력하세요.';
                      if (int.tryParse(v.trim()) == null) return '숫자만 입력 가능합니다.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // 성함
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: '성함'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? '성함을 입력하세요.' : null,
                  ),
                  const SizedBox(height: 16),

                  // 비밀번호
                  TextFormField(
                    controller: _pwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '비밀번호'),
                    validator: (v) => (v == null || v.isEmpty) ? '비밀번호를 입력하세요.' : null,
                  ),
                  const SizedBox(height: 32),

                  // 로그인 버튼
                  ElevatedButton(
                    onPressed: state.isLoading ? null : _submit,
                    child: state.isLoading
                        ? const SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimaryContainer),
                          )
                        : const Text('로그인'),
                  ),
                  const SizedBox(height: 24),

                  // 저작권
                  Text(
                    '© 2026 LNG Safety Solutions Corp.',
                    style: AppTextStyles.caption.copyWith(color: AppColors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
