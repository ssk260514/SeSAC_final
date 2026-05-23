# 19. 4주차 — 사내 MDM 배포 + JWT 자동 갱신 안정화

> **이 단계가 끝나면**: 18번에서 만든 APK 아티팩트가 사내 MDM(모바일 단말 관리) 시스템에 등록되어 검사원 단말기에 **자동 설치**됩니다. 그리고 토큰이 만료되어도 사용자에게 "다시 로그인하세요" 가 뜨지 않고 백그라운드에서 자동 갱신되어 검사가 끊기지 않습니다.
>
> **예상 시간**: 4시간

> ⚠️ **단일 모델 전제**: 본 단계는 배포·인증 안정화이므로 모델 구조와 무관합니다. 다만 MDM 으로 배포되는 APK 안에 단일 모델 `.tflite` 가 정상 포함되어 있어야 하며(18번 자동 검증 의존), JWT 갱신 시 OTA-001 호출(`GET /api/model/version`)도 자동 재시도 대상입니다.

> **참조 명세서**: [`아키텍처_명세서.md`](../명세서/아키텍처_명세서.md) Part 4 4주차 (L177·L179)·영역 D 두 채널 분리, [`API_SPEC.md`](../명세서/API_SPEC.md) AUTH 시리즈, [`기능_명세서.md`](../명세서/기능_명세서.md) §1 인증, [`tutorial/05_네트워크와_인증_뼈대.md`](05_네트워크와_인증_뼈대.md) (Dio 인터셉터 기반)

---

## 1. 왜 MDM + JWT 자동 갱신인가

### 1-1. MDM (Mobile Device Management)
- 검사원이 매번 Play Store 에서 앱을 깔게 하면 **사내 보안 정책 위반**(외부 스토어 배포 = 영업비밀 노출 위험)
- MDM 은 회사 단말기에 미리 프로파일을 깔아두면 **관리자가 원격으로 APK 푸시·자동 설치**할 수 있는 시스템
- 18번에서 만든 자동 빌드 산출물(`app-release.apk`) 을 MDM 에 업로드 → 검사원은 신경 안 써도 새 버전이 깔림

### 1-2. JWT 자동 갱신
- AUTH 토큰(`access_token`)은 보안상 30분 만료. 검사 도중 만료되면 다음 API 호출이 **401 UNAUTHORIZED** 로 실패
- 사용자에게 "다시 로그인" 화면이 뜨면 진행중인 검사 흐름이 끊김 → 검사원 불만 + 데이터 손실 가능
- **해결**: 401 응답을 감지하면 자동으로 `refresh_token` 으로 새 `access_token` 발급 → 원래 요청을 재시도 → 사용자는 모름

```
검사 중 API 호출
    │
    ▼
401 UNAUTHORIZED (access_token 만료)
    │
    ├─ Dio 인터셉터가 자동 감지
    │     │
    │     ├─ POST /api/auth/refresh (refresh_token 사용)
    │     │     ├─ 성공 → 새 access_token 저장 → 원래 요청 재시도 → 사용자에게는 정상 응답
    │     │     └─ 실패 (refresh_token도 만료) → 로그인 화면으로 보냄
```

> 💡 본 단계는 **05번의 Dio 인터셉터를 엣지케이스까지 강화**하는 작업입니다. 동시 요청 중 401·refresh 동시 실패·재진입 등 운영에서 발생하는 케이스를 처리합니다.

---

## 2. 사전 준비

- 18번(CI/CD 자동 빌드) 완료 — APK 아티팩트가 다운로드 가능
- 05번(네트워크·인증 뼈대) 완료 — Dio 클라이언트와 JWT 토큰 저장 로직 존재
- 사내 IT 팀에 MDM 시스템 정보 확인:
  - MDM 종류 (예: Microsoft Intune, Jamf, MobileIron, 자체 개발 등)
  - APK 업로드 방법 (관리자 콘솔 / API)
  - 배포 그룹·정책 (검사원 단말기 그룹)
