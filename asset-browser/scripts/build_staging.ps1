# Build Kumiho Browser - Staging
# Uses staging control plane

Write-Host "Building Kumiho Browser (Staging)..." -ForegroundColor Cyan

flutter build windows `
    --release `
    --dart-define=ENVIRONMENT=staging `
    --dart-define=CONTROL_PLANE_URL=https://control-staging.kumiho.cloud

Write-Host "Build complete! Output: build\windows\x64\runner\Release\" -ForegroundColor Green
