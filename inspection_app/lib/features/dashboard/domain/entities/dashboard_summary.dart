class SessionSummary {
  final int sessionId;
  final String tankType;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? lastModifiedAt;
  final bool hasDefect;

  const SessionSummary({
    required this.sessionId,
    required this.tankType,
    required this.startedAt,
    this.endedAt,
    this.lastModifiedAt,
    required this.hasDefect,
  });
}

class DashboardSummary {
  final int sessionNumber;
  final int todayImages;
  final double todayPassRate;
  final int? activeSessionId;
  final String? activeTankType;
  final String? activeSector;
  final String? activeSubsector;
  final List<SessionSummary> recentSessions;

  const DashboardSummary({
    required this.sessionNumber,
    required this.todayImages,
    required this.todayPassRate,
    this.activeSessionId,
    this.activeTankType,
    this.activeSector,
    this.activeSubsector,
    required this.recentSessions,
  });
}
