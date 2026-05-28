import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/dio_client.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/datasources/inspection_history_remote_data_source.dart';

class DetailModal extends ConsumerStatefulWidget {
  final int imageId;
  const DetailModal({super.key, required this.imageId});

  @override
  ConsumerState<DetailModal> createState() => _DetailModalState();
}

class _DetailModalState extends ConsumerState<DetailModal> {
  Map<String, dynamic>? _data;
  bool _gradcamOn = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await InspectionHistoryRemoteDataSource(ref.read(dioProvider)).getImageDetail(widget.imageId);
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                const Text('정밀 분석 결과', style: AppTextStyles.h1),
                const Spacer(),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
          else if (_data == null)
            const Padding(padding: EdgeInsets.all(32), child: Text('로딩 실패'))
          else
            Expanded(child: _content()),
          const SizedBox(height: 16),
          // 단말 모델도 오분류할 수 있으므로 모든 항목(서버 분석분 + 단말 자동종결분)이
          // 결과 처리로 진입 가능. 단말-only 항목은 단말 결과(대표 행)에 피드백이 붙는다.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('${AppRoutes.result}?imageId=${widget.imageId}');
              },
              child: const Text('결과 처리'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final image = _data!['image'] as Map<String, dynamic>;
    final server = _data!['server_result'] as Map<String, dynamic>?;
    final device = _data!['device_result'] as Map<String, dynamic>?;
    final action = _data!['action_guide'] as Map<String, dynamic>?;

    // Top-3 데이터 소스: 서버 분석이 있으면 그걸 우선, 없으면 단말 결과로 폴백 (양품 자동종결 / 오프라인 단말)
    final primary = server ?? device;
    final top3 = (primary?['top3_predictions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final imageUrl = image['image_url']?.toString();
    // Grad-CAM 은 서버가 불량으로 분류한 항목만 생성됨. 양품(일치/저신뢰)·미생성분은 토글 숨김.
    final hasGradcam = (image['gradcam_url']?.toString().isNotEmpty ?? false);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: _gradcamOn && hasGradcam
                        ? image['gradcam_url']
                        : (imageUrl ?? ''),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
                  ),
                  // 서버가 불량으로 분류해 Grad-CAM 이 있는 경우에만 토글 노출
                  if (hasGradcam)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Grad-CAM', style: TextStyle(color: Colors.white, fontSize: 12)),
                            Switch(value: _gradcamOn, onChanged: (v) => setState(() => _gradcamOn = v)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('추론 결과 (Top-3 Predictions)', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          ...top3.asMap().entries.map((e) => _PredictionBar(rank: e.key + 1, data: e.value)),

          // 매뉴얼 기반 조치 가이드 — 모든 결과에 매뉴얼(결함_유형) 룩업 가이드가 부여됨
          if (action != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withOpacity(0.15),
                border: Border.all(color: AppColors.primaryContainer),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.smart_toy, color: AppColors.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Text('매뉴얼 기반 조치 가이드', style: AppTextStyles.h3),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('[조치 요약]', style: AppTextStyles.labelBold),
                  Text(action['summary']?.toString() ?? '-', style: AppTextStyles.bodyMd),
                  if ((action['detail']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('[상세 조치 내역]', style: AppTextStyles.labelBold),
                    Text(action['detail']?.toString() ?? '-', style: AppTextStyles.bodyMd),
                  ],
                  if ((action['source_manuals'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: Text('매뉴얼 출처 ${(action['source_manuals'] as List).length}건', style: AppTextStyles.labelBold),
                      children: (action['source_manuals'] as List).map<Widget>((m) {
                        final mm = m as Map<String, dynamic>;
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.description, size: 18),
                          title: Text('${mm['title']} - p.${mm['page']}', style: AppTextStyles.bodyMd),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _PredictionBar extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> data;
  const _PredictionBar({required this.rank, required this.data});

  @override
  Widget build(BuildContext context) {
    final conf = (data['confidence'] as num).toDouble();
    final isTop = rank == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isTop ? AppColors.primaryContainer.withOpacity(0.15) : null,
          border: isTop ? Border.all(color: AppColors.primaryContainer) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(data['class']?.toString() ?? '-',
                    style: isTop ? AppTextStyles.h3 : AppTextStyles.bodyMd),
                Text('${(conf * 100).toStringAsFixed(1)}%', style: AppTextStyles.codeData),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: conf,
                minHeight: isTop ? 12 : 10,
                backgroundColor: AppColors.outlineVariant,
                color: isTop ? AppColors.primaryContainer : AppColors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
