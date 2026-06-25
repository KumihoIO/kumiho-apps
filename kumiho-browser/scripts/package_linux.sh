#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --version X.Y.Z --bundle-dir <path> [--out-dir <path>]" >&2
}

VERSION=""
BUNDLE_DIR=""
OUT_DIR="dist/linux"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"; shift 2 ;;
    --bundle-dir)
      BUNDLE_DIR="$2"; shift 2 ;;
    --out-dir)
      OUT_DIR="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage; exit 2 ;;
  esac
done

if [[ -z "$VERSION" || -z "$BUNDLE_DIR" ]]; then
  usage; exit 2
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Bundle dir not found: $BUNDLE_DIR" >&2
  exit 2
fi

APP_NAME="kumiho-browser"
BIN_NAME="kumiho_asset_browser"
INSTALL_DIR="/opt/$APP_NAME"

if [[ ! -f "$BUNDLE_DIR/$BIN_NAME" ]]; then
  echo "Expected executable not found: $BUNDLE_DIR/$BIN_NAME" >&2
  echo "Did you run: flutter build linux --release ?" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_FILE="$ROOT_DIR/linux/packaging/kumiho-browser.desktop"
ICON_FILE_256="$ROOT_DIR/assets/icons/common/icon_256x256.png"

if [[ ! -f "$DESKTOP_FILE" ]]; then
  echo "Desktop file missing: $DESKTOP_FILE" >&2
  exit 2
fi
if [[ ! -f "$ICON_FILE_256" ]]; then
  echo "Icon missing: $ICON_FILE_256" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Packaging Linux for version $VERSION from bundle: $BUNDLE_DIR"

############################
# Build .deb
############################

deb_root="$workdir/debroot"
mkdir -p "$deb_root/DEBIAN"
mkdir -p "$deb_root$INSTALL_DIR"
mkdir -p "$deb_root/usr/bin"
mkdir -p "$deb_root/usr/share/applications"
mkdir -p "$deb_root/usr/share/icons/hicolor/256x256/apps"

cp -a "$BUNDLE_DIR/." "$deb_root$INSTALL_DIR/"
cp "$DESKTOP_FILE" "$deb_root/usr/share/applications/$APP_NAME.desktop"
cp "$ICON_FILE_256" "$deb_root/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"

ln -s "$INSTALL_DIR/$BIN_NAME" "$deb_root/usr/bin/$APP_NAME"

cat > "$deb_root/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: ${VERSION}-1
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Kumiho <support@kumiho.io>
Homepage: https://kumiho.io
Depends: libgtk-3-0, libstdc++6
Description: Kumiho Browser
 A desktop application for browsing and managing creative assets on Kumiho Cloud.
EOF

chmod 0755 "$deb_root/DEBIAN"

deb_out="$OUT_DIR/${APP_NAME}_${VERSION}-1_amd64.deb"
dpkg-deb --build "$deb_root" "$deb_out" >/dev/null
echo "Wrote $deb_out"

############################
# Build .rpm
############################

if command -v rpmbuild >/dev/null 2>&1; then
  rpm_top="$workdir/rpmbuild"
  mkdir -p "$rpm_top/BUILD" "$rpm_top/BUILDROOT" "$rpm_top/RPMS" "$rpm_top/SOURCES" "$rpm_top/SPECS" "$rpm_top/SRPMS"

  srcdir="$workdir/rpm_src/${APP_NAME}-${VERSION}"
  mkdir -p "$srcdir"
  mkdir -p "$srcdir/bundle"

  cp -a "$BUNDLE_DIR/." "$srcdir/bundle/"
  cp "$DESKTOP_FILE" "$srcdir/$APP_NAME.desktop"
  cp "$ICON_FILE_256" "$srcdir/$APP_NAME.png"

  tarball="$rpm_top/SOURCES/${APP_NAME}-${VERSION}.tar.gz"
  (cd "$(dirname "$srcdir")" && tar -czf "$tarball" "${APP_NAME}-${VERSION}")

  spec="$rpm_top/SPECS/$APP_NAME.spec"
  cat > "$spec" <<EOF
Name:           $APP_NAME
Version:        $VERSION
Release:        1%{?dist}
Summary:        Kumiho Browser
License:        MIT
URL:            https://kumiho.io
Source0:        %{name}-%{version}.tar.gz
BuildArch:      x86_64

Requires:       gtk3

%description
A desktop application for browsing and managing creative assets on Kumiho Cloud.

%prep
%setup -q

%build
# No build step; we package the prebuilt Flutter bundle.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}${INSTALL_DIR}
cp -a bundle/. %{buildroot}${INSTALL_DIR}/

mkdir -p %{buildroot}/usr/bin
ln -s ${INSTALL_DIR}/${BIN_NAME} %{buildroot}/usr/bin/%{name}

mkdir -p %{buildroot}/usr/share/applications
install -m 0644 %{name}.desktop %{buildroot}/usr/share/applications/%{name}.desktop

mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps
install -m 0644 %{name}.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/%{name}.png

%files
${INSTALL_DIR}
/usr/bin/%{name}
/usr/share/applications/%{name}.desktop
/usr/share/icons/hicolor/256x256/apps/%{name}.png

%changelog
* $(date "+%a %b %d %Y") Kumiho <support@kumiho.io> - %{version}-1
- Automated build
EOF

  rpmbuild --define "_topdir $rpm_top" -bb "$spec" >/dev/null
  rpm_file="$(find "$rpm_top/RPMS" -type f -name "${APP_NAME}-${VERSION}-1*.rpm" | head -n 1)"
  if [[ -z "$rpm_file" ]]; then
    echo "RPM build completed but output not found" >&2
    exit 2
  fi

  rpm_out="$OUT_DIR/$(basename "$rpm_file")"
  cp "$rpm_file" "$rpm_out"
  echo "Wrote $rpm_out"
else
  echo "rpmbuild not found; skipping rpm packaging" >&2
fi
