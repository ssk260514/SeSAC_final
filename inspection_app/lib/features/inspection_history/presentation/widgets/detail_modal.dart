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
    final hasServer = _data?['server_result'] != null;
    final title = (_data == null || hasServer) ? '정밀 분석 결과' : '단말 자동 종결';

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
                Text(title, style: AppTextStyles.h1),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: hasServer
                ? ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go('${AppRoutes.result}?imageId=${widget.imageId}');
                    },
                    child: const Text('결과 처리'),
                  )
                : OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기'),
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

    // 서버 분석이 있으면 그걸 우선, 없으면 단말 결과로 폴백 (양품 자동종결 / 오프라인 단말)
    final primary = server ?? device;
    final top3 = (primary?['top3_predictions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final hasServer = server != null;

    // 단말 종결 항목은 이미지 경로가 local://batch, local://device-only, s3:// 등이라 직접 표시 불가
    final imageUrl = image['image_url']?.toString();
    final canShowImage = imageUrl != null &&
        (imageUrl.startsWith('http://') || imageUrl.startsWith('https://'));

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
              child: canShowImage
                  ? Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: _gradcamOn && (image['gradcam_url'] != null)
                              ? image['gradcam_url']
                              : imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                          errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
                        ),
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
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.devices, size: 36, color: AppColors.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text('단말 종결 항목 — 서버에 이미지 보관 안 됨',
                              style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
            ),
          ),
          if (canShowImage) ...[
            const SizedBox(height: 8),
            Text('* 이미지를 두 손가락으로 확대(Pinch Zoom)할 수 있습니다.',
                style: AppTextStyles.caption.copyWith(fontStyle: FontStyle.italic, color: AppColors.onSurfaceVariant)),
          ],

          const SizedBox(height: 16),
          Text(hasServer ? '추론 결과 (Top-3 Predictions)' : '단말 추론 결과 (Top-3 Predictions)',
              style: AppTextStyles.h3),
          const SizedBox(height: 8),
          ...top3.asMap().entries.map((e) => _PredictionBar(rank: e.key + 1, data: e.value)),

          // RAG 조치 가이드는 서버 정밀분석이 있을 때만 의미가 있음
          if (hasServer && action != null && action['recommendation_id'] != null) ...[
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
                      Text('RAG 생성 조치 가이드', style: AppTextStyles.h3),
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