- 거부 시 대안용 Google Play Console 계정 (회사 명의)

---

## 3. 사내 MDM 연동 (대표 시나리오)

MDM 종류마다 UI 가 다르므로 본 가이드는 **공통 흐름**만 다룹니다. 실제 작업 시 IT 팀과 함께 진행하세요.

### 3-1. APK 업로드

1. 18번 워크플로의 Artifacts 에서 `app-release-{sha}.apk` 다운로드
2. MDM 관리자 콘솔 → **Apps** 또는 **Application Management** → **Add app** → **Line-of-business app** 선택
3. APK 파일 업로드 → 메타정보 입력:
   - 이름: `LNG 탱크 검사`
   - 버전: `1.0.0+1` (`pubspec.yaml` 의 `version:` 과 일치)
   - 카테고리: `Business`
   - 설명: 검사원 안내 문구

### 3-2. 배포 그룹 지정

- **Required**(필수 설치) vs **Available**(선택 설치) 중 **Required** 선택 → 검사원 단말기는 자동 설치
- 배포 그룹: 검사원 IT 자산 인벤토리 그룹 (사전에 등록된 디바이스 ID 또는 사용자 그룹)

### 3-3. 자동 업데이트 정책

- **Update policy**: `Force update` (검사원이 거부할 수 없게 — 사내 정책 필수)
- **Background install**: 단말기 충전 중 + Wi-Fi 연결 시 자동 설치

### 3-4. 배포 확인 (파일럿 단말기)

- IT 팀에서 파일럿 단말기 5대 정도에 정책 적용 → 자동 설치 확인
- 단말기 화면에서 앱 아이콘 등장 → 실행 → 로그인 정상 동작 확인
- 16번 OTA 도 함께 검증: 앱 첫 실행 시 Firebase ML 다운로드 → SHA-256 검증 → 다음 시작 시 적용

---

## 4. Play Console 내부 테스트 대안 (MDM 거부 시)

사내 MDM 이 외부 APK 거부 정책이거나 도입 일정이 늦어질 때 대안:

### 4-1. Google Play Console 등록

1. https://play.google.com/console 에 회사 명의 계정 등록 (등록비 $25)
2. 새 앱 만들기 → **Internal testing track** 선택 (공개 안 됨)
3. 18번 자동 빌드 산출물(APK) 업로드. 단, Play Console 은 **AAB(Android App Bundle)** 권장 — `flutter build appbundle --release` 로 빌드해 업로드 가능
4. 테스터 그룹에 검사원 이메일 등록 → 검사원이 초대 링크 수락 → Play Store 에서 설치

### 4-2. AAB 빌드 추가 (옵션)

`.github/workflows/flutter-build.yml` 에 AAB step 추가:

```yaml
      - name: Build App Bundle
        run: flutter build appbundle --release

      - name: Upload AAB artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-release-bundle-${{ github.sha }}
          path: inspection_app/build/app/outputs/bundle/release/app-release.aab
          retention-days: 30
```

| 항목 | 사내 MDM | Play Console 내부 테스트 |
|---|---|---|
| 비용 | 사내 라이선스 | $25 일회성 등록비 |
| 외부 노출 | 없음 | 내부 테스트 트랙은 비공개지만 Google 인프라 경유 |
| 자동 설치 | Required 정책으로 강제 | 사용자가 Play Store 에서 수동 설치 |
| 영업비밀 보호 | ★★★★ | ★★★ (Google 정책 의존) |

→ **본 프로젝트는 사내 MDM 우선**. Play Console 은 MDM 일정 지연 시만 임시 사용.

---

## 5. JWT 자동 갱신 안정화 — Dio 인터셉터 확장

05번에서 만든 기본 인터셉터를 운영 수준으로 강화합니다.

### 5-1. `lib/core/network/auth_interceptor.dart` (05번에 추가 또는 신규)

