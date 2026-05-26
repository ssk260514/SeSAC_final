# Google Drive → AWS S3 마이그레이션

GCP 의존성을 제거하고 모든 파일을 AWS S3로 단일화하기 위한 일회성 이전 절차입니다.
**사전 결정 사항**과 배경은 OTA 전환 PoC 토론을 참조하세요.

## 버킷 설계 (용도별 분리)

| 버킷 | 용도 | 누가 쓰는가 |
|---|---|---|
| `lng-inspection-samples` | 양품 샘플 (기존 운영 중, **이 스크립트에서 건드리지 않음**) | 백엔드 PUT |
| `lng-inspection-models` | `.tflite` / `.pth` 모델 (OTA) | 백엔드 GET(presigned), 운영자 PUT |
| `lng-inspection-datasets` | 재학습용 원본/라벨 이미지 | 운영자 PUT, 학습 파이프라인 GET |
| `lng-inspection-docs` | 매뉴얼·명세서 PDF 등 | 운영자 PUT, 백엔드 GET(선택) |
| `lng-inspection-archive` | 기타 백업 | 운영자 PUT |

모든 버킷: `ap-northeast-2`, **Block Public Access ON**, **Versioning ON**, **기본 SSE-S3 암호화**.

## 실행 순서

```powershell
# 0) 사전: AWS CLI 로그인 (관리자 권한)
aws configure   # 또는 SSO

# 1) 버킷 생성
./01_create_s3_buckets.ps1

# 2) IAM 정책 적용 — 콘솔 또는 CLI로 두 정책을 생성하고 각 IAM 사용자/역할에 부착
#    02_iam_policy_backend.json    → 백엔드 서비스 키 (presigned URL 발급용)
#    02_iam_policy_uploader.json   → 운영자 업로드 키 (마이그레이션 + 모델 갱신용)

# 3) rclone 설정 (한 번만)
#    03_rclone_setup.md 참조 — Drive·S3 remote 등록

# 4) 마이그레이션 실행 — 항상 dry-run으로 먼저 확인
./04_migrate_drive_to_s3.ps1 -Target models    -DryRun
./04_migrate_drive_to_s3.ps1 -Target models             # 실제 실행
./04_migrate_drive_to_s3.ps1 -Target datasets  -DryRun
./04_migrate_drive_to_s3.ps1 -Target datasets
./04_migrate_drive_to_s3.ps1 -Target docs      -DryRun
./04_migrate_drive_to_s3.ps1 -Target docs
./04_migrate_drive_to_s3.ps1 -Target archive   -DryRun
./04_migrate_drive_to_s3.ps1 -Target archive
```

## 마이그레이션 후 체크

- [ ] 각 버킷에 파일 수 / 총 용량이 Drive와 일치 (`rclone check` 통과)
- [ ] `모델_레지스트리.파일_경로`를 `s3://lng-inspection-models/...`로 업데이트
- [ ] `모델_레지스트리.파일_해시`를 실제 SHA-256으로 업데이트
- [ ] 앱에서 `/api/model/version` 호출 시 `download_url` 반환되고 다운로드 성공
- [ ] Drive에는 30일 이상 보관 후 삭제 (롤백 여유)
