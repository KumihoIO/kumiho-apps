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
# Set REQUIRE_MACOS_SIGNING=1 for any artifact intended for public release.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REQUIRE_MACOS_SIGNING="${REQUIRE_MACOS_SIGNING:-0}"
APP_NAME="Kumiho Browser"
BUILD_DIR="$ROOT_DIR/build/macos/Build/Products/Release"
APP_SRC="$BUILD_DIR/kumiho_asset_browser.app"
APP_DST="$BUILD_DIR/${APP_NAME}.app"
OUT_DIR="$ROOT_DIR/dist/macos"

case "$REQUIRE_MACOS_SIGNING" in
  0|1) ;;
  *)
    echo "ERROR: REQUIRE_MACOS_SIGNING must be 0 or 1" >&2
    exit 1
    ;;
esac

if [[ "$REQUIRE_MACOS_SIGNING" == "1" ]]; then
  command -v node >/dev/null 2>&1 || {
    echo "ERROR: Node.js is required for the macOS release preflight" >&2
    exit 1
  }
  node "$ROOT_DIR/scripts/macos/validate_release_env.cjs"
fi

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
    echo "WARNING: No 'Developer ID Application' identity found in certificate" >&2
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

if [[ "$REQUIRE_MACOS_SIGNING" == "1" && -z "$CODESIGN_IDENTITY" ]]; then
  echo "ERROR: A Developer ID Application identity is required for a public macOS release" >&2
  exit 1
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

  sign_nested_code() {
    local code_path="$1"
    local signing_args=(
      --force
      --options runtime
      --timestamp
      --sign "$CODESIGN_IDENTITY"
    )

    # Sparkle's Downloader.xpc and other vendor-signed helpers can carry
    # required entitlements. Preserve them when replacing an existing
    # signature; unsigned frameworks such as Ass.framework take the new
    # Developer ID signature without this option.
    if codesign -d "$code_path" >/dev/null 2>&1; then
      signing_args+=(--preserve-metadata=entitlements)
    fi
    codesign "${signing_args[@]}" "$code_path"
  }

  # Sign every nested Mach-O first, then its containing bundle from the
  # deepest directory outward. Each object is checked independently so a
  # missing signature such as v1.0.5's Ass.framework cannot be hidden.
  echo "==> Signing nested Mach-O binaries"
  while IFS= read -r -d '' item; do
    if file -b "$item" | grep -q 'Mach-O'; then
      sign_nested_code "$item"
    fi
  done < <(find "$APP_DST/Contents" -type f -print0)

  echo "==> Signing nested code bundles"
  while IFS= read -r -d '' item; do
    sign_nested_code "$item"
  done < <(
    find "$APP_DST/Contents" -depth -type d \
      \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \
         -o -name '*.appex' -o -name '*.bundle' -o -name '*.plugin' \) \
      -print0
  )
  
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
    codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS_PATH" \
      --sign "$CODESIGN_IDENTITY" \
      "$APP_DST"
  else
    echo "==> Signing without entitlements (no provisioning profile embedded)"
    codesign --force --options runtime --timestamp \
      --sign "$CODESIGN_IDENTITY" \
      "$APP_DST"
  fi

  verify_signed_code() {
    local code_path="$1"
    local actual_team

    codesign --verify --strict --verbose=2 "$code_path"
    actual_team=$(codesign -dv --verbose=4 "$code_path" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    if [[ -n "${APPLE_TEAM_ID:-}" && "$actual_team" != "$APPLE_TEAM_ID" ]]; then
      echo "ERROR: Wrong or missing TeamIdentifier for $code_path (found: ${actual_team:-none})" >&2
      return 1
    fi
  }

  verify_app_bundle() {
    local app_path="$1"
    local code_path

    codesign --verify --deep --strict --verbose=2 "$app_path"
    verify_signed_code "$app_path"

    while IFS= read -r -d '' code_path; do
      verify_signed_code "$code_path"
    done < <(
      find "$app_path/Contents" -depth -type d \
        \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \
           -o -name '*.appex' -o -name '*.bundle' -o -name '*.plugin' \) \
        -print0
    )

    while IFS= read -r -d '' code_path; do
      if file -b "$code_path" | grep -q 'Mach-O'; then
        verify_signed_code "$code_path"
      fi
    done < <(find "$app_path/Contents" -type f -print0)
  }

  verify_app_bundle "$APP_DST"
  echo "==> Code signing complete"
else
  if [[ "$REQUIRE_MACOS_SIGNING" == "1" ]]; then
    echo "ERROR: Refusing to create an unsigned public macOS release" >&2
    exit 1
  fi
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
cleanup_dmg_workspace() {
  if [[ -n "${VERIFY_DEVICE:-}" ]]; then
    hdiutil detach "$VERIFY_DEVICE" -force -quiet || true
  fi
  if [[ -n "${DMG_DEVICE:-}" ]]; then
    hdiutil detach "$DMG_DEVICE" -force -quiet || true
  fi
  rm -rf "$DMG_STAGING_DIR" "$DMG_MOUNT_DIR"
  rm -f "$DMG_RW_PATH"
}
trap cleanup_dmg_workspace EXIT

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
  DMG_DEVICE=""
fi

# Convert to compressed DMG for distribution
hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "==> Signing DMG"
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"
fi

# ============ Notarization ============
if [[ -n "${CODESIGN_IDENTITY:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  submit_for_notarization() {
    local artifact_path="$1"
    local result_path
    local status

    result_path=$(mktemp)
    xcrun notarytool submit "$artifact_path" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait \
      --output-format json > "$result_path"
    cat "$result_path"
    status=$(plutil -extract status raw -o - "$result_path")
    rm -f "$result_path"
    if [[ "$status" != "Accepted" ]]; then
      echo "ERROR: Apple notarization did not accept $artifact_path (status: $status)" >&2
      return 1
    fi
  }

  echo "==> Submitting DMG for notarization"
  submit_for_notarization "$DMG_PATH"
  
  # Staple the notarization ticket to the DMG
  echo "==> Stapling notarization ticket to DMG"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

  # Also notarize the ZIP for Sparkle updates
  echo "==> Submitting ZIP for notarization"
  submit_for_notarization "$ZIP_PATH"

  echo "==> Verifying app from the final DMG"
  VERIFY_DEVICE=$(hdiutil attach -readonly -noverify -noautoopen "$DMG_PATH" \
    -mountpoint "$DMG_MOUNT_DIR" | awk '/^\/dev\// {print $1; exit}')
  MOUNTED_APP="$DMG_MOUNT_DIR/${APP_NAME}.app"
  if [[ -z "${VERIFY_DEVICE:-}" || ! -d "$MOUNTED_APP" ]]; then
    echo "ERROR: Could not mount the final DMG for verification" >&2
    exit 1
  fi
  verify_app_bundle "$MOUNTED_APP"
  spctl --assess --type execute --verbose=4 "$MOUNTED_APP"
  hdiutil detach "$VERIFY_DEVICE" -quiet
  VERIFY_DEVICE=""

  echo "==> Notarization complete"
else
  if [[ "$REQUIRE_MACOS_SIGNING" == "1" ]]; then
    echo "ERROR: Refusing to publish a macOS release without notarization" >&2
    exit 1
  fi
  echo "==> Skipping notarization (APPLE_ID, APPLE_APP_PASSWORD, or APPLE_TEAM_ID not set)"
fi

echo "==> Done"
echo "- App: $APP_DST"
echo "- ZIP: $ZIP_PATH"
echo "- DMG: $DMG_PATH"
