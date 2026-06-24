# Releases (Desktop App)

This document describes how Kumiho Browser is packaged for distribution.

## Versioning

- Release tags: `browser-vX.Y.Z`
- Flutter build name/number: taken from `pubspec.yaml` `version:`.

## Windows (Installable)

### Installer format

We build a Windows installer using **Inno Setup**. The output is a single `.exe` installer.

### Local build

Prereqs:

- Flutter SDK (see README)
- Inno Setup (installs `iscc.exe`) e.g. `choco install innosetup -y`

Run:

- `./scripts/build_windows_installer.ps1 -Environment production`

Output:

- `dist/windows/KumihoBrowserSetup-<version>.exe`

### CI build

The GitHub workflow `.github/workflows/build-kumiho-browser.yml`:

- Builds `flutter build windows --release`
- Produces an installer via `iscc.exe` and uploads it as an artifact
- On tag `browser-v*`, attaches the installer to the GitHub Release

## macOS (Auto-update later)

For macOS auto-update, the typical approach is **Sparkle** (appcast feed + signed updates).

Recommended future steps:

1. Decide distribution: GitHub Releases appcast vs dedicated update endpoint.
2. Add Sparkle to `macos/Runner` and generate an `appcast.xml` per release.
3. Sign the `.app` and update archives in CI using Apple Developer ID credentials.

Notes:

- Auto-update on macOS generally requires code signing + notarization for a smooth user experience.

## Linux (Debian + RPM)

We package the Flutter Linux release bundle into:

- `.deb` for Debian/Ubuntu
- `.rpm` for Fedora/RHEL-family distros

Install layout:

- App bundle: `/opt/kumiho-browser/`
- CLI shim: `/usr/bin/kumiho-browser` (symlink)
- Desktop entry: `/usr/share/applications/kumiho-browser.desktop`
- Icon: `/usr/share/icons/hicolor/256x256/apps/kumiho-browser.png`

Local packaging (on Linux):

- `./scripts/package_linux.sh --version X.Y.Z --bundle-dir build/linux/x64/release/bundle`

