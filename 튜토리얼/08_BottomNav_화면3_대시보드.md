# 08. Bottom Navigation + 화면 3 대시보드

> **이 단계가 끝나면**: 4탭 Bottom Nav가 동작하고, 대시보드 화면에 통계 카드 3개·최근 이력 3건·"검사 시작" 버튼이 백엔드 데이터와 함께 표시됩니다.
>
> **예상 시간**: 3시간

> **참조 명세서**: `frontend/design/PAGE/03_대시보드/COMPONENT.md`, `화면_명세서.md` 화면 3, `API_SPEC.md` SESS-002 / SESS-004

---

## 1. 백엔드 — 대시보드 요약 + 세션 이력

### 1-1. `app/schemas/session.py`

```python
from pydantic import BaseModel


class SessionSummary(BaseModel):
    session_id: int
    tank_type: str
    started_at: str
    ended_at: str | None = None
    last_modified_at: str | None = None
    has_defect: bool


class DashboardSummary(BaseModel):
    session_number: int          # 당일 세션 번호 (PK 그대로)
    today_images: int
    today_pass_rate: float       # 0~100
    active_session_id: int | None
    recent_sessions: list[SessionSummary]
```

### 1-2. `app/api/session.py` 추가 엔드포인트

기존 `session.py` 파일에 추가:

```python
@router.get("/sessions", response_model=list[SessionSummary])
async def list_sessions(
    status: str | None = None,
    limit: int = 20,
    offset: int = 0,
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    where = "검사원_ID = :iid"
    params = {"iid": inspector_id, "lim": limit, "off": offset}
    if status and status != "all":
        where += " AND 세션_상태 = :st"
        params["st"] = status

    res = await db.execute(text(f"""
        SELECT 세션_ID, 탱크_타입, 시작_일시, 종료_일시, 불량_수 > 0 AS has_defect
        FROM 검사_세션
        WHERE {where}
        ORDER BY 시작_일시 DESC
        LIMIT :lim OFFSET :off
    """), params)
    rows = res.all()
    return [
        SessionSummary(
            session_id=r[0],
            tank_type=r[1],
            started_at=r[2].isoformat(),
            ended_at=r[3].isoformat() if r[3] else None,
            has_defect=bool(r[4]),
        )
        for r in rows
    ]


@router.get("/dashboard/summary", response_model=DashboardSummary)
async def dashboard_summary(
    inspector_id: int = Depends(get_current_inspector_id),
    db: AsyncSession = Depends(get_db),
):
    # 오늘 진행중 세션
    active = await db.execute(text("""
        SELECT 세션_ID FROM 검사_세션
        WHERE 검사원_ID = :iid AND 세션_상태='진행중'
              AND 시작_일시 >= CURRENT_DATE
        LIMIT 1
    """), {"iid": inspector_id})
    active_id = active.scalar_one_or_none()

    # 오늘 통계 (진행중 + 완료 합산)
    today = await db.execute(text("""
        SELECT COALESCE(SUM(총_이미지_수),0), COALESCE(SUM(양품_수),0)
        FROM 검사_세션
        WHERE 검사원_ID = :iid AND 시작_일시 >= CURRENT_DATE
    """), {"iid": inspector_id})
    total_imgs, pass_imgs = today.first()
    pass_rate = (pass_imgs / total_imgs * 100.0) if total_imgs > 0 else 0.0

    # 최근 완료 세션 3건 + 최종 수정 시각
    recent = await db.execute(text("""
        SELECT s.세션_ID, s.탱크_타입, s.시작_일시, s.종료_일시,
               (s.불량_수 > 0) AS has_defect,
               MAX(f.수정_일시) AS last_modified
        FROM 검사_세션 s
        LEFT JOIN 검사_피드백 f ON f.세션_ID = s.세션_ID
        WHERE s.검사원_ID = :iid AND s.세션_상태 = '완료'
        GROUP BY s.세션_ID
        ORDER BY s.종료_일시 DESC NULLS LAST
        LIMIT 3
    """), {"iid": inspector_id})
    recent_rows = recent.all()

    # 당일 세션 번호 (active 우선, 없으면 가장 최근 세션 PK)
    session_number_row = await db.execute(text("""
        SELECT 세션_ID FROM 검사_세션
        WHERE 검사원_ID = :iid AND 시작_일시 >= CURRENT_DATE
        ORDER BY 시작_일시 DESC LIMIT 1
    """), {"iid": inspector_id})
    session_number = session_number_row.scalar_one_or_none() or 0

    return DashboardSummary(
        session_number=session_number,
        today_images=total_imgs,
        today_pass_rate=round(pass_rate, 1),
        active_session_id=active_id,
        recent_sessions=[
            SessionSummary(
                session_id=r[0],
                tank_type=r[1],
                started_at=r[2].isoformat(),
                ended_at=r[3].isoformat() if r[3] else None,
                last_modified_at=r[5].isoformat() if r[5] else None,
                has_defect=bool(r[4]),
            )
            for r in recent_rows
        ],
    )
```

