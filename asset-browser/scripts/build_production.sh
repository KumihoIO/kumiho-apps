#!/bin/bash
# Build Kumiho Browser - Production
# Cross-platform shell script for macOS and Linux

set -e

echo "Building Kumiho Browser (Production)..."

# Detect platform
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="linux"
else
    echo "Unsupported platform: $OSTYPE"
    exit 1
fi

echo "Platform: $PLATFORM"

flutter build $PLATFORM \
    --release \
    --dart-define=ENVIRONMENT=production \
    --dart-define=CONTROL_PLANE_URL=https://control.kumiho.cloud

if [[ "$PLATFORM" == "macos" ]]; then
    # Optional: embed Firebase macOS config.
    # FirebaseAuth on macOS expects a native GoogleService-Info.plist in the app bundle.
    # Provide it via:
    #   - env var: GOOGLE_SERVICE_INFO_PLIST=/absolute/path/to/GoogleService-Info.plist
    #   - or place it at: macos/Runner/GoogleService-Info.plist
    APP_PATH="build/macos/Build/Products/Release/kumiho_asset_browser.app"
    PLIST_DEST="$APP_PATH/Contents/Resources/GoogleService-Info.plist"
    mkdir -p "$(dirname "$PLIST_DEST")"

    if [[ -n "$GOOGLE_SERVICE_INFO_PLIST" && -f "$GOOGLE_SERVICE_INFO_PLIST" ]]; then
        cp -f "$GOOGLE_SERVICE_INFO_PLIST" "$PLIST_DEST"
        echo "Embedded GoogleService-Info.plist into app bundle (from GOOGLE_SERVICE_INFO_PLIST)."
        echo "Note: copying after build may invalidate code signing; re-sign before distribution."
    elif [[ -f "macos/Runner/GoogleService-Info.plist" ]]; then
        cp -f "macos/Runner/GoogleService-Info.plist" "$PLIST_DEST"
        echo "Embedded GoogleService-Info.plist into app bundle (from macos/Runner)."
        echo "Note: copying after build may invalidate code signing; re-sign before distribution."
    else
        echo "Firebase macOS config not found (GoogleService-Info.plist)."
        echo "Sign-in using Firebase Auth will be disabled on macOS unless you provide it."
    fi

    # Local sanity:
    # We ad-hoc sign for local testing so macOS will run the app.
    # IMPORTANT: Do NOT attach App Sandbox entitlements to an ad-hoc signature.
    # On recent macOS versions this can cause the app to be killed at launch
    # (e.g. RBSRequestErrorDomain Code=5 / NSPOSIXErrorDomain Code=163).
    #
    # For distribution (signed DMG + notarization + entitlements), use:
    #   scripts/macos/build_release.sh
    if [[ -d "$APP_PATH" ]]; then
        codesign --force --deep --sign - "$APP_PATH" 2>/dev/null \
          && echo "Ad-hoc signed app for local launching." \
          || echo "Note: ad-hoc codesign failed (may still run)."
    fi

    echo "Build complete! Output: build/macos/Build/Products/Release/"
elif [[ "$PLATFORM" == "linux" ]]; then
    echo "Build complete! Output: build/linux/x64/release/bundle/"
fi

echo ""
echo "Ready for packaging!"
