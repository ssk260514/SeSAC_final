import 'package:dio/dio.dart';

class ResultReviewRemoteDataSource {
  final Dio dio;
  ResultReviewRemoteDataSource(this.dio);

  Future<Map<String, dynamic>> getImageDetail(int imageId) async {
    final res = await dio.get('/images/$imageId/detail');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveFeedback({
    required int resultId,
    required int sessionId,
    String? modifiedDefectType,
    required String severity,
    String? opinion,
    required String finalActionContent,
  }) async {
    final res = await dio.post('/results/$resultId/feedback', data: {
      'session_id': sessionId,
      'modified_defect_type': modifiedDefectType,
      'severity': severity,
      'opinion': opinion,
      'final_action_content': finalActionContent,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> updateRecommendation(int recommendationId, String actionDetail) async {
    await dio.patch('/recommendations/$recommendationId', data: {'action_detail': actionDetail});
  }
}