### 1-3. Swagger로 확인

토큰을 받아서(`/api/auth/login`) Authorize 버튼으로 입력 후 `/api/dashboard/summary` 호출 → JSON이 나와야 합니다.

---

## 2. Flutter — Dashboard Feature 모듈

기본 패턴은 06번·07번과 동일하므로 핵심만 보여드립니다.

### 2-1. Entity

`features/dashboard/domain/entities/dashboard_summary.dart`:
```dart
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
  final List<SessionSummary> recentSessions;

  const DashboardSummary({
    required this.sessionNumber,
    required this.todayImages,
    required this.todayPassRate,
    this.activeSessionId,
    required this.recentSessions,
  });
}
```

### 2-2. Repository (추상)

`features/dashboard/domain/repositories/dashboard_repository.dart`:
```dart
import '../entities/dashboard_summary.dart';

abstract class DashboardRepository {
  Future<DashboardSummary> getSummary();
}
```

### 2-3. DTO

`features/dashboard/data/models/dashboard_summary_dto.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/dashboard_summary.dart';

part 'dashboard_summary_dto.freezed.dart';
part 'dashboard_summary_dto.g.dart';

@freezed
class SessionSummaryDto with _$SessionSummaryDto {
  const SessionSummaryDto._();

  const factory SessionSummaryDto({
    required int session_id,
    required String tank_type,
    required String started_at,
    String? ended_at,
    String? last_modified_at,
    required bool has_defect,
  }) = _SessionSummaryDto;

  factory SessionSummaryDto.fromJson(Map<String, dynamic> json) => _$SessionSummaryDtoFromJson(json);

  SessionSummary toEntity() => SessionSummary(
    sessionId: session_id,
    tankType: tank_type,
    startedAt: DateTime.parse(started_at),
    endedAt: ended_at == null ? null : DateTime.parse(ended_at!),
    lastModifiedAt: last_modified_at == null ? null : DateTime.parse(last_modified_at!),
    hasDefect: has_defect,
  );
}

@freezed
class DashboardSummaryDto with _$DashboardSummaryDto {
  const DashboardSummaryDto._();

  const factory DashboardSummaryDto({
    required int session_number,
    required int today_images,
    required double today_pass_rate,
    int? active_session_id,
    required List<SessionSummaryDto> recent_sessions,
  }) = _DashboardSummaryDto;

  factory DashboardSummaryDto.fromJson(Map<String, dynamic> json) => _$DashboardSummaryDtoFromJson(json);

  DashboardSummary toEntity() => DashboardSummary(
    sessionNumber: session_number,
    todayImages: today_images,
    todayPassRate: today_pass_rate,
    activeSessionId: active_session_id,
    recentSessions: recent_sessions.map((s) => s.toEntity()).toList(),
  );
}
```

### 2-4. DataSource + Repository 구현

`features/dashboard/data/datasources/dashboard_remote_data_source.dart`:
```dart
import 'package:dio/dio.dart';
import '../models/dashboard_summary_dto.dart';

class DashboardRemoteDataSource {
  final Dio dio;
  DashboardRemoteDataSource(this.dio);

  Future<DashboardSummaryDto> getSummary() async {
    final res = await dio.get('/dashboard/summary');
    return DashboardSummaryDto.fromJson(res.data as Map<String, dynamic>);
  }
}
```

`features/dashboard/data/repositories/dashboard_repository_impl.dart`:
```dart
import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_remote_data_source.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardRemoteDataSource remote;
  DashboardRepositoryImpl(this.remote);

  @override
  Future<DashboardSummary> getSummary() async {
    try {
      final dto = await remote.getSummary();
      return dto.toEntity();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError) throw const NetworkFailure();
      if ((e.response?.statusCode ?? 0) >= 500) throw const ServerFailure();
      throw const UnknownFailure();
    }
  }
}
```

