#!/usr/bin/env bash
set -euo pipefail

# Builds a signed and notarized macOS .app, then produces:
# - DMG for first-time installs
# - ZIP suitable for Sparkle updates (signed separately via Sparkle tools)
#
# Prereqs:
# - Flutter installed
# - CocoaPods installed (`sudo gem install cocoapods` or brew)
#
# For code signing & notarization, set these environment variables:
# - APPLE_CERTIFICATE_BASE64: Base64-encoded .p12 certificate
# - APPLE_CERTIFICATE_PASSWORD: Password for the .p12 certificate
# - APPLE_ID: Your Apple ID email
# - APPLE_APP_PASSWORD: App-specific password from appleid.apple.com
# - APPLE_TEAM_ID: Your Apple Developer Team ID (e.g., M57TZEKD3W)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="Kumiho Browser"
BUILD_DIR="$ROOT_DIR/build/macos/Build/Products/Release"
APP_SRC="$BUILD_DIR/kumiho_asset_browser.app"
APP_DST="$BUILD_DIR/${APP_NAME}.app"
OUT_DIR="$ROOT_DIR/dist/macos"

mkdir -p "$OUT_DIR"

# ============ Import Apple certificate if provided ============
CODESIGN_IDENTITY=""
if [[ -n "${APPLE_CERTIFICATE_BASE64:-}" && -n "${APPLE_CERTIFICATE_PASSWORD:-}" ]]; then
  echo "==> Importing Apple Developer certificate"
  
  CERT_PATH="/tmp/apple_certificate.p12"
  KEYCHAIN_PATH="$HOME/Library/Keychains/build.keychain-db"
  KEYCHAIN_PASSWORD="temp_keychain_pw_$$"
  
  # Decode certificate
  echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$CERT_PATH"
  
  # Delete old keychain if exists
  security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
  
  # Create new keychain
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  
  # Configure keychain: no auto-lock
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  
  # Unlock the keychain
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  
  # Import certificate with -T to allow codesign access
  security import "$CERT_PATH" \
    -k "$KEYCHAIN_PATH" \
    -P "${APPLE_CERTIFICATE_PASSWORD}" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
  
  # Allow codesign to access the keychain without prompts (macOS 10.12+)
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" 2>/dev/null || echo "Note: set-key-partition-list returned non-zero (may be ok)"
  
  # Add to search list (prepend so it's searched first)
  security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"' | tr '\n' ' ')
  
  # Show available identities for debugging
  echo "==> Available signing identities:"
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true
  
  # Find the Developer ID Application identity
  CODESIGN_IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/' || true)
  
  if [[ -z "$CODESIGN_IDENTITY" ]]; then
    echo "WARNING: No 'Developer ID Application' identity found in certificate"
    # Try to find any valid identity
    ANY_IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -v "^$" | head -1 | sed -E 's/.*"(.+)"/\1/' || true)
    if [[ -n "$ANY_IDENTITY" ]]; then
      echo "Found alternative identity: $ANY_IDENTITY"
      CODESIGN_IDENTITY="$ANY_IDENTITY"
    fi
  else
    echo "==> Found signing identity: $CODESIGN_IDENTITY"
  fi
  
  rm -f "$CERT_PATH"
elif [[ -n "${APPLE_CERTIFICATE_BASE64:-}" ]]; then
  # Certificate provided but no password - try with empty password
  echo "==> Importing Apple Developer certificate (no password)"
  
  CERT_PATH="/tmp/apple_certificate.p12"
  KEYCHAIN_PATH="$HOME/Library/Keychains/build.keychain-db"
  KEYCHAIN_PASSWORD="temp_keychain_pw_$$"
  
  echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$CERT_PATH"
  
  security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  
  # Import with empty password
  security import "$CERT_PATH" \
    -k "$KEYCHAIN_PATH" \
    -P "" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
  
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" 2>/dev/null || echo "Note: set-key-partition-list returned non-zero (may be ok)"
  
  security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"' | tr '\n' ' ')
  
  echo "==> Available signing identities:"
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true
  
  CODESIGN_IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/' || true)
  
  if [[ -n "$CODESIGN_IDENTITY" ]]; then
    echo "==> Found signing identity: $CODESIGN_IDENTITY"
  fi
  
  rm -f "$CERT_PATH"
else
  echo "==> Skipping certificate import (APPLE_CERTIFICATE_BASE64 not set)"
fi

echo "==> Installing pods"
(
  cd "$ROOT_DIR/macos"

  # CocoaPods uses Podfile.lock to pin versions. In CI, this can drift out of sync
  # with FlutterFire plugin constraints (e.g., firebase_auth requiring Firebase/Auth 12.x
  # while Podfile.lock pins 11.x), causing builds to fail.
  if [[ "${CI:-}" == "true" ]]; then
    echo "CI detected; cleaning CocoaPods state to re-resolve dependencies"
    rm -rf Pods Runner.xcworkspace Podfile.lock
  fi

  pod install --repo-update
)

echo "==> Building Flutter macOS release"
FLUTTER_BUILD_ARGS=(macos --release)

