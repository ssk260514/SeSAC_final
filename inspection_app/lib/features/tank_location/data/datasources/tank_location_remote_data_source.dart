import 'package:dio/dio.dart';

import '../models/tank_zone_dto.dart';
import '../models/session_dto.dart';

class TankLocationRemoteDataSource {
  final Dio dio;
  TankLocationRemoteDataSource(this.dio);

  Future<List<TankZoneDto>> listTankZones() async {
    final res = await dio.get('/tank-types');
    return (res.data as List)
        .map((e) => TankZoneDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CreateSessionResponseDto> createSession(CreateSessionRequestDto req) async {
    final res = await dio.post('/sessions', data: req.toJson());
    return CreateSessionResponseDto.fromJson(res.data as Map<String, dynamic>);
  }
}
