$ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi" -ErrorAction SilentlyContinue).IPAddress
if (-not $ip) {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "이더넷" -ErrorAction SilentlyContinue).IPAddress
}
if (-not $ip) {
    Write-Error "IP를 찾을 수 없습니다."
    exit 1
}
$serverBaseUrl = "http://" + $ip + ":8000"
$apiUrl        = $serverBaseUrl + "/api"
$defineArg     = "--dart-define=API_BASE_URL=" + $apiUrl

# backend/.env의 SERVER_BASE_URL을 현재 IP로 자동 갱신
$envFile = "$PSScriptRoot\backend\.env"
if (Test-Path $envFile) {
    $envContent = Get-Content $envFile -Raw
    if ($envContent -match 'SERVER_BASE_URL=') {
        $envContent = $envContent -replace 'SERVER_BASE_URL=.*', "SERVER_BASE_URL=$serverBaseUrl"
    } else {
        $envContent = $envContent.TrimEnd() + "`nSERVER_BASE_URL=$serverBaseUrl`n"
    }
    Set-Content $envFile $envContent -NoNewline -Encoding utf8
    Write-Host "backend/.env SERVER_BASE_URL → $serverBaseUrl" -ForegroundColor Cyan
}

Write-Host "감지된 IP: $ip"
Write-Host "API URL: $apiUrl"
Set-Location "$PSScriptRoot\inspection_app"
flutter run $defineArg --no-pub