if [[ -n "${ENVIRONMENT:-}" ]]; then
  FLUTTER_BUILD_ARGS+=("--dart-define=ENVIRONMENT=${ENVIRONMENT}")
fi

if [[ -n "${CONTROL_PLANE_URL:-}" ]]; then
  FLUTTER_BUILD_ARGS+=("--dart-define=CONTROL_PLANE_URL=${CONTROL_PLANE_URL}")
fi

if [[ -n "${UPDATE_GITHUB_OWNER:-}" ]]; then
  FLUTTER_BUILD_ARGS+=("--dart-define=UPDATE_GITHUB_OWNER=${UPDATE_GITHUB_OWNER}")
fi

if [[ -n "${UPDATE_GITHUB_REPO:-}" ]]; then
  FLUTTER_BUILD_ARGS+=("--dart-define=UPDATE_GITHUB_REPO=${UPDATE_GITHUB_REPO}")
fi

if [[ -n "${EXTRA_FLUTTER_BUILD_ARGS:-}" ]]; then
  # Space-separated extra args. Example:
  #   EXTRA_FLUTTER_BUILD_ARGS='--dart-define=FOO=bar --dart-define=BAZ=qux'
  # shellcheck disable=SC2206
  EXTRA_ARR=($EXTRA_FLUTTER_BUILD_ARGS)
  FLUTTER_BUILD_ARGS+=("${EXTRA_ARR[@]}")
fi

( cd "$ROOT_DIR" && flutter build "${FLUTTER_BUILD_ARGS[@]}" )

if [[ ! -d "$APP_SRC" ]]; then
  echo "ERROR: Expected app at $APP_SRC" >&2
  exit 1
fi

echo "==> Copying app as '$APP_NAME.app'"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

# ============ Firebase macOS config (optional) ============
# FirebaseAuth on macOS expects GoogleService-Info.plist to be present in the app bundle.
# IMPORTANT: this must happen BEFORE code signing / notarization.
#
# Provide via ONE of:
# - GOOGLE_SERVICE_INFO_PLIST_BASE64: base64-encoded contents of GoogleService-Info.plist
# - GOOGLE_SERVICE_INFO_PLIST: absolute/relative path to a GoogleService-Info.plist file
PLIST_DEST="$APP_DST/Contents/Resources/GoogleService-Info.plist"
mkdir -p "$(dirname "$PLIST_DEST")"

if [[ -n "${GOOGLE_SERVICE_INFO_PLIST_BASE64:-}" ]]; then
  echo "==> Embedding GoogleService-Info.plist (from GOOGLE_SERVICE_INFO_PLIST_BASE64)"
  # macOS base64 uses -D; GNU uses --decode. Support both.
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    printf '%s' "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > "$PLIST_DEST"
  else
    printf '%s' "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 -D > "$PLIST_DEST"
  fi
elif [[ -n "${GOOGLE_SERVICE_INFO_PLIST:-}" && -f "${GOOGLE_SERVICE_INFO_PLIST}" ]]; then
  echo "==> Embedding GoogleService-Info.plist (from GOOGLE_SERVICE_INFO_PLIST path)"
  cp -f "$GOOGLE_SERVICE_INFO_PLIST" "$PLIST_DEST"
else
  echo "==> GoogleService-Info.plist not provided; Firebase Auth will be unavailable on macOS."
fi

# ============ Code Signing ============
if [[ -n "${CODESIGN_IDENTITY:-}" && "$CODESIGN_IDENTITY" != *"0 valid identities"* ]]; then
  echo "==> Codesigning app with: $CODESIGN_IDENTITY"
  
  # Sign all nested frameworks and binaries first
  find "$APP_DST" -type f -perm +111 -o -name "*.dylib" -o -name "*.framework" 2>/dev/null | while read -r item; do
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$item" 2>/dev/null || true
  done
  
  # IMPORTANT (DMG distribution):
  # - We intentionally do NOT use App Sandbox entitlements for Developer ID DMG distribution.
  #   (Sandbox entitlements can cause launch failure on newer macOS if no matching
  #    provisioning profile is embedded.)
  # - Minimal Keychain entitlements (com.apple.application-identifier / keychain-access-groups)
  #   may also be treated as "restricted" and can trigger launch failure
  #   (RBSRequestErrorDomain Code=5 / NSPOSIXErrorDomain Code=163) unless a matching
  #   provisioning profile is embedded.
  #
  # Default behavior (safe): sign with hardened runtime only (no entitlements).
  # Optional: embed a provisioning profile and sign with minimal Keychain entitlements.

  # Optional provisioning profile embedding.
  # Provide via ONE of:
  # - MACOS_PROVISIONPROFILE_BASE64: base64-encoded .provisionprofile
  # - MACOS_PROVISIONPROFILE: path to a .provisionprofile file
  PROFILE_DST="$APP_DST/Contents/embedded.provisionprofile"
  if [[ -n "${MACOS_PROVISIONPROFILE_BASE64:-}" ]]; then
    echo "==> Embedding provisioning profile (from MACOS_PROVISIONPROFILE_BASE64)"
    if base64 --help 2>&1 | grep -q -- '--decode'; then
      printf '%s' "$MACOS_PROVISIONPROFILE_BASE64" | base64 --decode > "$PROFILE_DST"
    else
      printf '%s' "$MACOS_PROVISIONPROFILE_BASE64" | base64 -D > "$PROFILE_DST"
    fi
  elif [[ -n "${MACOS_PROVISIONPROFILE:-}" && -f "${MACOS_PROVISIONPROFILE}" ]]; then
    echo "==> Embedding provisioning profile (from MACOS_PROVISIONPROFILE path)"
    cp -f "$MACOS_PROVISIONPROFILE" "$PROFILE_DST"
  fi
  ENTITLEMENTS_PATH="/tmp/kumiho_release_entitlements.plist"
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DST/Contents/Info.plist" 2>/dev/null || true)
  if [[ -z "$BUNDLE_ID" ]]; then
    echo "ERROR: Could not read CFBundleIdentifier from Info.plist" >&2
    exit 1
  fi

  if [[ -n "${APPLE_TEAM_ID:-}" && -f "$PROFILE_DST" ]]; then
    APP_ID="${APPLE_TEAM_ID}.${BUNDLE_ID}"
    cat > "$ENTITLEMENTS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.application-identifier</key>
  <string>${APP_ID}</string>
  <key>keychain-access-groups</key>
  <array>
    <string>${APP_ID}</string>
  </array>
