class InspectionSession {
  final int sessionId;
  final String tankType;
  final String selectedSector;
  final String selectedSubsector;
  final int processId;
  final String processName;
  final DateTime startedAt;

  const InspectionSession({
    required this.sessionId,
    required this.tankType,
    required this.selectedSector,
    required this.selectedSubsector,
    required this.processId,
    required this.processName,
    required this.startedAt,
  });
}