```dart
import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this.dio, this.tokenStorage);
  final Dio dio;
  final TokenStorage tokenStorage;

  // 동시 401 응답에 대한 refresh 중복 호출 방지 (mutex)
  Completer<bool>? _refreshing;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokenStorage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final req = err.requestOptions;

    // 401이 아니거나, refresh 자체가 401 받은 경우는 그대로 전달
    if (status != 401 || req.path.endsWith('/auth/refresh')) {
      return handler.next(err);
    }
    // 같은 요청이 이미 retry 됐으면 무한루프 방지
    if (req.extra['retried'] == true) {
      return handler.next(err);
    }

    final refreshed = await _refreshOnce();
    if (!refreshed) {
      // refresh 실패 → 로그인 화면으로 (Riverpod이 listen 하는 authStateProvider 갱신)
      await tokenStorage.clear();
      return handler.next(err);
    }

    // 원 요청 재시도 (새 토큰으로)
    final newToken = await tokenStorage.readAccessToken();
    final retryOptions = req.copyWith(
      headers: {...req.headers, 'Authorization': 'Bearer $newToken'},
      extra: {...req.extra, 'retried': true},
    );
    try {
      final res = await dio.fetch(retryOptions);
      return handler.resolve(res);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// 동시에 여러 요청이 401 받아도 refresh 는 1회만 실행
  Future<bool> _refreshOnce() async {
    if (_refreshing != null) return _refreshing!.future;

    final completer = Completer<bool>();
    _refreshing = completer;
    try {
      final refreshToken = await tokenStorage.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        completer.complete(false);
        return false;
      }
      final res = await dio.post('/auth/refresh', data: {'refresh_token': refreshToken});
      final newAccess = res.data['access_token'] as String;
      final newRefresh = res.data['refresh_token'] as String?;
      await tokenStorage.writeAccessToken(newAccess);
      if (newRefresh != null) await tokenStorage.writeRefreshToken(newRefresh);
      completer.complete(true);
      return true;
    } on DioException {
      completer.complete(false);
      return false;
    } finally {
      _refreshing = null;
    }
  }
}
```

> 💡 **핵심 엣지케이스 처리**:
> - **mutex(`_refreshing`)**: 검사 중 여러 API 가 동시에 401을 받아도 refresh 는 1회만 호출
> - **`retried` 플래그**: refresh 후 재시도한 요청이 또 401 받으면 무한루프 방지
> - **`/auth/refresh` 경로 제외**: refresh 자체가 401 받으면 그대로 로그아웃 처리
> - **refresh 토큰까지 만료**: tokenStorage clear 후 로그인 화면 라우팅

### 5-2. `lib/core/network/dio_client.dart` 에 등록

```dart
final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final dio = Dio(BaseOptions(baseUrl: kBaseUrl));
  dio.interceptors.add(AuthInterceptor(dio, tokenStorage));  // 19번에서 강화한 버전
  return dio;
});
```

### 5-3. 로그인 화면 라우팅 자동화

`tokenStorage.clear()` 후 자동으로 로그인 화면으로 이동하려면 `authStateProvider` 가 토큰 변화를 listen 해야 합니다.

```dart
// lib/features/auth/presentation/providers/auth_state_provider.dart
final authStateProvider = StreamProvider<bool>((ref) async* {
  final storage = ref.watch(tokenStorageProvider);
  await for (final hasToken in storage.tokenStream()) {
    yield hasToken;
  }
});

// lib/core/router/app_router.dart
GoRouter buildRouter(Ref ref) => GoRouter(
  redirect: (ctx, state) {
    final isLoggedIn = ref.read(authStateProvider).valueOrNull ?? false;
    if (!isLoggedIn && !state.matchedLocation.startsWith('/login')) {
      return '/login';
    }
    return null;
  },
  // ...
);
```

`TokenStorage.tokenStream()` 은 토큰 변화를 emit (저장 시 true, clear 시 false).

---

## 6. 동작 확인

