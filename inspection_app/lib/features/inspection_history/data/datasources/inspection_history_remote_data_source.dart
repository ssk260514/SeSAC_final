import 'package:dio/dio.dart';
import '../models/result_card_dto.dart';

class InspectionHistoryRemoteDataSource {
  final Dio dio;
  InspectionHistoryRemoteDataSource(this.dio);

  Future<List<ResultCardDto>> listResults(int sessionId, String status) async {
    final res = await dio.get('/sessions/$sessionId/results', queryParameters: {'status': status});
    return (res.data as List).map((e) => ResultCardDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getImageDetail(int imageId) async {
    final res = await dio.get('/images/$imageId/detail');
    return res.data as Map<String, dynamic>;
  }

  Future<void> endSession(int sessionId) async {
    await dio.patch('/sessions/$sessionId/end');
  }
}
