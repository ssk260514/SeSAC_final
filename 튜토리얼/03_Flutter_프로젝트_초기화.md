# 03. Flutter 프로젝트 초기화 — 폴더 구조와 의존성

> **이 단계가 끝나면**: `inspection_app` Flutter 프로젝트가 생성되어 있고, Clean Architecture 폴더 구조와 필요한 모든 의존성이 설정되어 빈 앱이 에뮬레이터에서 실행됩니다.
>
> **예상 시간**: 1시간

> **참조 명세서**: `frontend/design/CLAUDE.md` §2 (Clean Architecture 폴더 구조), `제품_정의서.md` §7 (기술 스택)

---

## 1. Flutter 프로젝트 생성

PowerShell:

```powershell
cd C:\Users\yejin\Desktop\sesac_final\UsersyejinDesktopSeSAC_final
flutter create --org com.shipyard --platforms android inspection_app
cd inspection_app
```

옵션 설명:
- `--org com.shipyard` — 패키지 이름의 회사 도메인. Android 패키지 ID가 `com.shipyard.inspection_app`이 됩니다.
- `--platforms android` — 안드로이드만 (iOS는 Post-MVP). 나중에 추가하려면 `flutter create --platforms ios .`

VS Code에서 새로 만든 폴더를 엽니다: `File → Open Folder → C:\Users\yejin\Desktop\sesac_final\UsersyejinDesktopSeSAC_final\inspection_app`

---

## 2. Clean Architecture 폴더 구조

`frontend/design/CLAUDE.md` §2의 원칙대로 폴더를 만듭니다.

```
lib/
├── main.dart
├── core/                          ← 공통 인프라
│   ├── network/                   ← Dio 클라이언트, 인터셉터
│   ├── storage/                   ← secure storage 래퍼
│   ├── theme/                     ← Material 3 토큰
│   ├── error/                     ← Failure 클래스
│   └── router/                    ← go_router
├── shared/                        ← 공용 위젯·모델
│   └── widgets/
└── features/                      ← 화면별 모듈 (7개)
    ├── auth/
    │   ├── presentation/
    │   ├── domain/
    │   └── data/
    ├── tank_location/
    │   ├── presentation/
    │   ├── domain/
    │   └── data/
    ├── dashboard/
    │   ├── presentation/
    │   ├── domain/
    │   └── data/
    ├── inspection_history/
    │   ├── presentation/
    │   ├── domain/
    │   └── data/
    ├── capture/
    │   ├── presentation/
    │   ├── domain/
    │   └── data/
    ├── result_review/
    │   ├── presentation/
    │   ├── domain/
    │   └── data/
    └── settings/
        ├── presentation/
        ├── domain/
        └── data/
```

PowerShell 한 줄로 모두 만들기:

```powershell
cd C:\Users\yejin\Desktop\sesac_final\UsersyejinDesktopSeSAC_final\inspection_app\lib
mkdir core, core\network, core\storage, core\theme, core\error, core\router, shared, shared\widgets
$features = @("auth","tank_location","dashboard","inspection_history","capture","result_review","settings")
$layers = @("presentation","domain","data")
foreach ($f in $features) {
  mkdir "features\$f"
  foreach ($l in $layers) { mkdir "features\$f\$l" }
}
```

### 2-1. Clean Architecture 의존성 방향

```
presentation  ──→  domain  ←──  data
   (UI)         (순수 비즈니스)   (구현)
```

- **`domain`은 외부 의존성 0**. Flutter 패키지도 import 금지. 순수 Dart만.
- **`presentation`**과 **`data`** 둘 다 `domain`의 추상(Repository, UseCase)에 의존
- 데이터 흐름: `Widget → Notifier → UseCase → Repository(추상) → RepositoryImpl → DataSource`
- DI: **Riverpod Provider**로 추상 타입에 구현체를 바인딩

처음에는 어렵게 느껴지지만, 06번 단계의 로그인 화면 구현이 **표준 예시**가 됩니다. 그걸 다른 화면에 복제하면 됩니다.

---

## 3. `pubspec.yaml` 의존성

`pubspec.yaml`을 열어서 `dependencies:`와 `dev_dependencies:` 부분을 **다음 내용으로 대체**합니다:

