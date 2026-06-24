#!/bin/bash
set -e  # Exit on error

echo "======================================"
echo "Kumiho Ingest - macOS Local Build"
echo "======================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

# Check prerequisites
print_step "Checking prerequisites..."

if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed"
    exit 1
fi

if ! command -v pnpm &> /dev/null; then
    echo "Error: pnpm is not installed"
    echo "Install with: npm install -g pnpm@9"
    exit 1
fi

if ! command -v cargo &> /dev/null; then
    echo "Error: Rust/Cargo is not installed"
    echo "Install from: https://rustup.rs/"
    exit 1
fi

print_success "All prerequisites installed"
echo "  Node: $(node --version)"
echo "  pnpm: $(pnpm --version)"
echo "  Rust: $(rustc --version)"
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
ico_path = os.path.join(icons_dir, "icon.ico")
icns_path = os.path.join(icons_dir, "icon.icns")

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

def ensure_icns(path: str, png_bytes: bytes, size: int):
  try:
    with open(path, "rb") as f:
      header = f.read(4)
  except FileNotFoundError:
    header = b""
  if header == b"icns":
    return "kept"
  chunk_type = {128: b"ic07", 256: b"ic08", 512: b"ic09", 1024: b"ic10"}.get(size, b"ic09")
  chunk_len = 8 + len(png_bytes)
  total_len = 8 + chunk_len
  icns = b"icns" + struct.pack(">I", total_len) + chunk_type + struct.pack(">I", chunk_len) + png_bytes
  with open(path, "wb") as f:
    f.write(icns)
  return "generated"

png_bytes, png_info, png_status = ensure_png(png_path, 512, 512)
icns_size = png_info[0] if png_info else 512
icns_status = ensure_icns(icns_path, png_bytes, icns_size)

print(f"icon.png: {png_status}")
print(f"icon.icns: {icns_status}")
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

zip_name = "kumiho-ingest-macos.zip"
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
echo "  Bundle: apps/desktop-tauri/src-tauri/target/release/bundle/"
echo "  App:    apps/desktop-tauri/src-tauri/target/release/bundle/macos/Kumiho Ingest Studio.app"
echo "  DMG:    apps/desktop-tauri/src-tauri/target/release/bundle/dmg/"
echo "  Zip:    apps/desktop-tauri/src-tauri/target/release/bundle/kumiho-ingest-macos.zip"
echo ""
echo "To run the app:"
echo "  open 'apps/desktop-tauri/src-tauri/target/release/bundle/macos/Kumiho Ingest Studio.app'"
echo ""
