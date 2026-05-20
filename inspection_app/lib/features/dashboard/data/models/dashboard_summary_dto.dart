import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/dashboard_summary.dart';

part 'dashboard_summary_dto.freezed.dart';
part 'dashboard_summary_dto.g.dart';

@freezed
class SessionSummaryDto with _$SessionSummaryDto {
  const SessionSummaryDto._();

  const factory SessionSummaryDto({
    required int session_id,
    required String tank_type,
    required String started_at,
    String? ended_at,
    String? last_modified_at,
    required bool has_defect,
  }) = _SessionSummaryDto;

  factory SessionSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$SessionSummaryDtoFromJson(json);

  SessionSummary toEntity() => SessionSummary(
        sessionId: session_id,
        tankType: tank_type,
        startedAt: DateTime.parse(started_at),
        endedAt: ended_at == null ? null : DateTime.parse(ended_at!),
        lastModifiedAt:
            last_modified_at == null ? null : DateTime.parse(last_modified_at!),
        hasDefect: has_defect,
      );
}

@freezed
class DashboardSummaryDto with _$DashboardSummaryDto {
  const DashboardSummaryDto._();

  const factory DashboardSummaryDto({
    required int session_number,
    required int today_images,
    required double today_pass_rate,
    int? active_session_id,
    String? active_tank_type,
    String? active_sector,
    String? active_subsector,
    required List<SessionSummaryDto> recent_sessions,
  }) = _DashboardSummaryDto;

  factory DashboardSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardSummaryDtoFromJson(json);

  DashboardSummary toEntity() => DashboardSummary(
        sessionNumber: session_number,
        todayImages: today_images,
        todayPassRate: today_pass_rate,
        activeSessionId: active_session_id,
        activeTankType: active_tank_type,
        activeSector: active_sector,
        activeSubsector: active_subsector,
        recentSessions: recent_sessions.map((s) => s.toEntity()).toList(),
      );
}
