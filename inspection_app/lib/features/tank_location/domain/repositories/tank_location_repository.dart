import '../entities/tank_zone.dart';
import '../entities/inspection_session.dart';

abstract class TankLocationRepository {
  Future<List<TankZone>> listTankZones();
  Future<InspectionSession> createSession({
    required String tankType,
    required String selectedSector,
    required String selectedSubsector,
  });
}
