# 18. 3주차 — CI/CD 자동 빌드 (Flutter APK + 백엔드 Docker)

> **이 단계가 끝나면**: `main` 브랜치에 푸시할 때마다 Flutter APK가 자동으로 빌드·서명되어 아티팩트로 보관되고, 백엔드 코드는 Docker 이미지로 자동 빌드됩니다. 매번 손으로 `flutter build apk` 칠 필요가 없습니다.
>
> **예상 시간**: 3시간

> ⚠️ **단일 모델 전제**: 본 단계는 빌드 자동화이므로 모델 구조와 무관합니다. 다만 APK 안에 번들된 `assets/models/best_model_v5_datamatch_full.tflite` 가 정상 포함되는지(빌드 산출물 크기 확인)는 단일 모델 정합 검증의 일부입니다.

> **참조 명세서**: [`아키텍처_명세서.md`](../명세서/아키텍처_명세서.md) Part 4 3주차 (L169), [`제품_정의서.md`](../명세서/제품_정의서.md) §4-2 `[3주차 도입]` 자동 빌드, [`tutorial/15_빌드_배포_및_트러블슈팅.md`](15_빌드_배포_및_트러블슈팅.md) (수동 빌드 기준)

---

## 1. 왜 CI/CD 인가

- 1·2주차에는 `flutter build apk --release` 를 손으로 돌렸지만 3주차부터 빌드 주기가 급격히 늘어남(OTA, 양품 샘플링, 오프라인 큐 등 변경 잦음)
- 사람이 빌드하면 **서명 키가 노출되기 쉽고**(키스토어를 로컬에서 들고 다님) 환경 차이로 인한 빌드 실패가 발생
- CI/CD = 정해진 워크플로로 빌드 → 서명 → 아티팩트 업로드 → 알림 → MDM 배포 준비. 사람은 결과만 확인

본 단계에서는 **GitHub Actions** 기반(무료 등급으로 충분) 흐름을 작성합니다. 대안으로 **Codemagic** (Flutter 전용 SaaS, 무료 등급 있음) 도 같은 단계로 구성 가능합니다 (§4 비교 박스 참조).

```
git push origin main
    │
    ▼
GitHub Actions trigger
    │
    ├─ Job: flutter-build
    │   ├─ checkout
    │   ├─ Flutter SDK setup
    │   ├─ flutter pub get
    │   ├─ flutter analyze + test
    │   ├─ keystore 복원 (Base64 시크릿 → 파일)
    │   ├─ flutter build apk --release
    │   └─ artifact upload (app-release.apk)
    │
    └─ Job: backend-docker (선택)
        ├─ checkout
        ├─ Docker buildx
        └─ ghcr.io 푸시 (또는 ECR)
```

---

## 2. 사전 준비

- 15번에서 만든 `upload-keystore.jks` 와 `key.properties` 가 로컬에 있음
- GitHub 저장소가 만들어져 있음 (private 권장)
- 19번 MDM 배포는 본 단계 산출물(APK 아티팩트)을 사용. 본 단계만으로는 자동 설치되지 않음

---

## 3. Keystore 를 GitHub Secrets 로

키스토어를 그대로 커밋하면 안 되므로 Base64 인코딩 후 Secrets 에 보관합니다.

**Windows**
```powershell
$keystorePath = "C:\Users\yejin\Desktop\sesac_final\UsersyejinDesktopSeSAC_final\inspection_app\android\app\upload-keystore.jks"
[Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath)) | Set-Clipboard
Write-Output "Base64 키스토어가 클립보드에 복사됐습니다."
```

> 🍏 **macOS**
> ```bash
> base64 -i ~/Desktop/final/inspection_app/android/app/upload-keystore.jks | pbcopy
> echo "Base64 키스토어가 클립보드에 복사됐습니다."
> ```

GitHub 저장소 → Settings → Secrets and variables → Actions → New repository secret 으로 다음 4개 등록:

