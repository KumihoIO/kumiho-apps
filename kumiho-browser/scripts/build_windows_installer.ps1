Param(
  [Parameter(Mandatory = $false)][ValidateSet('production', 'staging')][string]$Environment = 'production',
  [Parameter(Mandatory = $false)][string]$UpdateGithubOwner,
  [Parameter(Mandatory = $false)][string]$UpdateGithubRepo
)

$ErrorActionPreference = 'Stop'

function Get-ControlPlaneUrl([string]$envName) {
  switch ($envName) {
    'staging' { return 'https://control-staging.kumiho.cloud' }
    default { return 'https://control.kumiho.cloud' }
  }
}

$controlPlaneUrl = Get-ControlPlaneUrl $Environment

Write-Host "Building Windows release ($Environment)..."
flutter pub get
$dartDefines = @(
  "--dart-define=ENVIRONMENT=$Environment",
  "--dart-define=CONTROL_PLANE_URL=$controlPlaneUrl"
)

if ($UpdateGithubOwner -and $UpdateGithubRepo) {
  $dartDefines += "--dart-define=UPDATE_GITHUB_OWNER=$UpdateGithubOwner"
  $dartDefines += "--dart-define=UPDATE_GITHUB_REPO=$UpdateGithubRepo"
}

flutter build windows --release @dartDefines

if (-not (Get-Command iscc.exe -ErrorAction SilentlyContinue)) {
  throw "Inno Setup compiler (iscc.exe) not found. Install Inno Setup, or run: choco install innosetup -y"
}

$pubspec = Join-Path $PSScriptRoot '..\pubspec.yaml'
$versionLine = (Get-Content $pubspec | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1)
if (-not $versionLine) { throw "Could not determine version from pubspec.yaml" }

$semver = ($versionLine -replace '^version:\s*', '').Trim()
if ($semver -match '^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$') {
  $appVersion = "$($Matches[1]).$($Matches[2])"
} else {
  $appVersion = $semver
}

Write-Host "Packaging installer (APP_VERSION=$appVersion)..."
$env:APP_VERSION = $appVersion

$iss = Join-Path $PSScriptRoot '..\windows\installer\kumiho_asset_browser.iss'
& iscc.exe $iss

Write-Host "Done. Installer in dist\\windows"
