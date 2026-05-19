import 'package:dio/dio.dart';
import '../models/dashboard_summary_dto.dart';

class DashboardRemoteDataSource {
  final Dio dio;
  DashboardRemoteDataSource(this.dio);

  Future<DashboardSummaryDto> getSummary() async {
    final res = await dio.get('/dashboard/summary');
    return DashboardSummaryDto.fromJson(res.data as Map<String, dynamic>);
  }
}
