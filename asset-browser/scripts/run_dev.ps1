<#
Run Kumiho Browser (Windows).

Examples:
    # Dev against local control plane
    .\scripts\run_dev.ps1

    # Production control plane
    .\scripts\run_dev.ps1 --production

    # Enable Firebase on desktop (required for email/password sign-in)
    .\scripts\run_dev.ps1 --production --firebase-desktop

    # Explicit control plane override
    .\scripts\run_dev.ps1 --control-plane-url=https://control.kumiho.cloud --firebase-desktop
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    # Named usage: -Environment production
    # Flag usage:  --production (handled below)
    [string]$Environment = 'development',

    [Parameter()]
    [string]$ControlPlaneUrl = '',
    [Parameter()]
    [string]$DataPlaneUrl = '',

    [Alias('firebase-desktop')]
    [switch]$EnableFirebaseDesktop,

    [switch]$Release,
    [switch]$Profile,

    [Parameter()]
    [string]$Device = 'windows',
    [Parameter()]
    [switch]$Help,

    # Accept all remaining args (e.g. production, --release, --production)
    # without PowerShell trying to bind them positionally.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

# Build a unified arg list from RemainingArgs.
$rawArgs = @()
if ($null -ne $RemainingArgs) {
    $rawArgs += $RemainingArgs
}

foreach ($arg in $rawArgs) {
    switch -Regex ($arg) {
        '^--help$' { $Help = $true; break }
        '^(production|prod)$' { $Environment = 'production'; break }
        '^(staging|stage)$' { $Environment = 'staging'; break }
        '^(development|dev)$' { $Environment = 'development'; break }
        '^--production$' { $Environment = 'production'; break }
        '^--staging$' { $Environment = 'staging'; break }
        '^--development$' { $Environment = 'development'; break }
        '^--firebase-desktop$' { $EnableFirebaseDesktop = $true; break }
        '^--release$' { $Release = $true; break }
        '^--profile$' { $Profile = $true; break }
        '^--control-plane-url=(.+)$' { $ControlPlaneUrl = $Matches[1]; break }
        '^--data-plane-url=(.+)$' { $DataPlaneUrl = $Matches[1]; break }
        '^--device=(.+)$' { $Device = $Matches[1]; break }
    }
}

if ($Release -and $Profile) {
    Write-Error "Choose only one: --release or --profile.";
    exit 1
}

# Normalize any explicitly provided environment values.
switch ($Environment.ToLowerInvariant()) {
    'prod' { $Environment = 'production' }
    'production' { $Environment = 'production' }
    'stage' { $Environment = 'staging' }
    'staging' { $Environment = 'staging' }
    'dev' { $Environment = 'development' }
    'development' { $Environment = 'development' }
    default {
        Write-Error "Invalid -Environment '$Environment'. Use development|staging|production.";
        exit 1
    }
}

if ($Help) {
    Write-Host "Usage:" -ForegroundColor Cyan
    Write-Host "  .\scripts\run_dev.ps1 [--production|--staging|--development] [--firebase-desktop] [--control-plane-url=URL] [--data-plane-url=URL] [--device=windows]" -ForegroundColor Cyan
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ControlPlaneUrl)) {
    if ($Environment -eq 'production') {
        $ControlPlaneUrl = 'https://control.kumiho.cloud'
    } elseif ($Environment -eq 'staging') {
        $ControlPlaneUrl = 'https://control-staging.kumiho.cloud'
    } else {
        $ControlPlaneUrl = 'http://localhost:3000'
    }
}

Write-Host "Running Kumiho Browser..." -ForegroundColor Cyan
Write-Host "  ENVIRONMENT=$Environment" -ForegroundColor DarkGray
Write-Host "  CONTROL_PLANE_URL=$ControlPlaneUrl" -ForegroundColor DarkGray
if (-not [string]::IsNullOrWhiteSpace($DataPlaneUrl)) {
    Write-Host "  DATA_PLANE_URL=$DataPlaneUrl" -ForegroundColor DarkGray
}
if ($EnableFirebaseDesktop) {
    Write-Host "  ENABLE_FIREBASE_DESKTOP=true" -ForegroundColor DarkGray
}

$dartDefines = @(
    "--dart-define=ENVIRONMENT=$Environment",
    "--dart-define=CONTROL_PLANE_URL=$ControlPlaneUrl"
)

if (-not [string]::IsNullOrWhiteSpace($DataPlaneUrl)) {
    $dartDefines += "--dart-define=DATA_PLANE_URL=$DataPlaneUrl"
}

if ($EnableFirebaseDesktop) {
    $dartDefines += "--dart-define=ENABLE_FIREBASE_DESKTOP=true"
}

$flutterArgs = @('run', '-d', $Device) + $dartDefines

if ($Release) {
    $flutterArgs += '--release'
} elseif ($Profile) {
    $flutterArgs += '--profile'
}

flutter @flutterArgs
