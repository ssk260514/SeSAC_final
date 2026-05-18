<#
.SYNOPSIS
  단일 통합 모델(30클래스) 정합성 자동 회귀 검증 — Windows PowerShell 판

.DESCRIPTION
  영향 분석서 `명세서/계획 변경 내용.md` §검증 + 본 plan 작업 0~B의 검증 항목을
  자동 grep 으로 회귀 검증한다. 위반 0건이면 exit 0, 1건이라도 있으면 위반 위치
  를 모두 출력하고 exit 1.

.NOTES
  - 명세서/tutorial/ 폴더는 사용자 결정 §C "완전 제외"이므로 검증에서 제외
  - .venv·node_modules·build·.dart_tool 등 의존성 산출물은 검증 제외
  - macOS/Linux 동일 검증은 `check_single_model_integrity.sh` 사용

.EXAMPLE
  PS> .\scripts\check_single_model_integrity.ps1
  ✅ All checks passed (0 violations)

.EXAMPLE  (위반 발생 시)
  PS> .\scripts\check_single_model_integrity.ps1
  ❌ FAIL: 2 violations found
    [surface_v1] tutorial\01_개발환경_셋업.md:42
    [startsWith('표면양품-')] inspection_app\lib\...
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$violations = New-Object System.Collections.Generic.List[string]

# 제외할 경로 패턴
$excludePatterns = @(
    '\\\.venv\\',
    '\\\.dart_tool\\',
    '\\node_modules\\',
    '\\build\\',
    '\\android\\\.gradle\\',
    '\\android\\build\\',
    '\\명세서\\tutorial\\',           # 사용자 결정 §C: 완전 제외
    '\\명세서\\계획 변경 내용\.md$',  # 영향 분석서 자체는 before 인용 보존
    '\\\.claude\\plans\\',            # 본 plan 파일은 검증 대상 아님
    '\\scripts\\check_single_model_integrity\.(ps1|sh)$',  # 본 스크립트 자기 자신
    '\\backend\\app\\SINGLE_MODEL_GUIDE\.md$'              # 가이드 안내 문장 허용
)

function Test-ShouldExclude {
    param([string]$Path)
    foreach ($pat in $excludePatterns) {
        if ($Path -match $pat) { return $true }
    }
    return $false
}

