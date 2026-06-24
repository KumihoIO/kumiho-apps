# Build Kumiho Browser - Production
# Uses production control plane (control.kumiho.cloud)

Write-Host "Building Kumiho Browser (Production)..." -ForegroundColor Cyan

flutter build windows `
    --release `
    --dart-define=ENVIRONMENT=production `
    --dart-define=CONTROL_PLANE_URL=https://control.kumiho.cloud

Write-Host "Build complete! Output: build\windows\x64\runner\Release\" -ForegroundColor Green
Write-Host ""
Write-Host "Ready for installer packaging!" -ForegroundColor Yellow
