import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/tank_zone.dart';
import '../../domain/entities/inspection_session.dart';
import '../../domain/repositories/tank_location_repository.dart';
import '../datasources/tank_location_remote_data_source.dart';
import '../models/session_dto.dart';

class TankLocationRepositoryImpl implements TankLocationRepository {
  final TankLocationRemoteDataSource remote;
  TankLocationRepositoryImpl(this.remote);

  @override
  Future<List<TankZone>> listTankZones() async {
    try {
      final dtos = await remote.listTankZones();
      return dtos.map((d) => d.toEntity()).toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<InspectionSession> createSession({
    required String tankType,
    required String selectedSector,
    required String selectedSubsector,
  }) async {
    try {
      final dto = await remote.createSession(CreateSessionRequestDto(
        tank_type: tankType,
        selected_sector: selectedSector,
        selected_subsector: selectedSubsector,
      ));
      return dto.toEntity();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Failure _map(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (status == 409 && data is Map) {
      final id = data['detail']?['existing_session_id'] ?? -1;
      return DailySessionExistsFailure(id as int);
    }
    if (e.type == DioExceptionType.connectionError) return const NetworkFailure();
    if (status != null && status >= 500) return const ServerFailure();
    return const UnknownFailure();
  }
}
