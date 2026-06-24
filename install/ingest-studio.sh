#!/usr/bin/env sh
# Kumiho Ingest Studio one-line installer (macOS / Linux)
#   curl -fsSL https://raw.githubusercontent.com/KumihoIO/kumiho-apps/main/install/ingest-studio.sh | sh
set -eu

REPO="KumihoIO/kumiho-apps"
PREFIX="ingest-studio-v"

case "$(uname -s)" in
  Darwin) WANT=".dmg" ;;
  Linux)
    if command -v dpkg >/dev/null 2>&1; then WANT=".deb"
    else WANT=".AppImage"; fi ;;
  *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to resolve the latest release." >&2
  echo "Download manually from https://github.com/$REPO/releases" >&2
  exit 1
fi

URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=50" \
  | python3 -c "import sys,json
prefix='$PREFIX'; want='$WANT'
for r in json.load(sys.stdin):
    if r.get('draft') or r.get('prerelease'): continue
    if not r.get('tag_name','').startswith(prefix): continue
    for a in r.get('assets',[]):
        if a['name'].endswith(want):
            print(a['browser_download_url']); sys.exit(0)
sys.exit(1)")"

[ -n "$URL" ] || { echo "No ${WANT} asset found for ${PREFIX}* in $REPO." >&2; exit 1; }

TMP="$(mktemp -d)"
FILE="$TMP/$(basename "$URL")"
echo "Downloading $(basename "$URL")..."
curl -fsSL "$URL" -o "$FILE"

case "$WANT" in
  .deb) sudo dpkg -i "$FILE" || sudo apt-get install -f -y ;;
  .AppImage) chmod +x "$FILE"; mkdir -p "$HOME/.local/bin"; mv "$FILE" "$HOME/.local/bin/kumiho-ingest-studio.AppImage";
             echo "Installed to ~/.local/bin/kumiho-ingest-studio.AppImage" ;;
  .dmg) echo "Opening $FILE — drag Kumiho Ingest Studio to Applications."; open "$FILE" ;;
esac
