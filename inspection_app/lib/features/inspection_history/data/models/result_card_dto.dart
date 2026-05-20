import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/entities/result_card.dart';

part 'result_card_dto.freezed.dart';
part 'result_card_dto.g.dart';

@freezed
class ResultCardDto with _$ResultCardDto {
  const ResultCardDto._();
  const factory ResultCardDto({
    required int image_id,
    required String thumbnail_url,
    required String captured_at,
    required String defect_type,
    required bool is_defect,
    required double confidence,
    required String result_status,
    required bool needs_human_review,
    required bool has_server_result,
    required bool has_device_result,
    String? feedback_status,
  }) = _ResultCardDto;
  factory ResultCardDto.fromJson(Map<String, dynamic> json) => _$ResultCardDtoFromJson(json);

  ResultCard toEntity() => ResultCard(
    imageId: image_id,
    thumbnailUrl: thumbnail_url,
    capturedAt: DateTime.parse(captured_at),
    defectType: defect_type,
    isDefect: is_defect,
    confidence: confidence,
    resultStatus: result_status,
    needsHumanReview: needs_human_review,
    hasServerResult: has_server_result,
    hasDeviceResult: has_device_result,
    feedbackStatus: feedback_status,
  );
}
