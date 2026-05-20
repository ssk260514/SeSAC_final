class ResultDetail {
  final int imageId;
  final int? serverResultId;
  final String defectType;
  final double confidence;
  final int? recommendationId;
  final String actionSummary;
  final String actionDetail;
  final FeedbackData? feedback;

  const ResultDetail({
    required this.imageId,
    this.serverResultId,
    required this.defectType,
    required this.confidence,
    this.recommendationId,
    required this.actionSummary,
    required this.actionDetail,
    this.feedback,
  });
}

class FeedbackData {
  final int feedbackId;
  final String? modifiedDefectType;
  final String? severity;
  final String? opinion;
  final String? finalAction;

  const FeedbackData({
    required this.feedbackId,
    this.modifiedDefectType,
    this.severity,
    this.opinion,
    this.finalAction,
  });
}
