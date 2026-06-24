#!/usr/bin/env bash
set -euo pipefail

PY_VERSION="${PY_VERSION:-3.13.11}"
REPO_URL="https://api.github.com/repos/indygreg/python-build-standalone/releases/latest"

OS_NAME="$(uname -s)"
ARCH_NAME="$(uname -m)"

case "$OS_NAME" in
  Darwin) PLATFORM_OS="apple-darwin"; DEST_DIR="python/macos" ;;
  Linux) PLATFORM_OS="unknown-linux-gnu"; DEST_DIR="python/linux" ;;
  *) echo "Unsupported OS: $OS_NAME" >&2; exit 1 ;;
esac

case "$ARCH_NAME" in
  x86_64|amd64) PLATFORM_ARCH="x86_64" ;;
  arm64|aarch64) PLATFORM_ARCH="aarch64" ;;
  *) echo "Unsupported architecture: $ARCH_NAME" >&2; exit 1 ;;
esac

ASSET_REGEX="^cpython-${PY_VERSION}\\+.*-${PLATFORM_ARCH}-${PLATFORM_OS}-install_only\\.tar\\.gz$"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse GitHub release metadata." >&2
  exit 1
fi

ASSET_URL="$(python3 - <<PY
import json
import re
import urllib.request

data = json.loads(urllib.request.urlopen("${REPO_URL}").read().decode("utf-8"))
regex = re.compile("${ASSET_REGEX}")
for asset in data.get("assets", []):
    name = asset.get("name", "")
    if regex.match(name):
        print(asset.get("browser_download_url", ""))
        break
PY
)"

if [[ -z "$ASSET_URL" ]]; then
  echo "No asset found for ${PY_VERSION} ${PLATFORM_ARCH}-${PLATFORM_OS}." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/${DEST_DIR}"
TMP_DIR="$(mktemp -d)"
ARCHIVE_PATH="${TMP_DIR}/python.tar.gz"

echo "Downloading ${ASSET_URL}"
curl -L "$ASSET_URL" -o "$ARCHIVE_PATH"

echo "Extracting into ${TARGET_DIR}"
mkdir -p "$TARGET_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"

if [[ -d "${TMP_DIR}/python" ]]; then
  rsync -a "${TMP_DIR}/python/" "$TARGET_DIR/"
else
  rsync -a "${TMP_DIR}/" "$TARGET_DIR/"
fi

echo "Done. Python runtime placed in ${TARGET_DIR}"
