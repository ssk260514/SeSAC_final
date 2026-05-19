import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/tank_zone.dart';

part 'tank_zone_dto.freezed.dart';
part 'tank_zone_dto.g.dart';

@freezed
class ProcessDto with _$ProcessDto {
  const factory ProcessDto({
    required int process_id,
    required String process_name,
    double? confidence_threshold,
    List<String>? defect_types,
  }) = _ProcessDto;

  factory ProcessDto.fromJson(Map<String, dynamic> json) => _$ProcessDtoFromJson(json);
}

@freezed
class TankZoneDto with _$TankZoneDto {
  const TankZoneDto._();

  const factory TankZoneDto({
    required String tank_type,
    required Map<String, List<String>> sectors,
    String? description,
    required ProcessDto process,
  }) = _TankZoneDto;

  factory TankZoneDto.fromJson(Map<String, dynamic> json) => _$TankZoneDtoFromJson(json);

  TankZone toEntity() => TankZone(
        tankType: tank_type,
        sectors: sectors,
        description: description,
        processId: process.process_id,
        processName: process.process_name,
      );
}
