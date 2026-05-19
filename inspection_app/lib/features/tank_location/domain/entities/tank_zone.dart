class TankZone {
  final String tankType;
  final Map<String, List<String>> sectors;
  final String? description;
  final int processId;
  final String processName;

  const TankZone({
    required this.tankType,
    required this.sectors,
    this.description,
    required this.processId,
    required this.processName,
  });
}