### 6-1. MDM 배포
1. 18번 워크플로로 새 APK 빌드 → MDM 관리자가 업로드
2. 파일럿 단말기 5대 → 자동 설치 확인 (대기 시간 ~10분)
3. 앱 실행 → 16번 OTA 로 최신 모델 다운로드 → 17번 양품 샘플링·오프라인 큐 정상 동작
4. MDM 콘솔에서 디바이스별 설치 성공률 95% 이상

### 6-2. JWT 자동 갱신
1. **access_token 만료 시뮬레이션**: backend `.env` 에서 `ACCESS_TOKEN_EXPIRE_MINUTES=1` 로 임시 변경 → 앱에서 1분 후 API 호출 → 401 즉시 → 사용자에게 보이지 않게 자동 refresh → 정상 응답
2. **동시 401**: 여러 API 동시 호출 중 만료 → refresh 1회만 호출되는지 backend 로그로 확인
3. **refresh 만료**: backend `.env` 에서 `REFRESH_TOKEN_EXPIRE_DAYS=0` 로 변경 후 access 도 만료 → 자동 로그아웃 → 로그인 화면

---

## 자주 발생하는 오류와 해결

### MDM 이 APK 설치 거부 ("App not allowed by your organization")
- MDM 정책에서 "Unknown sources" 허용 필요. 또는 APK 서명 인증서를 MDM 에 화이트리스트 등록
- Android Enterprise 모드라면 Managed Google Play 사용 필요 — Play Console 등록 후 sideload 방식 변경

### 무한 refresh 루프 (CPU 100%)
- `retried` 플래그가 누락된 경우. 재시도 요청에 `extra: {'retried': true}` 명시 확인
- refresh 응답이 200 인데 토큰 저장 실패 — `tokenStorage.writeAccessToken` 의 await 누락 점검

### refresh 동시 호출로 backend 가 같은 refresh_token 두 번 받아 두 번째 거부
- mutex(`_refreshing`) 누락. 인터셉터 코드의 `if (_refreshing != null) return _refreshing!.future;` 확인

### MDM 설치는 됐는데 앱이 실행 즉시 크래시
- 18번 TFLite 검증 step 통과한 APK 인지 확인. 누락된 경우 `pubspec.yaml` `flutter.assets:` 점검
- OTA 가 잘못된 .tflite 다운로드 가능성 — SHA-256 불일치 시 fallback 동작(16번) 확인

### Play Console 내부 테스트 — APK 가 "이전 버전"으로 거부
- `versionCode` 가 기존보다 작으면 거부. `android/app/build.gradle` 의 `versionCode` 자동 증가 로직 추가(18번 워크플로에서 `github.run_number` 사용 권장)

---

## ✅ 다음 단계로 가기 전 체크리스트

- [ ] 사내 MDM 에 18번 APK 가 업로드됐다 (또는 Play Console 내부 테스트 등록)
- [ ] 파일럿 단말기에서 **자동 설치** 가 동작했다
- [ ] 자동 설치된 앱이 16번 OTA 로 단일 모델을 받아 정상 추론한다
- [ ] 17번 양품 샘플링·오프라인 큐가 MDM 배포 단말기에서 동작한다
- [ ] `AuthInterceptor` 가 401 → refresh → 재시도 흐름을 자동 처리한다
- [ ] 동시 401 발생 시 refresh 가 1회만 호출된다 (mutex 동작)
- [ ] refresh 도 만료된 경우 자동 로그아웃 + 로그인 화면 라우팅
- [ ] 무한 retry 루프가 없다 (`retried` 플래그 동작)
- [ ] `/auth/refresh` 자체가 401 받으면 즉시 로그아웃 (인터셉터 분기)
- [ ] 16·17·18번에서 만든 흐름이 MDM 배포 단말기에서 모두 동작 (오프라인 큐 flush·OTA 알림 토스트·양품 샘플 S3 업로드)

다음 단계 **[20_4주차_모니터링과_파일럿.md](20_4주차_모니터링과_파일럿.md)** 로 이동하세요.