| Secret 이름 | 값 |
|---|---|
| `KEYSTORE_BASE64` | 위에서 복사한 Base64 문자열 |
| `KEYSTORE_PASSWORD` | 15번에서 설정한 keystore 비밀번호 |
| `KEY_PASSWORD` | 키 별칭 비밀번호 (보통 동일) |
| `KEY_ALIAS` | `upload` (15번 기준) |

> ⚠️ Secrets 는 로그에 마스킹되지만 echo·print 로 노출되지 않도록 워크플로에서 직접 출력 금지.

---

## 4. GitHub Actions 워크플로

### 4-1. `.github/workflows/flutter-build.yml` (신규)

```yaml
name: Flutter Android Build

on:
  push:
    branches: [main]
    paths:
      - 'inspection_app/**'
      - '.github/workflows/flutter-build.yml'
  workflow_dispatch:  # 수동 트리거도 허용

jobs:
  build-apk:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: inspection_app

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.x'
          channel: stable

      - name: Cache pub dependencies
        uses: actions/cache@v4
        with:
          path: |
            ~/.pub-cache
            inspection_app/.dart_tool
          key: pub-${{ runner.os }}-${{ hashFiles('inspection_app/pubspec.lock') }}

      - name: Flutter pub get
        run: flutter pub get

      - name: Static analysis
        run: flutter analyze

      - name: Run tests
        run: flutter test

      - name: Restore keystore from secret
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/upload-keystore.jks
          cat > android/key.properties <<EOF
          storePassword=${{ secrets.KEYSTORE_PASSWORD }}
          keyPassword=${{ secrets.KEY_PASSWORD }}
          keyAlias=${{ secrets.KEY_ALIAS }}
          storeFile=upload-keystore.jks
          EOF

      - name: Build release APK
        run: flutter build apk --release

      - name: Verify TFLite asset bundled
        run: |
          unzip -l build/app/outputs/flutter-apk/app-release.apk \
            | grep best_model_v5_datamatch_full.tflite \
            || (echo "❌ 단일 모델 .tflite 누락" && exit 1)

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-release-${{ github.sha }}
          path: inspection_app/build/app/outputs/flutter-apk/app-release.apk
          retention-days: 30
```

> 💡 **왜 "TFLite asset 검증" 단계가 있나**: 빌드는 성공했는데 `pubspec.yaml` 의 `flutter.assets` 등록 누락으로 모델이 빠진 APK가 배포되면 앱이 런타임에 깨집니다. 빌드 단계에서 단일 모델 파일 포함 여부를 자동 검증해 사고를 막습니다 (`계획 변경 내용.md` §7 inspection_app 가이드와 정합).

### 4-2. (선택) 백엔드 Docker 빌드 `.github/workflows/backend-docker.yml`

```yaml
name: Backend Docker Build

on:
  push:
    branches: [main]
    paths:
      - 'backend/**'
      - '.github/workflows/backend-docker.yml'

jobs:
  docker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write   # ghcr.io 푸시 권한

    steps:
      - uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set up Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build & push
        uses: docker/build-push-action@v6
        with:
          context: ./backend
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/lng-inspection-backend:${{ github.sha }}
            ghcr.io/${{ github.repository_owner }}/lng-inspection-backend:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

`backend/Dockerfile` 이 없다면 신규 작성:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
COPY sql/ ./sql/
ENV PYTHONUNBUFFERED=1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## 5. Codemagic 대안 (Flutter 전용)

Flutter 전용 SaaS 가 익숙하다면 Codemagic 도 같은 흐름을 더 적은 YAML 로 작성할 수 있습니다. `codemagic.yaml` 예시:

```yaml
workflows:
  android-release:
    name: Android Release Build
    instance_type: mac_mini_m2
    environment:
      android_signing:
        - lng_keystore        # Codemagic UI에서 등록한 키스토어 참조
      flutter: stable
    scripts:
      - cd inspection_app && flutter pub get
      - cd inspection_app && flutter analyze
      - cd inspection_app && flutter test
      - cd inspection_app && flutter build apk --release
    artifacts:
      - inspection_app/build/**/outputs/**/*.apk
