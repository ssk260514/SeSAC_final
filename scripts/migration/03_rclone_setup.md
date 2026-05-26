# rclone 설정 가이드 (한 번만)

## 설치

```powershell
winget install Rclone.Rclone
rclone version
```

## Drive remote 등록

```powershell
rclone config
```

대화형 프롬프트:
- `n` (새 remote)
- name: `gdrive`
- Storage: `drive`
- `client_id` / `client_secret`: **빈 칸 그대로 Enter** — rclone 내장 클라이언트 사용
  (GCP 프로젝트를 만들지 않아도 됩니다. 대용량에서 rate limit이 걸리면 §하단 참조)
- scope: `2` (drive.readonly) — 읽기만 — 권장
- service_account_file: 빈 칸
- Edit advanced config: `n`
- Use auto config: `y` — 브라우저로 OAuth 동의 (분리된 Google 계정으로 로그인)
- Configure as Shared Drive: `n` (필요시 `y`)
- `y` (저장)

확인:
```powershell
rclone lsd gdrive:        # 최상위 폴더 목록이 보이면 OK
```

## S3 remote 등록

```powershell
rclone config
```

- `n`
- name: `s3`
- Storage: `s3`
- provider: `AWS`
- env_auth: `false`
- access_key_id: `<uploader 키>`
- secret_access_key: `<uploader 시크릿>`
- region: `ap-northeast-2`
- endpoint / location_constraint / acl: 기본
- server_side_encryption: `AES256`
- storage_class: 기본
- Edit advanced: `n`
- `y` (저장)

확인:
```powershell
rclone lsd s3:lng-inspection-models   # 빈 결과(에러 없음) → OK
```

## 폴더 매핑 메모

마이그레이션 실행 전에 Drive의 실제 폴더 이름을 확인하고
`04_migrate_drive_to_s3.ps1` 상단의 `$Sources` 해시테이블을 본인 환경에 맞게 수정하세요.

```powershell
rclone lsd gdrive:                          # 최상위에서 후보 폴더 찾기
rclone lsd "gdrive:학습데이터셋"            # 하위 확인
rclone size "gdrive:학습데이터셋"           # 전송량 가늠
```

## rate limit이 걸릴 때 (대용량 데이터셋)

내장 클라이언트는 공유라 Drive API 한도가 빠르게 소진될 수 있습니다.
이 경우에만 본인 OAuth 클라이언트를 만들어 `client_id` / `client_secret`을 채우세요.

> ⚠️ "GCP를 쓰지 않는다"는 목표에 어긋난다고 느낄 수 있으나, 이는 **본인 Drive 읽기 권한**을 위한
> 무료 OAuth credential일 뿐 GCP 인프라/과금이 발생하지 않습니다.
> 마이그레이션이 끝나면 OAuth 클라이언트를 삭제하면 흔적이 남지 않습니다.

대안: rate limit이 걸린 파일만 모아 Google Takeout으로 내려받아 S3에 별도 업로드.
