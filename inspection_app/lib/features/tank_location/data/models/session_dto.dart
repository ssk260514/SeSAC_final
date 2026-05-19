import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/inspection_session.dart';
import 'tank_zone_dto.dart';

part 'session_dto.freezed.dart';
part 'session_dto.g.dart';

@freezed
class CreateSessionRequestDto with _$CreateSessionRequestDto {
  const factory CreateSessionRequestDto({
    required String tank_type,
    required String selected_sector,
    required String selected_subsector,
  }) = _CreateSessionRequestDto;

  factory CreateSessionRequestDto.fromJson(Map<String, dynamic> json) =>
      _$CreateSessionRequestDtoFromJson(json);
}

@freezed
class CreateSessionResponseDto with _$CreateSessionResponseDto {
  const CreateSessionResponseDto._();

  const factory CreateSessionResponseDto({
    required int session_id,
    required String status,
    required String started_at,
    required String tank_type,
    required String selected_sector,
    required String selected_subsector,
    required ProcessDto process,
  }) = _CreateSessionResponseDto;

  factory CreateSessionResponseDto.fromJson(Map<String, dynamic> json) =>
      _$CreateSessionResponseDtoFromJson(json);

  InspectionSession toEntity() => InspectionSession(
        sessionId: session_id,
        tankType: tank_type,
        selectedSector: selected_sector,
        selectedSubsector: selected_subsector,
        processId: process.process_id,
        processName: process.process_name,
        startedAt: DateTime.parse(started_at),
      );
}
