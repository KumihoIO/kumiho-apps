# Kumiho Ingest - Local Build Guide

This guide explains how to build the Kumiho Ingest desktop app locally on macOS, Windows, and Linux, reproducing the same build process used by GitHub Actions.

## Prerequisites

Before building, ensure you have the following installed:

### 1. Node.js (v20+)
```bash
# Check if installed
node --version

# Install via Homebrew (if needed)
brew install node@20
```

### 2. pnpm (v9)
```bash
# Check if installed
pnpm --version

# Install globally
npm install -g pnpm@9
```

### 3. Rust and Cargo
```bash
# Check if installed
rustc --version
cargo --version

# Install via rustup (if needed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### 4. Python 3
```bash
# Check if installed (macOS usually has Python 3 pre-installed)
python3 --version
```

## Quick Build

### macOS
From the `kumiho-ingest` directory, run:

```bash
./build-macos.sh
```

### Windows
From the `kumiho-ingest` directory in PowerShell, run:

```powershell
.\build-windows.ps1
```

### Linux (Ubuntu/Debian)
From the `kumiho-ingest` directory, run:

```bash
./build-linux.sh
```

This script will:
1. Install UI dependencies
2. Build the React/Vite UI
3. Install tauri-cli (if not already installed)
4. Generate app icons
5. Build the Tauri desktop app
6. Create a distributable zip file

## Build Output

After a successful build, you'll find the following artifacts:

### macOS
```
apps/desktop-tauri/src-tauri/target/release/bundle/
├── macos/
│   └── Kumiho Ingest Studio.app   # The macOS app bundle
├── dmg/
│   └── Kumiho Ingest Studio_*.dmg # DMG installer
└── kumiho-ingest-macos.zip        # Zipped bundle for distribution
```

### Windows
```
apps/desktop-tauri/src-tauri/target/release/bundle/
├── msi/
│   └── Kumiho Ingest Studio_*.msi # MSI installer
├── nsis/
│   └── Kumiho Ingest Studio_*.exe # NSIS installer
└── kumiho-ingest-windows.zip      # Zipped bundle for distribution
```

### Linux
```
apps/desktop-tauri/src-tauri/target/release/bundle/
├── appimage/
│   └── *.AppImage                 # AppImage executable
├── deb/
│   └── *.deb                      # Debian package
└── kumiho-ingest-linux.zip        # Zipped bundle for distribution
```

## Running the App

### macOS
```bash
open "apps/desktop-tauri/src-tauri/target/release/bundle/macos/Kumiho Ingest Studio.app"
```
Or double-click the `.app` file in Finder.

### Windows
Navigate to the bundle folder and run the MSI or NSIS installer, or extract and run the executable from the zip.

### Linux
**AppImage:**
```bash
chmod +x apps/desktop-tauri/src-tauri/target/release/bundle/appimage/*.AppImage
./apps/desktop-tauri/src-tauri/target/release/bundle/appimage/*.AppImage
```

**Debian package:**
```bash
sudo dpkg -i apps/desktop-tauri/src-tauri/target/release/bundle/deb/*.deb
```

## Manual Build Steps

If you prefer to build manually, follow these steps:

### 1. Build the UI
```bash
cd apps/ingest-studio-ui
pnpm install --frozen-lockfile
pnpm run build
cd ../..
```

### 2. Install tauri-cli (first time only)
```bash
cargo install tauri-cli --locked
```

### 3. Build the Tauri app
```bash
cd apps/desktop-tauri/src-tauri
cargo tauri build
```

## Platform Compatibility Analysis

### Code Changes Compatibility

All recent changes to the codebase are **fully cross-platform compatible**:

✅ **Storyboard file moving** (`storyboard_ingest.py`)
- Uses `os.path.join()` for path construction (works on all platforms)
- Uses `shutil.move()` for file operations (cross-platform)
- Path sanitization handles both `/` and `\` separators

✅ **Dynamic grid slicing** (React/TypeScript UI)
- Pure JavaScript/React code (platform-independent)
- No file system operations in the grid logic

✅ **File path wrapping** (CSS changes)
- CSS word-break rules (browser-rendered, platform-independent)

### Build Differences from GitHub Actions

The local build scripts mirror the GitHub Actions workflow (`.github/workflows/tauri-build.yml`) with these considerations:

**macOS (`build-macos.sh`):**
- Generates `.app` bundle, DMG, and ICNS icons
- No additional dependencies needed (macOS has everything built-in)

**Windows (`build-windows.ps1`):**
- Generates MSI and NSIS installers, ICO icons
- Requires PowerShell (built into Windows)
- Uses same Python scripts as GitHub Actions

**Linux (`build-linux.sh`):**
- Generates AppImage and Debian packages
- Requires system dependencies (GTK, WebKit, etc.)
- Script offers to auto-install missing dependencies

## Testing Changes

After making code changes:

### UI Changes (React/TypeScript)
```bash
cd apps/ingest-studio-ui
pnpm run dev  # Development mode with hot reload
```

### Backend/Rust Changes
```bash
cd apps/desktop-tauri/src-tauri
cargo tauri dev  # Development mode
```

### Full Production Build
```bash
./build-macos.sh  # Complete production build
```

## Troubleshooting

### Build fails with "tauri-cli not found"
Install tauri-cli manually:
```bash
cargo install tauri-cli --locked
```

### UI build fails
Clear node_modules and reinstall:
```bash
cd apps/ingest-studio-ui
rm -rf node_modules pnpm-lock.yaml
pnpm install
pnpm run build
```

### Rust build fails
Clean the Rust build cache:
```bash
cd apps/desktop-tauri/src-tauri
cargo clean
cargo tauri build
```

### Icons missing
The script auto-generates placeholder icons. To use custom icons, place them in:
```
apps/desktop-tauri/src-tauri/icons/
├── icon.png   # 512x512 PNG
└── icon.icns  # macOS icon file
```

## Build Time

Expect the following build times (approximate):
- **First build**: 10-20 minutes (Rust dependencies compilation)
- **Subsequent builds**: 2-5 minutes (incremental compilation)

## Related Files

- Build script: `build-macos.sh`
- GitHub workflow: `.github/workflows/tauri-build.yml`
- Tauri config: `apps/desktop-tauri/src-tauri/tauri.conf.json`
- UI package: `apps/ingest-studio-ui/package.json`