```

| 항목 | GitHub Actions | Codemagic |
|---|---|---|
| 비용 | public repo 무료, private 월 2000분 무료 | 월 500분 무료 |
| 설정 | YAML 직접 작성 | UI + YAML |
| Flutter 최적화 | 일반 — 직접 캐싱 설정 | Flutter 특화 — 자동 캐싱 |
| MDM·Firebase 연동 | 직접 작성 | 내장 통합 있음 |

본 가이드는 **GitHub Actions** 를 기본으로 합니다(저장소가 이미 GitHub인 경우 추가 가입 불필요).

---

## 6. 동작 확인

1. `inspection_app/lib/main.dart` 에 사소한 변경 push → `Actions` 탭에서 워크플로 시작 확인
2. 모든 step 녹색 (analyze/test/build) → 마지막 step "Upload APK artifact" 의 다운로드 링크 생성
3. APK 다운로드 → 실기기 설치 → 앱 정상 실행 (15번 수동 빌드 결과와 동일)
4. **TFLite 자동 검증** step 통과 — `best_model_v5_datamatch_full.tflite` 가 APK에 포함됨
5. (선택) 백엔드 Docker: `ghcr.io/{org}/lng-inspection-backend:{sha}` 이미지 푸시 확인

```powershell
# 로컬에서 GHCR 이미지 받기 (테스트)
docker pull ghcr.io/<org>/lng-inspection-backend:latest
docker run --rm -p 8000:8000 --env-file backend/.env ghcr.io/<org>/lng-inspection-backend:latest
```

---

## 자주 발생하는 오류와 해결

### "Keystore was tampered with, or password was incorrect"
- `KEYSTORE_BASE64` 가 잘림. PowerShell 출력 끝 개행 포함 여부 확인 — `Set-Clipboard` 사용 권장
- `KEYSTORE_PASSWORD`/`KEY_PASSWORD` Secrets 값에 오타나 공백

### Flutter 캐시 무효화로 매번 pub get 가 10분 이상
- `actions/cache@v4` 의 key가 `pubspec.lock` 해시 기반인지 확인 (위 워크플로에 포함)

### TFLite asset 검증 step 실패
- `pubspec.yaml` 의 `flutter.assets:` 에 `assets/models/` 등록 누락
- `assets/models/best_model_v5_datamatch_full.tflite` 파일이 실제로 커밋되어 있는지

### Docker build OOM (Out of Memory)
- runner 메모리 한계. multi-stage build 또는 `--build-arg`로 PyTorch 같은 무거운 라이브러리 별도 stage 분리

### `flutter analyze` 가 무수한 lint 경고로 실패
- 1주차에 미루던 lint 정리 필요. 또는 `analysis_options.yaml` 의 `analyzer.exclude:` 에 자동 생성 파일 추가

---

## ✅ 다음 단계로 가기 전 체크리스트

- [ ] `.github/workflows/flutter-build.yml` 가 main push 시 자동 실행된다
- [ ] APK 아티팩트가 `Actions → workflow run → Artifacts` 에서 다운로드 가능하다
- [ ] **TFLite 자동 검증** step 이 단일 모델(`best_model_v5_datamatch_full.tflite`) 포함을 강제한다
- [ ] keystore Base64 가 Secrets 로만 보관되고 저장소·로그에 노출되지 않는다
- [ ] (선택) 백엔드 Docker 이미지가 GHCR/ECR 에 자동 푸시된다
- [ ] `flutter analyze`·`flutter test` 가 빌드 전에 게이트 역할을 한다 (실패 시 빌드 중단)
- [ ] 19번 MDM 배포에 사용할 APK 아티팩트 다운로드 URL 패턴이 정해졌다
- [ ] 16번 OTA 와 본 빌드의 관계 확인 — APK 안의 .tflite 는 "초기 번들", OTA 는 "이후 갱신". 두 흐름이 같은 단일 모델을 가리킨다

다음 단계 **[19_4주차_MDM배포_JWT안정화.md](19_4주차_MDM배포_JWT안정화.md)** 로 이동하세요.
