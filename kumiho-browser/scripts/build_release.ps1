Param(
  [Parameter(Mandatory = $false)][ValidateSet('production', 'staging', 'development')][string]$Environment = 'production',
  [Parameter(Mandatory = $false)][switch]$SkipInstaller,
  [Parameter(Mandatory = $false)][switch]$SkipZip,
  [Parameter(Mandatory = $false)][switch]$CleanDist,
  [Parameter(Mandatory = $false)][string]$IsccPath,
  [Parameter(Mandatory = $false)][string]$UpdateGithubOwner,
  [Parameter(Mandatory = $false)][string]$UpdateGithubRepo
)

$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
  throw "This script is intended for Windows (PowerShell). Use flutter build macos/linux on those platforms."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

function Get-ControlPlaneUrl([string]$envName) {
  switch ($envName) {
    'staging' { return 'https://control-staging.kumiho.cloud' }
    'development' { return 'http://localhost:3000' }
    default { return 'https://control.kumiho.cloud' }
  }
}

function Get-AppVersionFromPubspec([string]$pubspecPath) {
  $versionLine = (Get-Content $pubspecPath | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1)
  if (-not $versionLine) {
    throw "Could not determine version from pubspec.yaml"
  }

  $raw = ($versionLine -replace '^version:\s*', '').Trim()

  # Flutter uses: X.Y.Z+N. Inno wants dotted numeric. We map to X.Y.Z.N.
  if ($raw -match '^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$') {
    return "$($Matches[1]).$($Matches[2])"
  }

  return $raw
}

$controlPlaneUrl = Get-ControlPlaneUrl $Environment
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$appVersion = Get-AppVersionFromPubspec $pubspecPath

$distDir = Join-Path $repoRoot 'dist'
$distWindowsDir = Join-Path $distDir 'windows'

if ($CleanDist) {
  if (Test-Path $distDir) {
    Remove-Item -Recurse -Force $distDir
  }
}

New-Item -ItemType Directory -Force -Path $distWindowsDir | Out-Null

Write-Host "Building Kumiho Browser (Windows)" -ForegroundColor Cyan
Write-Host "- Environment: $Environment"
Write-Host "- CONTROL_PLANE_URL: $controlPlaneUrl"
Write-Host "- Version (pubspec -> installer): $appVersion"
if ($UpdateGithubOwner -and $UpdateGithubRepo) {
  Write-Host "- Update feed: https://github.com/$UpdateGithubOwner/$UpdateGithubRepo/releases"
}

Write-Host "\nRestoring dependencies..." -ForegroundColor Cyan
flutter pub get

Write-Host "\nBuilding Flutter Windows release..." -ForegroundColor Cyan
$dartDefines = @(
  "--dart-define=ENVIRONMENT=$Environment",
  "--dart-define=CONTROL_PLANE_URL=$controlPlaneUrl"
)

if ($UpdateGithubOwner -and $UpdateGithubRepo) {
  $dartDefines += "--dart-define=UPDATE_GITHUB_OWNER=$UpdateGithubOwner"
  $dartDefines += "--dart-define=UPDATE_GITHUB_REPO=$UpdateGithubRepo"
}

flutter build windows --release @dartDefines

$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path $releaseDir)) {
  throw "Expected build output not found: $releaseDir"
}

if (-not $SkipZip) {
  Write-Host "\nCreating portable zip..." -ForegroundColor Cyan
  $zipPath = Join-Path $distWindowsDir "kumiho-browser-windows-x64-$appVersion.zip"
  if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
  Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath
  Write-Host "Wrote: $zipPath"
}

if (-not $SkipInstaller) {
  $iscc = $null
  if ($IsccPath) {
    $resolved = Resolve-Path -Path $IsccPath -ErrorAction Stop
    $iscc = $resolved.Path
  } else {
    $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Path }
  }

  if ($iscc) {
    Write-Host "\nBuilding installer (Inno Setup)..." -ForegroundColor Cyan
    $env:APP_VERSION = $appVersion
    & $iscc windows\installer\kumiho_asset_browser.iss
    Write-Host "Installer output: $distWindowsDir" 
  } else {
    Write-Warning "Inno Setup compiler (iscc.exe) not found. Install it (Admin PowerShell: 'choco install innosetup -y' or 'winget install --id JRSoftware.InnoSetup -e') or rerun with -IsccPath <path> or -SkipInstaller."
  }
}

Write-Host "\nDone." -ForegroundColor Green
Write-Host "Artifacts:" -ForegroundColor Green
Write-Host "- Windows release folder: $releaseDir"
Write-Host "- Windows dist folder: $distWindowsDir"
