import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/capture_result.dart';

part 'inspect_response_dto.freezed.dart';
part 'inspect_response_dto.g.dart';

@freezed
class ServerResultDto with _$ServerResultDto {
  const factory ServerResultDto({
    required int result_id,
    required String defect_type,
    required double confidence,
    int? inference_ms,
    bool? needs_human_review,
  }) = _ServerResultDto;

  factory ServerResultDto.fromJson(Map<String, dynamic> json) =>
      _$ServerResultDtoFromJson(json);
}

@freezed
class InspectResponseDto with _$InspectResponseDto {
  const InspectResponseDto._();

  const factory InspectResponseDto({
    required int image_id,
    required ServerResultDto server_result,
    String? heatmap_url,
  }) = _InspectResponseDto;

  factory InspectResponseDto.fromJson(Map<String, dynamic> json) =>
      _$InspectResponseDtoFromJson(json);

  CaptureResult toEntity() => CaptureResult(
        imageId: image_id,
        resultId: server_result.result_id,
        defectType: server_result.defect_type,
        confidence: server_result.confidence,
        isDefect: !server_result.defect_type.contains('양품'),
        heatmapUrl: heatmap_url,
      );
}
