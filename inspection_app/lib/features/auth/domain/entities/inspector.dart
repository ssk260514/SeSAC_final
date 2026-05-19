class Inspector {
  final int inspectorId;
  final String name;
  final String? department;

  const Inspector({
    required this.inspectorId,
    required this.name,
    this.department,
  });
}