function Invoke-PatternScan {
    param(
        [string]$Pattern,
        [string]$ViolationLabel,
        [string[]]$AllowSubstrings = @()
    )
    $files = Get-ChildItem -Path $ProjectRoot -Recurse -File `
        -Include *.md, *.py, *.dart, *.sql, *.yaml, *.yml, *.ts, *.tsx, *.js -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if (Test-ShouldExclude -Path $f.FullName) { continue }
        $matches = Select-String -Path $f.FullName -Pattern $Pattern -AllMatches -ErrorAction SilentlyContinue
        foreach ($m in $matches) {
            $line = $m.Line
            $allowed = $false
            foreach ($allow in $AllowSubstrings) {
                if ($line -match $allow) { $allowed = $true; break }
            }
            if (-not $allowed) {
                $rel = $f.FullName.Substring($ProjectRoot.Length).TrimStart('\')
                $violations.Add(("  [{0}] {1}:{2}" -f $ViolationLabel, $rel, $m.LineNumber))
            }
        }
    }
}

Write-Host "🔍 Single Model Integrity Check" -ForegroundColor Cyan
Write-Host "   Project root: $ProjectRoot" -ForegroundColor Gray
Write-Host ""

# Check 1: surface_v1 잔재 (단일 모델 = best_model_v5_datamatch_full)
# 허용: 단일모델 안내 문장 (예: "surface_v1 전면 폐기" / "surface_v1 → best_model" 등)
Invoke-PatternScan -Pattern 'surface_v1' `
    -ViolationLabel 'surface_v1' `
    -AllowSubstrings @(
        '전면 폐기',
        '→.*best_model_v5',
        '`surface_v1`.*전.*폐기',
        'surface_v1.*\(구|이전|legacy|구버전\)'
    )

# Check 2: '표면양품-' 접두사 하드코딩 (양품 판별은 .contains('양품') / '양품' in)
# 허용: 클래스 라벨 데이터 (예: "표면양품-도장" 라는 30클래스 중 하나)
Invoke-PatternScan -Pattern "\.startsWith\(['""]표면양품-" `
    -ViolationLabel "startsWith('표면양품-')"
Invoke-PatternScan -Pattern "\.startswith\(['""]표면양품-" `
    -ViolationLabel "startswith('표면양품-')"

# Check 3: ?process_id / ?process= 쿼리 파라미터 (OTA-001 단일 모델 — 파라미터 없음)
Invoke-PatternScan -Pattern '\?process_id=' `
    -ViolationLabel '?process_id='
Invoke-PatternScan -Pattern '\?process=surface' `
    -ViolationLabel '?process=surface'

# Check 4: 6공정 모델 분기 표현
Invoke-PatternScan -Pattern '공정별로 6개 모델' `
    -ViolationLabel '공정별로 6개 모델'
Invoke-PatternScan -Pattern '6공정 × 30' `
    -ViolationLabel '6공정 × 30+유형'
Invoke-PatternScan -Pattern '나머지 5공정.*학습' `
    -ViolationLabel '나머지 5공정 학습'

# Check 5: 30클래스 정합 — 핵심 라벨 4곳 모두 "29":"폼스프레이양품-우레탄폼" 또는 동등 표현 존재 확인
$thirtiethLabel = '폼스프레이양품-우레탄폼'
$thirtiethFiles = @(
    'backend\sql\002_seed.sql',
    'tutorial\02_백엔드_기반_구축.md',
    'tutorial\09_화면5_카메라_촬영.md',
    'tutorial\14_2주차_백엔드_RAG_정밀분석.md'
)
foreach ($f in $thirtiethFiles) {
    $full = Join-Path $ProjectRoot $f
    if (-not (Test-Path $full)) {
        $violations.Add(("  [30클래스 정합 누락] {0} (파일 없음)" -f $f))
        continue
    }
    if (-not (Select-String -Path $full -Pattern $thirtiethLabel -Quiet)) {
        $violations.Add(("  [30클래스 정합 누락] {0} (29번 라벨 '{1}' 없음)" -f $f, $thirtiethLabel))
    }
}

# Check 6: best_model_v5_datamatch_full 등장 확인 (핵심 7개 파일)
$bestModelFiles = @(
    'backend\sql\002_seed.sql',
    'tutorial\02_백엔드_기반_구축.md',
    'tutorial\13_2주차_TFLite_단말_추론.md',
    'tutorial\14_2주차_백엔드_RAG_정밀분석.md',
    'tutorial\16_3주차_모델OTA_Firebase.md',
    'inspection_app\SINGLE_MODEL_GUIDE.md',
    '명세서\제품_정의서.md'
)
foreach ($f in $bestModelFiles) {
    $full = Join-Path $ProjectRoot $f
    if (-not (Test-Path $full)) {
        $violations.Add(("  [best_model 누락] {0} (파일 없음)" -f $f))
        continue
    }
    if (-not (Select-String -Path $full -Pattern 'best_model_v5_datamatch_full' -Quiet)) {
        $violations.Add(("  [best_model 누락] {0} (모델 파일명 없음)" -f $f))
    }
}

# Check 7: RAG 공정_ID 조건 유지 (매뉴얼 공정 범위 한정)
$ragKeepFiles = @(
    'backend\sql\001_schema.sql',     # idx_manual_process
    '명세서\기능_명세서.md',          # WHERE 공정_ID
    '명세서\schema_diagram.md'        # 매뉴얼 공정_ID FK
)
foreach ($f in $ragKeepFiles) {
    $full = Join-Path $ProjectRoot $f
    if (-not (Test-Path $full)) {
        $violations.Add(("  [RAG 공정_ID 누락] {0} (파일 없음)" -f $f))
        continue
    }
    $hasIdx = Select-String -Path $full -Pattern 'idx_manual_process' -Quiet
    $hasWhere = Select-String -Path $full -Pattern '매뉴얼.*공정_ID|공정_ID.*매뉴얼|FROM 매뉴얼' -Quiet
    if (-not ($hasIdx -or $hasWhere)) {
        $violations.Add(("  [RAG 공정_ID 누락] {0} (매뉴얼 공정_ID 조건/인덱스 없음)" -f $f))
    }
}

# 결과 출력
Write-Host ""
if ($violations.Count -eq 0) {
    Write-Host "✅ All checks passed (0 violations)" -ForegroundColor Green
    Write-Host "   - surface_v1 잔재: 0건" -ForegroundColor Green
    Write-Host "   - startsWith('표면양품-') 하드코딩: 0건" -ForegroundColor Green
    Write-Host "   - ?process_id / ?process=surface: 0건" -ForegroundColor Green
    Write-Host "   - 공정별 6모델 분기 표현: 0건" -ForegroundColor Green
    Write-Host "   - 30클래스 4자 정합 (sql/002·tutorial/02·09·14): OK" -ForegroundColor Green
    Write-Host "   - best_model_v5_datamatch_full 7개 파일 존재: OK" -ForegroundColor Green
    Write-Host "   - RAG 매뉴얼.공정_ID 조건 유지: OK" -ForegroundColor Green
    exit 0
} else {
    Write-Host ("❌ FAIL: {0} violations found" -f $violations.Count) -ForegroundColor Red
    foreach ($v in $violations) {
        Write-Host $v -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "📖 참고: `명세서/계획 변경 내용.md` §검증, plan file 작업 1-A" -ForegroundColor Gray
    exit 1
}
