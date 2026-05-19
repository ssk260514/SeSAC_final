import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../notifiers/tank_location_notifier.dart';

class TankLocationScreen extends ConsumerStatefulWidget {
  const TankLocationScreen({super.key});

  @override
  ConsumerState<TankLocationScreen> createState() => _TankLocationScreenState();
}

class _TankLocationScreenState extends ConsumerState<TankLocationScreen> {
  int _step = 1;           // 1: 탱크 선택, 2: 위치 선택
  String? _selectedTank;   // "B" or "C"
  String? _selectedSector;
  String? _selectedSubsector;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tankLocationNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 1 ? '탱크 유형 선택' : '위치 선택'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step == 2) {
              setState(() {
                _step = 1;
                _selectedSector = null;
                _selectedSubsector = null;
              });
            } else {
              context.go(AppRoutes.login);
            }
          },
        ),
      ),
      body: state.isLoading && state.zones.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _step == 1
              ? _buildStep1(state.zones)
              : _buildStep2(state),
    );
  }

  Widget _buildStep1(List zones) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: zones.map<Widget>((z) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: AppColors.surfaceContainerLowest,
          child: ListTile(
            leading: const Icon(Icons.propane_tank, color: AppColors.primary, size: 32),
            title: Text('탱크 ${z.tankType} (Type ${z.tankType})', style: AppTextStyles.h3),
            subtitle: Text(
              z.description ?? '',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              _selectedTank = z.tankType;
              _step = 2;
            }),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStep2(TankLocationState state) {
    final zone = state.zones.firstWhere((z) => z.tankType == _selectedTank);
    final sectors = zone.sectors.keys.toList();
    final subsectors =
        _selectedSector == null ? <String>[] : (zone.sectors[_selectedSector] ?? []);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('구역', style: AppTextStyles.labelBold),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedSector,
            decoration: const InputDecoration(),
            hint: const Text('구역을 선택하세요'),
            items: sectors.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() {
              _selectedSector = v;
              _selectedSubsector = null;
            }),
          ),
          const SizedBox(height: 16),

          const Text('세부 위치', style: AppTextStyles.labelBold),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedSubsector,
            decoration: const InputDecoration(),
            hint: const Text('세부 위치를 선택하세요'),
            items: subsectors.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged:
                _selectedSector == null ? null : (v) => setState(() => _selectedSubsector = v),
          ),
          const Spacer(),

          ElevatedButton(
            onPressed:
                (_selectedSector != null && _selectedSubsector != null && !state.isLoading)
                    ? () async {
                        final session = await ref
                            .read(tankLocationNotifierProvider.notifier)
                            .confirmSelection(
                              tankType: _selectedTank!,
                              sector: _selectedSector!,
                              subsector: _selectedSubsector!,
                            );
                        if (!mounted) return;
                        if (session != null) {
                          context.go(AppRoutes.dashboard);
                        } else {
                          final s = ref.read(tankLocationNotifierProvider);
                          if (s.existingSessionId != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.errorMessage ?? '이미 세션이 있습니다.')),
                            );
                            context.go(AppRoutes.history);
                          } else if (s.errorMessage != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(s.errorMessage!),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      }
                    : null,
            child: state.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('확인'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
