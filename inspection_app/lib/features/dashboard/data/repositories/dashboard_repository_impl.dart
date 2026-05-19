import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_remote_data_source.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardRemoteDataSource remote;
  DashboardRepositoryImpl(this.remote);

  @override
  Future<DashboardSummary> getSummary() async {
    try {
      final dto = await remote.getSummary();
      return dto.toEntity();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError) throw const NetworkFailure();
      if ((e.response?.statusCode ?? 0) >= 500) throw const ServerFailure();
      throw const UnknownFailure();
    }
  }
}
