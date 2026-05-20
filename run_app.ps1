$ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi" -ErrorAction SilentlyContinue).IPAddress
if (-not $ip) {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "이더넷" -ErrorAction SilentlyContinue).IPAddress
}
if (-not $ip) {
    Write-Error "IP를 찾을 수 없습니다."
    exit 1
}
$apiUrl = "http://" + $ip + ":8000/api"
$defineArg = "--dart-define=API_BASE_URL=" + $apiUrl
Write-Host "감지된 IP: $ip"
Write-Host "API URL: $apiUrl"
Set-Location "$PSScriptRoot\inspection_app"
flutter run $defineArg