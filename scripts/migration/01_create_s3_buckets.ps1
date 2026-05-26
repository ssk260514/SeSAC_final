# 버킷 생성 — ap-northeast-2, Block Public Access ON, Versioning ON, SSE-S3 암호화.
# 멱등(idempotent): 이미 존재하는 버킷은 건너뛰고 정책만 재적용.
#
# 사용:
#   ./01_create_s3_buckets.ps1                 # 4개 신규 버킷 생성
#   ./01_create_s3_buckets.ps1 -WhatIf         # 시뮬레이션만

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Region = "ap-northeast-2",
    [string[]]$Buckets = @(
        "lng-inspection-models",
        "lng-inspection-datasets",
        "lng-inspection-docs",
        "lng-inspection-archive"
    )
)

$ErrorActionPreference = "Stop"

function Test-BucketExists([string]$name) {
    aws s3api head-bucket --bucket $name 2>$null
    return $LASTEXITCODE -eq 0
}

foreach ($b in $Buckets) {
    Write-Host "=== $b ===" -ForegroundColor Cyan

    if (Test-BucketExists $b) {
        Write-Host "  (이미 존재) 정책만 재적용" -ForegroundColor Yellow
    }
    else {
        if ($PSCmdlet.ShouldProcess($b, "create-bucket in $Region")) {
            # ap-northeast-2는 us-east-1과 달리 LocationConstraint 필수
            aws s3api create-bucket `
                --bucket $b `
                --region $Region `
                --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
            Write-Host "  생성 완료" -ForegroundColor Green
        }
    }

    # Block Public Access (4개 옵션 전부 ON)
    aws s3api put-public-access-block `
        --bucket $b `
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" | Out-Null

    # Versioning 활성화 — 모델/데이터 실수 삭제 보호
    aws s3api put-bucket-versioning `
        --bucket $b `
        --versioning-configuration Status=Enabled | Out-Null

    # 기본 SSE-S3 암호화 (KMS가 필요하면 별도 설정)
    aws s3api put-bucket-encryption `
        --bucket $b `
        --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}' | Out-Null

    Write-Host "  BPA / Versioning / SSE 적용 완료" -ForegroundColor Green
}

Write-Host ""
Write-Host "다음 단계: 02_iam_policy_*.json 을 IAM에 생성하고 키에 부착" -ForegroundColor Cyan