</dict>
</plist>
EOF

    echo "==> Signing with minimal Keychain entitlements (profile embedded)"
    codesign --force --deep --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS_PATH" \
      --sign "$CODESIGN_IDENTITY" \
      "$APP_DST"
  else
    echo "==> Signing without entitlements (no provisioning profile embedded)"
    codesign --force --deep --options runtime --timestamp \
      --sign "$CODESIGN_IDENTITY" \
      "$APP_DST"
  fi
  
  codesign --verify --deep --strict --verbose=2 "$APP_DST"
  echo "==> Code signing complete"
else
  echo "==> Skipping codesign (no valid signing identity found)"
  echo "==> NOTE: The app will trigger macOS Gatekeeper warnings without code signing"
fi

echo "==> Creating Sparkle update ZIP"
ZIP_PATH="$OUT_DIR/${APP_NAME}.zip"
rm -f "$ZIP_PATH"
# Sparkle expects a .zip of the .app bundle.
( cd "$BUILD_DIR" && ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "$ZIP_PATH" )

echo "==> Creating DMG"
DMG_PATH="$OUT_DIR/${APP_NAME}.dmg"
rm -f "$DMG_PATH"

# Build a simple drag-to-install DMG layout:
# - "${APP_NAME}.app"
# - "Applications" symlink to /Applications
DMG_STAGING_DIR="$(mktemp -d)"
DMG_MOUNT_DIR="$(mktemp -d)"
DMG_RW_PATH="$OUT_DIR/${APP_NAME}-rw.dmg"
trap 'rm -rf "$DMG_STAGING_DIR" "$DMG_MOUNT_DIR"; rm -f "$DMG_RW_PATH"' EXIT

cp -R "$APP_DST" "$DMG_STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

# Create a read-write DMG so we can set Finder window layout (.DS_Store)
rm -f "$DMG_RW_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDRW \
  "$DMG_RW_PATH" >/dev/null

# Mount read-write DMG and (best-effort) set icon positions
DMG_DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW_PATH" -mountpoint "$DMG_MOUNT_DIR" \
  | awk '/^\/dev\// {print $1; exit}')

if command -v osascript >/dev/null 2>&1; then
  osascript <<EOF || echo "==> Note: Could not set DMG Finder layout (non-fatal)"
tell application "Finder"
  tell disk "${APP_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 200, 740, 520}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set position of item "${APP_NAME}.app" to {170, 200}
    set position of item "Applications" to {480, 200}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
fi

sync
sleep 1

if [[ -n "${DMG_DEVICE:-}" ]]; then
  hdiutil detach "$DMG_DEVICE" -quiet || hdiutil detach "$DMG_DEVICE" -force -quiet || true
fi

# Convert to compressed DMG for distribution
hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

# ============ Notarization ============
if [[ -n "${CODESIGN_IDENTITY:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  echo "==> Submitting DMG for notarization"
  
  # Submit for notarization and wait
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  
  # Staple the notarization ticket to the DMG
  echo "==> Stapling notarization ticket to DMG"
  xcrun stapler staple "$DMG_PATH"
  
  # Also notarize the ZIP for Sparkle updates
  echo "==> Submitting ZIP for notarization"
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  
  # Staple the ZIP (note: stapling ZIPs doesn't always work, but we try)
  xcrun stapler staple "$ZIP_PATH" 2>/dev/null || echo "==> Note: Could not staple ZIP (this is normal)"
  
  echo "==> Notarization complete"
else
  echo "==> Skipping notarization (APPLE_ID, APPLE_APP_PASSWORD, or APPLE_TEAM_ID not set)"
fi

echo "==> Done"
echo "- App: $APP_DST"
echo "- ZIP: $ZIP_PATH"
echo "- DMG: $DMG_PATH"