```yaml
name: inspection_app
description: "선박 LNG탱크 부품 품질 검사 AI 앱"
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.5.0
  flutter: ">=3.24.0"

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # 상태관리
  flutter_riverpod: ^2.5.1
  # ⚠️ riverpod_annotation은 06번 단계에서 Riverpod v3 패키지셋으로 함께 추가합니다.
  #    (riverpod_annotation ^2.x + riverpod_generator ^2.x 조합은 Dart 3.7+ 환경에서
  #     analyzer_plugin 버전 충돌로 build_runner가 실행되지 않습니다)

  # 라우팅
  go_router: ^14.2.7

  # 네트워크
  dio: ^5.7.0

  # 저장소
  flutter_secure_storage: ^9.2.2
  sqflite: ^2.3.3
  path_provider: ^2.1.4

  # 카메라·권한
  camera: ^0.11.0
  permission_handler: ^11.3.1
  image: ^4.3.0  # 이미지 전처리용

  # 네트워크 상태
  connectivity_plus: ^6.0.5

  # 이미지 캐싱
  cached_network_image: ^3.4.1

  # 데이터 클래스
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0

  # 유틸리티
  intl: ^0.19.0           # 날짜 포맷
  package_info_plus: ^8.0.2  # 앱 버전
  uuid: ^4.5.0            # client_request_id

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

  # 코드 생성기
  build_runner: ^2.4.13
  freezed: ^2.5.7
  json_serializable: ^6.8.0
  # ⚠️ riverpod_generator, custom_lint, riverpod_lint는 06번 단계에서 추가합니다.
  #    Dart 3.7+ 환경에서 riverpod_generator ^2.x → riverpod_analyzer_utils →
  #    analyzer_plugin 0.12.x가 analyzer 7.x와 비호환되어 build_runner 컴파일 실패.
  #    custom_lint ^0.6.x / ^0.7.x도 freezed_annotation ^2.x와 버전 체인 충돌.

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/models/      # 13번 단계에서 .tflite 추가
  # fonts: (04번 단계에서 추가)
```

### 3-1. assets 폴더 먼저 생성

> ⚠️ `pubspec.yaml`에 `assets/images/`·`assets/models/` 경로를 선언했으므로, **`flutter pub get` 전에** 폴더를 만들어야 VS Code 경고가 뜨지 않습니다.

```powershell
cd C:\Users\yejin\Desktop\sesac_final\UsersyejinDesktopSeSAC_final\inspection_app
mkdir assets, assets\images, assets\models, assets\fonts
```

빈 폴더는 git이 추적 안 하므로 placeholder 파일 하나씩:
```powershell
New-Item assets\images\.gitkeep, assets\models\.gitkeep, assets\fonts\.gitkeep -ItemType File
```

### 3-2. 의존성 설치

PowerShell:
```powershell
flutter pub get
```

처음 실행은 3~5분 걸립니다.

---

## 4. Android 설정 — `AndroidManifest.xml`

`android/app/src/main/AndroidManifest.xml`을 열어 `<manifest>` 태그 안, `<application>` 태그 위에 권한을 추가합니다.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- 인터넷 (API 호출) -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>

    <!-- 카메라 -->
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera" android:required="true"/>

    <application
        android:label="LNG Inspection"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">   <!-- ← dev 전용. http:// 허용 -->

        <activity
            android:name=".MainActivity"
            ... (기존 그대로)
        </activity>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
```

핵심 변경:
1. **권한 4개** 추가
2. `android:label` → "LNG Inspection"
3. **`android:usesCleartextTraffic="true"`** ← dev 환경에서 http://10.0.2.2 호출을 허용 (운영 시에는 https로 바꾸고 이 줄 제거)

---

## 5. minSdkVersion 26 (Android 8+)

`android/app/build.gradle.kts`(또는 `build.gradle`)을 열고 `defaultConfig` 안의 `minSdk`를 찾아 **26**으로:

```kotlin
defaultConfig {
    applicationId = "com.shipyard.inspection_app"
    minSdk = 26                  // ← Android 8 (제품 정의서 §1 단말 사양)
    targetSdk = 34
    versionCode = flutterVersionCode.toInteger()
    versionName = flutterVersionName
}
```

> 💡 **왜 26?** 제품 정의서 §1에 "Android 8 이상" 명시. 그리고 일부 패키지(`camera`, `flutter_secure_storage`)가 minSdk 21 미만에서는 안 돕니다. 26은 90% 이상의 안드로이드 폰을 커버합니다.

---

## 6. `lib/main.dart` 초기화

기존 카운터 앱 예제를 지우고 다음으로 대체:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(
    const ProviderScope(
      child: InspectionApp(),
    ),
  );
}

class InspectionApp extends StatelessWidget {
  const InspectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LNG Inspection',
      theme: ThemeData(useMaterial3: true),
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LNG Inspection')),
      body: const Center(
        child: Text('초기 설정 완료 — 04번 단계에서 라우팅 추가'),
      ),
    );
  }
}
```

핵심:
- **`ProviderScope`** — Riverpod의 최상위 위젯. 모든 Provider를 감쌈
- 화면 구성과 라우팅은 04번에서 추가

---

## 7. 첫 실행 확인

에뮬레이터를 켜고:
```powershell
flutter run
```

또는 VS Code에서 **F5** (디버그 시작).

에뮬레이터 또는 실기기에 **"초기 설정 완료 — 04번 단계에서 라우팅 추가"** 텍스트가 보이면 성공.

