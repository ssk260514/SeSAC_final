class ResultCard {
  final int imageId;
  final String thumbnailUrl;
  final DateTime capturedAt;
  final String defectType;
  final bool isDefect;
  final double confidence;
  final String resultStatus;
  final bool needsHumanReview;
  final bool hasServerResult;
  final bool hasDeviceResult;
  final String? feedbackStatus;

  const ResultCard({
    required this.imageId,
    required this.thumbnailUrl,
    required this.capturedAt,
    required this.defectType,
    required this.isDefect,
    required this.confidence,
    required this.resultStatus,
    required this.needsHumanReview,
    required this.hasServerResult,
    required this.hasDeviceResult,
    this.feedbackStatus,
  });
}
