# Kumiho Browser one-line installer (Windows)
#   irm https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/asset-browser.ps1 | iex
$ErrorActionPreference = 'Stop'
$repo = 'KumihoIO/kumiho-apps'
$prefix = 'asset-browser-v'

$headers = @{ 'User-Agent' = 'kumiho-installer'; 'Accept' = 'application/vnd.github+json' }
$releases = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=50" -Headers $headers
$rel = $releases | Where-Object { $_.tag_name -like "$prefix*" -and -not $_.draft -and -not $_.prerelease } | Select-Object -First 1
if (-not $rel) { throw "No published $prefix* release found in $repo." }

$asset = $rel.assets | Where-Object { $_.name -like '*.exe' } | Select-Object -First 1
if (-not $asset) { throw "Release $($rel.tag_name) has no .exe installer." }

$out = Join-Path $env:TEMP $asset.name
Write-Host "Downloading $($asset.name) ($($rel.tag_name))..."
Invoke-WebRequest $asset.browser_download_url -OutFile $out -Headers $headers
Write-Host "Launching installer..."
Start-Process $out
