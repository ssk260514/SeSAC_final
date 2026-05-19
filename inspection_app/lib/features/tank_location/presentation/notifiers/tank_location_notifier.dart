import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/tank_zone.dart';
import '../../domain/entities/inspection_session.dart';
import '../providers/tank_location_providers.dart';

part 'tank_location_notifier.freezed.dart';

@freezed
class TankLocationState with _$TankLocationState {
  const factory TankLocationState({
    @Default(false) bool isLoading,
    @Default([]) List<TankZone> zones,
    String? errorMessage,
    int? existingSessionId,
  }) = _TankLocationState;
}

class TankLocationNotifier extends StateNotifier<TankLocationState> {
  final Ref ref;
  TankLocationNotifier(this.ref) : super(const TankLocationState()) {
    _loadZones();
  }

  Future<void> _loadZones() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final zones = await ref.read(tankLocationRepositoryProvider).listTankZones();
      state = state.copyWith(isLoading: false, zones: zones);
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
    }
  }

  Future<InspectionSession?> confirmSelection({
    required String tankType,
    required String sector,
    required String subsector,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null, existingSessionId: null);
    try {
      final session = await ref.read(tankLocationRepositoryProvider).createSession(
            tankType: tankType,
            selectedSector: sector,
            selectedSubsector: subsector,
          );

      ref.read(selectedTankLocationProvider.notifier).state =
          SelectedTankLocation(tankType: tankType, sector: sector, subsector: subsector);

      state = state.copyWith(isLoading: false);
      return session;
    } on DailySessionExistsFailure catch (f) {
      state = state.copyWith(
          isLoading: false, errorMessage: f.message, existingSessionId: f.existingSessionId);
      return null;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return null;
    }
  }
}

final tankLocationNotifierProvider =
    StateNotifierProvider<TankLocationNotifier, TankLocationState>(
  (ref) => TankLocationNotifier(ref),
);
