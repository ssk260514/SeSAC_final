import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../tank_location/presentation/providers/tank_location_providers.dart';
import '../providers/capture_providers.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  CameraController? _ctrl;
  Future<void>? _initFuture;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  Future<void> _init() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _permissionDenied = true);
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final rear = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _ctrl = CameraController(rear, ResolutionPreset.high, enableAudio: false);
    await _ctrl!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized || _ctrl!.value.isTakingPicture) return;

    // await 이전에 모든 상태 캡처 — 촬영 중 화면 이탈 시에도 업로드가 진행되도록
    final sid = ref.read(currentSessionIdProvider);
    final pid = ref.read(currentProcessIdProvider);
    final tankLoc = ref.read(selectedTankLocationProvider);
    if (sid == null || pid == null || tankLoc.tankType == null) {
      _showError('세션 정보가 없습니다. 대시보드로 돌아가 검사 시작을 다시 눌러주세요.');
      return;
    }
    final repo = ref.read(captureRepositoryProvider);
    final container = ProviderScope.containerOf(context);

    final xfile = await _ctrl!.takePicture();
    final file = File(xfile.path);

    container.read(pendingUploadsProvider.notifier).update((s) => s + 1);

    Future(() async {
      try {
        await repo.uploadAndInspect(
          imageFile: file,
          sessionId: sid,
          processId: pid,
          tankType: tankLoc.tankType!,
          sector: tankLoc.sector,
          subsector: tankLoc.subsector,
        );
        container.read(completedCapturesProvider.notifier).update((s) => s + 1);
      } catch (e) {
        // 실패해도 증가시켜 검사이력 갱신을 트리거하고 오류를 알림
        container.read(completedCapturesProvider.notifier).update((s) => s + 1);
        container.read(uploadFailureProvider.notifier).state = e.toString();
        debugPrint('업로드 실패: $e');
      } finally {
        container.read(pendingUploadsProvider.notifier).update((s) => (s - 1).clamp(0, 1 << 30));
      }
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography, size: 64, color: AppColors.onSurfaceVariant),
                const SizedBox(height: 16),
                Text('카메라 권한이 필요합니다', style: AppTextStyles.h2),
                const SizedBox(height: 8),
                Text(
                  '설정에서 카메라 권한을 허용한 후 다시 시도해주세요.',
                  style: AppTextStyles.bodyMd,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: openAppSettings, child: const Text('설정 열기')),
                TextButton(
                  onPressed: () => context.go(AppRoutes.dashboard),
                  child: const Text('대시보드로'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    ref.listen(uploadFailureProvider, (_, msg) {
      if (msg != null) {
        _showError('업로드 실패: $msg');
        ref.read(uploadFailureProvider.notifier).state = null;
      }
    });

    final tankLoc = ref.watch(selectedTankLocationProvider);
    final pending = ref.watch(pendingUploadsProvider);
    final completed = ref.watch(completedCapturesProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snap) {
          if (_ctrl == null || !(_ctrl!.value.isInitialized)) {
            return const Center(child: CircularProgressIndicator());
          }
          return Stack(
            children: [
              Positioned.fill(child: CameraPreview(_ctrl!)),

              // 상단 정보 (탱크 + 위치)
              Positioned(
                top: 50, left: 16, right: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '탱크 ${tankLoc.tankType ?? "-"} · ${tankLoc.sector ?? "-"} / ${tankLoc.subsector ?? "-"}',
                        style: AppTextStyles.labelBold.copyWith(color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    if (pending > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '업로드중 $pending',
                          style: AppTextStyles.labelBold.copyWith(color: AppColors.onPrimaryContainer),
                        ),
                      ),
                  ],
                ),
              ),

              // 중앙 가이드 박스
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 240, height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.primaryContainer.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              // 하단 컨트롤
              Positioned(
                left: 0, right: 0, bottom: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 검사 이력 썸네일
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.history),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                '$completed',
                                style: AppTextStyles.h3.copyWith(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('검사 이력', style: AppTextStyles.caption.copyWith(color: Colors.white)),
                        ],
                      ),
                    ),

                    // 셔터 버튼
                    GestureDetector(
                      onTap: _shoot,
                      child: Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: AppColors.primaryContainer,
                        ),
                      ),
                    ),

                    const SizedBox(width: 56, height: 56),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
