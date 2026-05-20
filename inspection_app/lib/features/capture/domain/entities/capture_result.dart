class CaptureResult {
  final int imageId;
  final int resultId;
  final String defectType;
  final double confidence;
  final bool isDefect;
  final String? heatmapUrl;

  const CaptureResult({
    required this.imageId,
    required this.resultId,
    required this.defectType,
    required this.confidence,
    required this.isDefect,
    this.heatmapUrl,
  });
}
