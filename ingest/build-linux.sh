#!/bin/bash
set -e  # Exit on error

echo "======================================"
echo "Kumiho Ingest - Linux Local Build"
echo "======================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}➜ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check prerequisites
print_step "Checking prerequisites..."

if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed"
    echo "Install with: curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs"
    exit 1
fi

if ! command -v pnpm &> /dev/null; then
    print_error "pnpm is not installed"
    echo "Install with: npm install -g pnpm@9"
    exit 1
fi

if ! command -v cargo &> /dev/null; then
    print_error "Rust/Cargo is not installed"
    echo "Install from: https://rustup.rs/"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    print_error "Python 3 is not installed"
    echo "Install with: sudo apt-get install python3"
    exit 1
fi

print_success "All prerequisites installed"
echo "  Node: $(node --version)"
echo "  pnpm: $(pnpm --version)"
echo "  Rust: $(rustc --version)"
echo "  Python: $(python3 --version)"
echo ""

# Check Linux dependencies
print_step "Checking Linux build dependencies..."
MISSING_DEPS=()

# Check for required packages
for pkg in build-essential pkg-config libssl-dev libgtk-3-dev libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        MISSING_DEPS+=("$pkg")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    print_warning "Missing required system dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "Install with:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y \\"
    echo "    build-essential \\"
    echo "    pkg-config \\"
    echo "    libssl-dev \\"
    echo "    libgtk-3-dev \\"
    echo "    libwebkit2gtk-4.1-dev \\"
    echo "    libayatana-appindicator3-dev \\"
    echo "    librsvg2-dev \\"
    echo "    patchelf"
    echo ""
    read -p "Install missing dependencies now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo apt-get update
        sudo apt-get install -y \
            build-essential \
            pkg-config \
            libssl-dev \
            libgtk-3-dev \
            libwebkit2gtk-4.1-dev \
            libayatana-appindicator3-dev \
            librsvg2-dev \
            patchelf
        print_success "Dependencies installed"
    else
        print_error "Cannot proceed without required dependencies"
        exit 1
    fi
else
    print_success "All Linux dependencies installed"
fi
echo ""

# Install UI dependencies
print_step "Installing UI dependencies..."
cd apps/ingest-studio-ui
pnpm install --frozen-lockfile
print_success "UI dependencies installed"
echo ""

# Build UI
print_step "Building UI..."
pnpm run build
print_success "UI build complete"
echo ""

cd ../..

# Install tauri-cli if not present
print_step "Checking for tauri-cli..."
if ! command -v cargo-tauri &> /dev/null; then
    print_warning "tauri-cli not found, installing..."
    cargo install tauri-cli --locked
    print_success "tauri-cli installed"
else
    print_success "tauri-cli already installed"
fi
echo ""

# Ensure Tauri icons exist
print_step "Ensuring Tauri icons exist..."
python3 - <<'PY'
import os
import struct
import binascii
import zlib

icons_dir = os.path.join("apps", "desktop-tauri", "src-tauri", "icons")
os.makedirs(icons_dir, exist_ok=True)

png_path = os.path.join(icons_dir, "icon.png")

def chunk(tag: bytes, data: bytes) -> bytes:
  return (
    struct.pack("!I", len(data))
    + tag
    + data
    + struct.pack("!I", binascii.crc32(tag + data) & 0xFFFFFFFF)
  )

def build_png(width: int, height: int) -> bytes:
  rgba = b"\x22\x22\x22\xff"  # dark gray + alpha
  row = b"\x00" + rgba * width  # filter 0 + RGBA pixels
  raw = row * height
  compressed = zlib.compress(raw, 9)
  ihdr = struct.pack("!IIBBBBB", width, height, 8, 6, 0, 0, 0)
  return (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", ihdr)
    + chunk(b"IDAT", compressed)
    + chunk(b"IEND", b"")
  )

def read_png_info(path: str):
  try:
    with open(path, "rb") as f:
      data = f.read()
  except FileNotFoundError:
    return None, None
  if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n":
    return None, None
  if data[12:16] != b"IHDR":
    return None, None
  width, height, bit_depth, color_type, *_ = struct.unpack("!IIBBBBB", data[16:29])
  return data, (width, height, bit_depth, color_type)

def ensure_png(path: str, width: int, height: int):
  data, info = read_png_info(path)
  if info:
    w, h, _, color_type = info
    if w == h and color_type == 6:
      return data, info, "kept"
  data = build_png(width, height)
  with open(path, "wb") as f:
    f.write(data)
  return data, (width, height, 8, 6), "generated"

png_bytes, png_info, png_status = ensure_png(png_path, 512, 512)

print(f"icon.png: {png_status}")
PY
print_success "Icons ready"
echo ""

# Build Tauri app
print_step "Building Tauri app (this may take a while)..."
cd apps/desktop-tauri/src-tauri
cargo tauri build
print_success "Tauri build complete"
echo ""

cd ../../..

# Create bundle zip
print_step "Creating bundle zip..."
python3 - <<'PY'
import os
import zipfile

bundle_dir = os.path.join("apps", "desktop-tauri", "src-tauri", "target", "release", "bundle")
if not os.path.isdir(bundle_dir):
  raise SystemExit(f"Missing bundle directory: {bundle_dir}")

zip_name = "kumiho-ingest-linux.zip"
zip_path = os.path.join(bundle_dir, zip_name)

files = []
for root, _, filenames in os.walk(bundle_dir):
  for filename in filenames:
    full_path = os.path.join(root, filename)
    if os.path.abspath(full_path) == os.path.abspath(zip_path):
      continue
    files.append(full_path)

if not files:
  raise SystemExit("No bundle files found to zip.")

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
  for full_path in files:
    rel_path = os.path.relpath(full_path, bundle_dir)
    zf.write(full_path, rel_path)

print(f"Created {zip_path} with {len(files)} files.")
PY
print_success "Bundle zip created"
echo ""

# Show output location
echo "======================================"
echo -e "${GREEN}Build Complete!${NC}"
echo "======================================"
echo ""
echo "Build artifacts location:"
echo "  Bundle:    apps/desktop-tauri/src-tauri/target/release/bundle/"
echo "  AppImage:  apps/desktop-tauri/src-tauri/target/release/bundle/appimage/"
echo "  Deb:       apps/desktop-tauri/src-tauri/target/release/bundle/deb/"
echo "  Zip:       apps/desktop-tauri/src-tauri/target/release/bundle/kumiho-ingest-linux.zip"
echo ""
echo "To run the app:"
echo "  - AppImage: chmod +x apps/desktop-tauri/src-tauri/target/release/bundle/appimage/*.AppImage"
echo "              ./apps/desktop-tauri/src-tauri/target/release/bundle/appimage/*.AppImage"
echo "  - Deb:      sudo dpkg -i apps/desktop-tauri/src-tauri/target/release/bundle/deb/*.deb"
echo ""