### 2-5. Provider + Notifier

`features/dashboard/presentation/providers/dashboard_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/datasources/dashboard_remote_data_source.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../domain/repositories/dashboard_repository.dart';

final dashboardRemoteProvider = Provider((ref) => DashboardRemoteDataSource(ref.watch(dioProvider)));
final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepositoryImpl(ref.watch(dashboardRemoteProvider)),
);
```

`features/dashboard/presentation/notifiers/dashboard_notifier.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../providers/dashboard_providers.dart';

part 'dashboard_notifier.freezed.dart';

@freezed
class DashboardState with _$DashboardState {
  const factory DashboardState({
    @Default(true) bool isLoading,
    DashboardSummary? data,
    String? errorMessage,
  }) = _DashboardState;
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final Ref ref;
  DashboardNotifier(this.ref) : super(const DashboardState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = await ref.read(dashboardRepositoryProvider).getSummary();
      state = state.copyWith(isLoading: false, data: data);
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
    }
  }
}

final dashboardNotifierProvider =
    StateNotifierProvider.autoDispose<DashboardNotifier, DashboardState>(
  (ref) => DashboardNotifier(ref),
);
```

### 2-6. 코드 생성

```powershell
dart run build_runner build --delete-conflicting-outputs
```

---

## 3. Dashboard Screen

기존 placeholder를 다음으로 대체:

`features/dashboard/presentation/screens/dashboard_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/storage/token_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../tank_location/presentation/providers/tank_location_providers.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../notifiers/dashboard_notifier.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardNotifierProvider);
    final inspector = ref.watch(currentInspectorProvider);
    final tankLoc = ref.watch(selectedTankLocationProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person, color: AppColors.onPrimaryContainer, size: 20),
            ),
            const SizedBox(width: 8),
            const Text('LNG Inspection'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_location_alt_outlined),
            tooltip: '위치 변경',
            onPressed: () => context.go(AppRoutes.tankLocation),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () async {
              await ref.read(tokenStorageProvider).clear();
              if (!context.mounted) return;
              context.go(AppRoutes.login);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardNotifierProvider.notifier).refresh(),
        child: state.isLoading && state.data == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 프로필 카드
                  Card(
                    color: AppColors.surfaceContainerLowest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.secondaryContainer,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(Icons.person, color: AppColors.onSecondaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(inspector?.name ?? '-', style: AppTextStyles.h3),
                                const SizedBox(height: 4),
                                Text(inspector?.department ?? '-', style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 현재 검사 위치 (있을 때만)
                  if (tankLoc.tankType != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryFixed,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '탱크 ${tankLoc.tankType} · ${tankLoc.sector} / ${tankLoc.subsector}',
                        style: AppTextStyles.labelBold.copyWith(color: AppColors.onPrimaryContainer),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // 통계 카드 3개
                  if (state.data != null) _StatsRow(data: state.data!),
                  const SizedBox(height: 24),

                  // 검사 시작 버튼
                  ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('검사 시작'),
                    onPressed: () => context.go(AppRoutes.capture),
                  ),
                  const SizedBox(height: 24),

                  // 최근 세션 이력
                  Text('최근 세션 이력', style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  if (state.data == null || state.data!.recentSessions.isEmpty)
                    _EmptyRecent()
                  else
                    ...state.data!.recentSessions.map((s) => _RecentSessionTile(s)),

                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(state.errorMessage!, style: TextStyle(color: AppColors.error)),
                  ],
                ],
              ),
      ),
    );
  }
}


class _StatsRow extends StatelessWidget {
  final DashboardSummary data;
  const _StatsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(label: '세션 번호', value: '#${data.sessionNumber}'),
        const SizedBox(width: 8),
        _StatCard(label: '총 이미지', value: '${data.todayImages}장'),
        const SizedBox(width: 8),
        _StatCard(label: '양품률', value: '${data.todayPassRate.toStringAsFixed(1)}%'),
      ],
    );
  }
}


class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value, style: AppTextStyles.h2),
          ],
        ),
      ),
    );
  }
}


class _RecentSessionTile extends StatelessWidget {
  final SessionSummary s;
  const _RecentSessionTile(this.s);

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy.MM.dd HH:mm');
    return Card(
      color: AppColors.surfaceContainerLowest,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: s.hasDefect ? AppColors.errorContainer : AppColors.successContainerOrFallback(context),
          child: Icon(s.hasDefect ? Icons.warning : Icons.check_circle, color: s.hasDefect ? AppColors.error : Color(0xFF1B5E20)),
        ),
        title: Text('탱크 ${s.tankType}', style: AppTextStyles.h3),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('검사 시작: ${fmt.format(s.startedAt)}', style: AppTextStyles.bodyMd),
            if (s.endedAt != null) Text('검사 종료: ${fmt.format(s.endedAt!)}', style: AppTextStyles.bodyMd),
            if (s.lastModifiedAt != null) Text('최종 수정: ${fmt.format(s.lastModifiedAt!)}', style: AppTextStyles.bodyMd),
          ],
        ),
      ),
    );
  }
}


class _EmptyRecent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.history, size: 48, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('완료된 세션이 아직 없습니다', style: AppTextStyles.bodyLg.copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text("'검사 시작'을 눌러 첫 검사를 시작하세요", style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// 임시 보조 — 더 깔끔하게 ThemeExtension을 쓰려면 위 04번의 SemanticColorsX 사용
extension on AppColors {
  static Color successContainerOrFallback(BuildContext _) => const Color(0xFFC8E6C9);
}
```

