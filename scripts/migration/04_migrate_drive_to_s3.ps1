# Google Drive → S3 마이그레이션 (rclone copy + check)
#
# 사용:
#   ./04_migrate_drive_to_s3.ps1 -Target models   -DryRun   # 시뮬레이션
#   ./04_migrate_drive_to_s3.ps1 -Target models             # 실제 실행 (copy + check)
#   ./04_migrate_drive_to_s3.ps1 -Target datasets -CheckOnly # 이전 결과만 재검증
#
# 사전: 03_rclone_setup.md에 따라 `gdrive`, `s3` remote 설정 완료.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("models", "datasets", "docs", "archive")]
    [string]$Target,

    [switch]$DryRun,
    [switch]$CheckOnly,

    [int]$Transfers = 8,
    [int]$Checkers = 16
)

$ErrorActionPreference = "Stop"

# ⚠️ 본인 Drive의 실제 폴더 이름에 맞게 수정하세요.
# 키 = Target, 값 = Drive 쪽 경로 (rclone 표기: `gdrive:폴더명`).
$Sources = @{
    models   = "gdrive:tflite-models"
    datasets = "gdrive:학습데이터셋"
    docs     = "gdrive:매뉴얼"
    archive  = "gdrive:백업"
}

$Destinations = @{
    models   = "s3:lng-inspection-models"
    datasets = "s3:lng-inspection-datasets/raw"
    docs     = "s3:lng-inspection-docs"
    archive  = "s3:lng-inspection-archive"
}

$src = $Sources[$Target]
$dst = $Destinations[$Target]

Write-Host "=== $Target ===" -ForegroundColor Cyan
Write-Host "  source: $src"
Write-Host "  dest:   $dst"

# 소스 크기 미리보기 (의도치 않게 큰 폴더를 옮기는 사고 방지)
Write-Host ""
Write-Host "소스 크기 확인 중..." -ForegroundColor Yellow
rclone size $src

if ($CheckOnly) {
    Write-Host ""
    Write-Host "검증 모드 — 크기만 비교" -ForegroundColor Yellow
    rclone check $src $dst --size-only
    return
}

$copyArgs = @(
    "copy", $src, $dst,
    "--progress",
    "--transfers", $Transfers,
    "--checkers", $Checkers,
    "--s3-no-check-bucket",        # 버킷 존재 확인 호출 절약
    "--retries", "5",
    "--low-level-retries", "10",
    "--stats", "30s"
)

if ($DryRun) {
    $copyArgs += "--dry-run"
    Write-Host ""
    Write-Host "[DRY-RUN] 실제 복사 없음 — 옮겨질 파일만 표시" -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "복사 시작 (Ctrl+C로 중단 가능, 재실행 시 이어받기)" -ForegroundColor Green
}

rclone @copyArgs

if ($DryRun) { return }

Write-Host ""
Write-Host "무결성 검증 (크기 기준)..." -ForegroundColor Yellow
rclone check $src $dst --size-only

Write-Host ""
Write-Host "완료. 다음 단계:" -ForegroundColor Cyan
if ($Target -eq "models") {
    Write-Host "  - 모델_레지스트리.파일_경로 / 파일_해시 갱신 (README §마이그레이션 후 체크)" -ForegroundColor Cyan
}
Write-Host "  - Drive 원본은 30일 이상 보관 후 삭제 (롤백 여유)" -ForegroundColor Cyan
