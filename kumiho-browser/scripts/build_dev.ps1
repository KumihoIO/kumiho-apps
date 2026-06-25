# Build Kumiho Browser - Development
# Uses localhost control plane

Write-Host "Building Kumiho Browser (Development)..." -ForegroundColor Cyan

flutter build windows `
    --dart-define=ENVIRONMENT=development `
    --dart-define=CONTROL_PLANE_URL=http://localhost:3000

Write-Host "Build complete! Output: build\windows\x64\runner\Release\" -ForegroundColor Green
