# Kumiho Ingest - Windows Local Build Script
# PowerShell script to reproduce GitHub Actions build on Windows

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Kumiho Ingest - Windows Local Build" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

function Print-Step {
    param([string]$Message)
    Write-Host "➜ $Message" -ForegroundColor Blue
}

function Print-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Print-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Print-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Check prerequisites
Print-Step "Checking prerequisites..."

# Check Node.js
try {
    $nodeVersion = node --version
    Print-Success "Node.js installed: $nodeVersion"
} catch {
    Print-Error "Node.js is not installed"
    Write-Host "Install from: https://nodejs.org/"
    exit 1
}

# Check pnpm
try {
    $pnpmVersion = pnpm --version
    Print-Success "pnpm installed: $pnpmVersion"
} catch {
    Print-Error "pnpm is not installed"
    Write-Host "Install with: npm install -g pnpm@9"
    exit 1
}

# Check Rust/Cargo
try {
    $rustVersion = rustc --version
    Print-Success "Rust installed: $rustVersion"
} catch {
    Print-Error "Rust is not installed"
    Write-Host "Install from: https://rustup.rs/"
    exit 1
}

# Check Python
try {
    $pythonVersion = python --version
    Print-Success "Python installed: $pythonVersion"
} catch {
    Print-Error "Python is not installed"
    Write-Host "Install from: https://www.python.org/"
    exit 1
}

Write-Host ""

# Install UI dependencies
Print-Step "Installing UI dependencies..."
Push-Location apps\ingest-studio-ui
pnpm install --frozen-lockfile
if ($LASTEXITCODE -ne 0) {
    Print-Error "Failed to install UI dependencies"
    exit 1
}
Print-Success "UI dependencies installed"
Write-Host ""

# Build UI
Print-Step "Building UI..."
pnpm run build
if ($LASTEXITCODE -ne 0) {
    Print-Error "Failed to build UI"
    exit 1
}
Print-Success "UI build complete"
Write-Host ""

Pop-Location

# Install tauri-cli if not present
Print-Step "Checking for tauri-cli..."
$tauriInstalled = Get-Command cargo-tauri -ErrorAction SilentlyContinue
if (-not $tauriInstalled) {
    Print-Warning "tauri-cli not found, installing..."
    cargo install tauri-cli --locked
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Failed to install tauri-cli"
        exit 1
    }
    Print-Success "tauri-cli installed"
} else {
    Print-Success "tauri-cli already installed"
}
Write-Host ""

# Ensure Tauri icons exist
Print-Step "Ensuring Tauri icons exist..."
python -c @"
import os
import struct
import binascii
import zlib

icons_dir = os.path.join('apps', 'desktop-tauri', 'src-tauri', 'icons')
os.makedirs(icons_dir, exist_ok=True)

png_path = os.path.join(icons_dir, 'icon.png')
ico_path = os.path.join(icons_dir, 'icon.ico')

def chunk(tag: bytes, data: bytes) -> bytes:
  return (
    struct.pack('!I', len(data))
    + tag
    + data
    + struct.pack('!I', binascii.crc32(tag + data) & 0xFFFFFFFF)
  )

def build_png(width: int, height: int) -> bytes:
  rgba = b'\x22\x22\x22\xff'
  row = b'\x00' + rgba * width
  raw = row * height
  compressed = zlib.compress(raw, 9)
  ihdr = struct.pack('!IIBBBBB', width, height, 8, 6, 0, 0, 0)
  return (
    b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', ihdr)
    + chunk(b'IDAT', compressed)
    + chunk(b'IEND', b'')
  )

def read_png_info(path: str):
  try:
    with open(path, 'rb') as f:
      data = f.read()
  except FileNotFoundError:
    return None, None
  if len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n':
    return None, None
  if data[12:16] != b'IHDR':
    return None, None
  width, height, bit_depth, color_type, *_ = struct.unpack('!IIBBBBB', data[16:29])
  return data, (width, height, bit_depth, color_type)