> ⚠️ extension 부분의 코드는 `successContainerOrFallback` 헬퍼 사용. 04번에서 만든 `context.semanticColors.successContainer`를 쓰는 게 더 깔끔합니다. 처음에는 위 예시처럼 인라인으로 두고, 익숙해지면 리팩터하세요.

---

## 4. 동작 확인

1. 백엔드 실행 + Flutter 실행
2. 로그인 → 탱크 선택 → 대시보드
3. 상단 AppBar:
   - 프로필 아이콘 + "LNG Inspection"
   - 우측: 위치 변경 / 알림 / 로그아웃 아이콘
4. 본문:
   - 프로필 카드 (이름, 부서)
   - "탱크 B · 외부 / 지지대" 칩
   - 통계 카드 3개 (현재는 모두 0)
   - "검사 시작" 큰 버튼
   - 최근 이력 (현재는 EmptyState — 완료된 세션 없음)
5. 우상단 로그아웃 → 로그인 화면
6. Bottom Nav 탭 전환 → 다른 placeholder 화면이 정상 표시
7. **AppBar 위치 변경 아이콘** → `/tank-location` → 1단계 화면

### DB로 가짜 완료 세션 만들어보기

```powershell
docker exec -it inspection_postgres psql -U inspection_user -d inspection_db
```

```sql
INSERT INTO 검사_세션 (검사원_ID, 공정_ID, 탱크_타입, 선택_구역, 선택_세부위치, 총_이미지_수, 양품_수, 불량_수, 세션_상태, 시작_일시, 종료_일시)
VALUES (1, 1, 'B', '외부', '지지대', 10, 8, 2, '완료', NOW() - INTERVAL '2 hours', NOW() - INTERVAL '1 hour'),
       (1, 1, 'B', '외부', '플랫폼', 5, 5, 0, '완료', NOW() - INTERVAL '4 hours', NOW() - INTERVAL '3 hours');
```

앱 새로고침(아래로 당기기) → 최근 이력 2건 + 통계가 갱신되어 보여야 함.

---

## ✅ 다음 단계로 가기 전 체크리스트

- [ ] `/api/dashboard/summary` GET이 JSON을 반환한다
- [ ] `/api/sessions` GET이 세션 목록을 반환한다
- [ ] 대시보드에 프로필·위치 칩·통계 3개·검사 시작 버튼·최근 이력이 표시된다
- [ ] DB에 완료 세션 행을 넣으면 앱에 최근 이력이 보인다
- [ ] Bottom Nav 4탭 전환이 부드럽게 동작한다
- [ ] AppBar "위치 변경" 아이콘이 탱크 선택 화면을 다시 띄운다
- [ ] 로그아웃 → 로그인 화면 → 자동 로그인 안 됨 (토큰 삭제됨)
- [ ] Pull-to-refresh (아래로 당기기) 시 대시보드 데이터가 새로 받아진다

다음 단계 **[09_화면5_카메라_촬영.md](09_화면5_카메라_촬영.md)** 로 이동하세요.
