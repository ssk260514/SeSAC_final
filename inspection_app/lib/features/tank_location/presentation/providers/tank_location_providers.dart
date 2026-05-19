import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/datasources/tank_location_remote_data_source.dart';
import '../../data/repositories/tank_location_repository_impl.dart';
import '../../domain/repositories/tank_location_repository.dart';

final tankLocationRemoteProvider =
    Provider((ref) => TankLocationRemoteDataSource(ref.watch(dioProvider)));

final tankLocationRepositoryProvider = Provider<TankLocationRepository>(
  (ref) => TankLocationRepositoryImpl(ref.watch(tankLocationRemoteProvider)),
);

class SelectedTankLocation {
  final String? tankType;
  final String? sector;
  final String? subsector;
  const SelectedTankLocation({this.tankType, this.sector, this.subsector});

  SelectedTankLocation copyWith({String? tankType, String? sector, String? subsector}) =>
      SelectedTankLocation(
        tankType: tankType ?? this.tankType,
        sector: sector ?? this.sector,
        subsector: subsector ?? this.subsector,
      );
}

final selectedTankLocationProvider =
    StateProvider<SelectedTankLocation>((_) => const SelectedTankLocation());
