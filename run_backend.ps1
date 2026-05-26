# Backend uvicorn 기동 스크립트 (--reload 활성화).
# 코드 수정 시 자동 리로드되어 "옛 코드가 계속 도는" 사고 방지.
# 별도 터미널에서 실행: .\run_backend.ps1

$ErrorActionPreference = "Stop"

# 1) venv 확인
$pythonExe = "$PSScriptRoot\backend\.venv\Scripts\python.exe"
if (-not (Test-Path $pythonExe)) {
    Write-Error "venv 가 없습니다: $pythonExe. 먼저 backend/.venv 를 생성하세요."
    exit 1
}

# 2) 포트 8000 점유 사전 체크 — 옛 uvicorn 남아있으면 WinError 10013 으로 죽기 전에 안내
$conn = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
if ($conn) {
    $pidOnPort = $conn.OwningProcess
    $proc = Get-Process -Id $pidOnPort -ErrorAction SilentlyContinue
    Write-Host "포트 8000 이 이미 점유되어 있습니다 (PID=$pidOnPort, $($proc.ProcessName))." -ForegroundColor Yellow
    Write-Host "옛 uvicorn 일 가능성이 높습니다. 종료하려면:" -ForegroundColor Yellow
    Write-Host "  Stop-Process -Id $pidOnPort -Force" -ForegroundColor Cyan
    exit 1
}

Set-Location "$PSScriptRoot\backend"
Write-Host "uvicorn 기동 (http://0.0.0.0:8000, --reload)..." -ForegroundColor Green
& $pythonExe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