def ensure_png(path: str, width: int, height: int):
  data, info = read_png_info(path)
  if info:
    w, h, _, color_type = info
    if w == h and color_type == 6:
      return data, info, 'kept'
  data = build_png(width, height)
  with open(path, 'wb') as f:
    f.write(data)
  return data, (width, height, 8, 6), 'generated'

def ico_has_256(path: str) -> bool:
  try:
    with open(path, 'rb') as f:
      data = f.read()
  except FileNotFoundError:
    return False
  if len(data) < 6 or data[:4] != b'\x00\x00\x01\x00':
    return False
  count = struct.unpack('<H', data[4:6])[0]
  if len(data) < 6 + count * 16:
    return False
  for i in range(count):
    entry = data[6 + i * 16 : 6 + (i + 1) * 16]
    if entry[0] == 0 and entry[1] == 0:
      return True
  return False

def ensure_ico(path: str, png_bytes: bytes):
  if ico_has_256(path):
    return 'kept'
  header = struct.pack('<HHH', 0, 1, 1)
  entry = struct.pack('<BBBBHHII', 0, 0, 0, 0, 1, 32, len(png_bytes), 6 + 16)
  with open(path, 'wb') as f:
    f.write(header + entry + png_bytes)
  return 'generated'

png_bytes, png_info, png_status = ensure_png(png_path, 512, 512)
ico_status = ensure_ico(ico_path, build_png(256, 256))

print(f'icon.png: {png_status}')
print(f'icon.ico: {ico_status}')
"@

if ($LASTEXITCODE -ne 0) {
    Print-Error "Failed to generate icons"
    exit 1
}
Print-Success "Icons ready"
Write-Host ""

# Build Tauri app
Print-Step "Building Tauri app (this may take a while)..."
Push-Location apps\desktop-tauri\src-tauri
cargo tauri build
if ($LASTEXITCODE -ne 0) {
    Print-Error "Failed to build Tauri app"
    exit 1
}
Print-Success "Tauri build complete"
Write-Host ""

Pop-Location

# Create bundle zip
Print-Step "Creating bundle zip..."
python -c @"
import os
import zipfile

bundle_dir = os.path.join('apps', 'desktop-tauri', 'src-tauri', 'target', 'release', 'bundle')
if not os.path.isdir(bundle_dir):
  raise SystemExit(f'Missing bundle directory: {bundle_dir}')

zip_name = 'kumiho-ingest-windows.zip'
zip_path = os.path.join(bundle_dir, zip_name)

files = []
for root, _, filenames in os.walk(bundle_dir):
  for filename in filenames:
    full_path = os.path.join(root, filename)
    if os.path.abspath(full_path) == os.path.abspath(zip_path):
      continue
    files.append(full_path)

if not files:
  raise SystemExit('No bundle files found to zip.')

with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
  for full_path in files:
    rel_path = os.path.relpath(full_path, bundle_dir)
    zf.write(full_path, rel_path)

print(f'Created {zip_path} with {len(files)} files.')
"@

if ($LASTEXITCODE -ne 0) {
    Print-Error "Failed to create bundle zip"
    exit 1
}
Print-Success "Bundle zip created"
Write-Host ""

# Show output location
Write-Host "======================================" -ForegroundColor Green
Write-Host "Build Complete!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "Build artifacts location:"
Write-Host "  Bundle: apps\desktop-tauri\src-tauri\target\release\bundle\"
Write-Host "  MSI:    apps\desktop-tauri\src-tauri\target\release\bundle\msi\"
Write-Host "  NSIS:   apps\desktop-tauri\src-tauri\target\release\bundle\nsis\"
Write-Host "  Zip:    apps\desktop-tauri\src-tauri\target\release\bundle\kumiho-ingest-windows.zip"
Write-Host ""
Write-Host "To run the app, navigate to the bundle folder and run the installer or executable."
Write-Host ""
