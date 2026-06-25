#!/usr/bin/env bash
set -euo pipefail

# Generates a Sparkle appcast.xml and signs the update ZIP.
#
# You need Sparkle's command line tools installed locally.
# Recommended: download Sparkle release and install its tools:
#   - generate_keys
#   - sign_update
#   - generate_appcast
#
# Typical flow:
# 1) Create keys once:
#      generate_keys
#    Put the PUBLIC key into macos/Runner/Configs/AppInfo.xcconfig as SPARKLE_PUBLIC_ED25519_KEY
#    Keep the PRIVATE key safe for CI/release signing.
#
# 2) Build artifacts first:
#      ./scripts/macos/build_release.sh
#
# 3) Sign the ZIP + generate appcast:
#      SPARKLE_PRIVATE_KEY=... ./scripts/macos/sparkle_appcast.sh \
#        --downloads-dir dist/macos \
#        --base-url https://downloads.example.com/kumiho-browser/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOWNLOADS_DIR="$ROOT_DIR/dist/macos"
BASE_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --downloads-dir)
      DOWNLOADS_DIR="$2"; shift 2;;
    --base-url)
      BASE_URL="$2"; shift 2;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$BASE_URL" ]]; then
  echo "ERROR: --base-url is required (where you host the ZIP/DMG)." >&2
  exit 1
fi

PRIVATE_KEY_INPUT="${SPARKLE_ED25519_PRIVATE_KEY:-${SPARKLE_PRIVATE_KEY:-}}"
if [[ -z "$PRIVATE_KEY_INPUT" ]]; then
  echo "ERROR: Set SPARKLE_ED25519_PRIVATE_KEY (preferred) or SPARKLE_PRIVATE_KEY." >&2
  echo "- Value can be a file path OR the key text itself." >&2
  echo "TIP: Prefer storing the key text in CI secrets." >&2
  exit 1
fi

APP_NAME="Kumiho Browser"
ZIP_PATH="$DOWNLOADS_DIR/${APP_NAME}.zip"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "ERROR: Missing ZIP: $ZIP_PATH" >&2
  echo "Run: ./scripts/macos/build_release.sh" >&2
  exit 1
fi

# The Sparkle tool invocation differs depending on how you installed it.
# If tools are on PATH, these should work:
SIGN_TOOL="sign_update"
APPCAST_TOOL="generate_appcast"

KEY_FILE=""
if [[ -f "$PRIVATE_KEY_INPUT" ]]; then
  KEY_FILE="$PRIVATE_KEY_INPUT"
else
  KEY_FILE="$(mktemp -t sparkle_ed25519.XXXXXX)"
  printf '%s' "$PRIVATE_KEY_INPUT" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
fi

echo "==> Signing update ZIP"
# Sparkle's sign_update typically supports: sign_update <path> --ed-key-file <private_key>
# You may need to adjust flags based on your Sparkle tools version.
$SIGN_TOOL "$ZIP_PATH" --ed-key-file "$KEY_FILE" > "$ZIP_PATH.signature"

echo "==> Generating appcast.xml"
# generate_appcast scans a folder of updates and emits appcast.xml.
# We pass a base URL so Sparkle knows where downloads are hosted.
# Sparkle does not allow multiple archives with the same bundle version in one appcast.
# If you keep both a DMG (manual install) and ZIP (Sparkle update) in the same folder,
# generate_appcast will fail. Generate the appcast from the ZIP only.
APPCAST_INPUT_DIR="$(mktemp -d -t sparkle_appcast_input.XXXXXX)"
trap 'rm -rf "$APPCAST_INPUT_DIR"' EXIT
cp -f "$ZIP_PATH" "$APPCAST_INPUT_DIR/"
if [[ -f "$ZIP_PATH.signature" ]]; then
  cp -f "$ZIP_PATH.signature" "$APPCAST_INPUT_DIR/"
fi

$APPCAST_TOOL --download-url-prefix "$BASE_URL" "$APPCAST_INPUT_DIR" > "$DOWNLOADS_DIR/appcast.xml"

echo "==> Done"
echo "- appcast.xml: $DOWNLOADS_DIR/appcast.xml"
echo "- signature:  $ZIP_PATH.signature"