---

## 8. build_runner 첫 실행

freezed·json_serializable이 만들어주는 파일들을 미리 한 번 생성해봅니다. 지금은 대상 파일이 없으니 `wrote 0 outputs` 메시지가 나옵니다.

```powershell
dart run build_runner build --delete-conflicting-outputs
```

> 💡 **build_runner가 뭔가요?** `@freezed`, `@JsonSerializable` 같은 어노테이션이 붙은 파일을 보고 **`.freezed.dart`**, **`.g.dart`** 같은 보조 파일을 자동 생성합니다. `@riverpod` 코드 생성은 06번 단계에서 riverpod_generator를 추가한 뒤 사용합니다.

향후 코드 생성 워크플로우:
- 일회성: `dart run build_runner build --delete-conflicting-outputs`
- 파일 변경 시 자동: `dart run build_runner watch --delete-conflicting-outputs` (계속 실행 상태)

---

## 9. `.gitignore` 보강

`inspection_app/.gitignore`에 다음이 포함되어 있는지 확인 (`flutter create`가 기본으로 만들어주지만, 안 들어 있는 항목 추가):

```
# IDE
.vscode/
.idea/

# Flutter
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.pub-cache/
.pub/
build/

# Generated
*.g.dart
*.freezed.dart
# ← 이 둘은 보통은 commit하지만, 프로젝트 정책에 따라 제외 가능

# IDE 캐시
.metadata
```

> 💡 `.g.dart` `.freezed.dart`를 git에 올릴지 말지는 팀 합의 사항입니다. 이 매뉴얼에서는 **올린다** 가정 (CI 없이 PR 리뷰가 쉽도록).

---

## 10. README placeholder 생성 (선택)

각 feature 폴더 안에 한 줄 README를 두면 IDE에서 폴더가 비어도 잘 보입니다.

```powershell
$features = @("auth","tank_location","dashboard","inspection_history","capture","result_review","settings")
foreach ($f in $features) {
  Set-Content -Path "lib\features\$f\README.md" -Value "# $f`n`n화면 모듈 — Clean Architecture (presentation/domain/data)"
}
```

---

## 자주 발생하는 오류와 해결

### `flutter create`가 "Permission denied" 에러
- 다른 프로세스가 폴더를 잡고 있음. VS Code 닫고 재시도

### `flutter pub get` 실패 (network)
- 회사 네트워크에서 pub.dev 막혀있을 수 있음. VPN 또는 IT팀 문의

### Gradle 빌드 실패 ("Unsupported class file major version")
- Java 버전 문제. Android Studio가 설치한 JDK 17을 사용하도록 환경변수 `JAVA_HOME` 설정. 또는 `flutter config --jdk-dir <Android Studio JBR 경로>`

### Gradle 빌드 데몬 OOM 크래시 (RAM ≤ 8GB)
"Gradle build daemon disappeared unexpectedly" 또는 `JVM crash log found: hs_err_pid*.log` 오류.

기본 `android/gradle.properties`의 `-Xmx8G` 설정이 시스템 RAM을 초과해 JVM이 강제 종료됩니다. `android/gradle.properties`를 열고 첫 줄을 수정합니다:

```properties
# 수정 전 (기본값)
org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError

# 수정 후 (RAM 8GB 이하 환경)
org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError
```

### `build_runner` 무한 대기
- `.dart_tool` 폴더 손상 가능. 삭제 후 `flutter pub get` 다시:
  ```powershell
  Remove-Item -Recurse -Force .dart_tool
  flutter pub get
  ```

### 에뮬레이터에서 앱이 흰 화면만 나오고 안 뜸
- `flutter clean` 후 `flutter pub get` → `flutter run`

---

## ✅ 다음 단계로 가기 전 체크리스트

- [ ] `lib/` 아래에 `core/`, `shared/`, `features/` (7개 feature) 폴더가 모두 있다
- [ ] 각 feature 폴더 안에 `presentation/`, `domain/`, `data/` 세 폴더가 있다
- [ ] `pubspec.yaml` 의존성 목록이 Section 3 코드 블록 내용과 일치하고 `flutter pub get`이 성공했다
- [ ] `AndroidManifest.xml`에 INTERNET, CAMERA, ACCESS_NETWORK_STATE 권한이 들어 있다
- [ ] `android/app/build.gradle.kts`의 `minSdk`가 26이다
- [ ] `flutter run`이 에뮬레이터에 "초기 설정 완료" 메시지를 표시한다
- [ ] `dart run build_runner build --delete-conflicting-outputs`가 에러 없이 끝난다 (`wrote 0 outputs` 메시지가 나오는 것이 정상)

다음 단계 **[04_디자인_시스템과_라우팅.md](04_디자인_시스템과_라우팅.md)** 로 이동하세요.
