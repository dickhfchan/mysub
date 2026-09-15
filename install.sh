#!/usr/bin/env bash
# MySub installer — downloads the latest release and wires up the native host
set -euo pipefail

REPO="dickhfchan/mysub"
INSTALL_DIR="$HOME/.mysub"
DOWNLOAD_DIR="$HOME/Downloads/MySub"
NM_NAME="com.mysub.downloader"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}▶${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
error() { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }
bold()  { echo -e "${BOLD}$*${NC}"; }

echo ""
bold "  MySub Installer"
echo "  ───────────────────────────────────────"
echo ""

# ── 1. Platform check ────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || error "MySub requires macOS."

# ── 2. Prerequisites ─────────────────────────────────────────────────────────
info "Checking prerequisites..."
MISSING=0
check() {
    local cmd=$1 brew=$2
    if command -v "$cmd" &>/dev/null; then
        echo "  ✓ $cmd"
    else
        warn "$cmd not found — install with: brew install $brew"
        MISSING=1
    fi
}
check python3 python
check yt-dlp  yt-dlp
check ffmpeg  ffmpeg
[[ $MISSING -eq 0 ]] || error "Install the missing tools above, then re-run this script."

# ── 3. Download latest release ────────────────────────────────────────────────
info "Fetching latest release from github.com/$REPO ..."
LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
echo "  → version $LATEST"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ZIP_URL="https://github.com/$REPO/archive/refs/tags/$LATEST.zip"
curl -fsSL "$ZIP_URL" -o "$TMP/mysub.zip"
unzip -q "$TMP/mysub.zip" -d "$TMP"
SRC=$(echo "$TMP"/mysub-*/)

# ── 4. Install to ~/.mysub ────────────────────────────────────────────────────
info "Installing to $INSTALL_DIR ..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -R "$SRC"* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/native/mysub_host.py" \
         "$INSTALL_DIR/native/mysub_uploader.py"

# ── 5. Install native messaging manifest ─────────────────────────────────────
info "Installing native messaging host..."
HOST_PATH="$INSTALL_DIR/native/mysub_host.py"

write_nm_manifest() {
    local dest_dir=$1
    mkdir -p "$dest_dir"
    sed "s|__HOST_PATH__|$HOST_PATH|g" \
        "$INSTALL_DIR/native/$NM_NAME.json" > "$dest_dir/$NM_NAME.json"
}

INSTALLED_FOR=()
ARC_DIR="$HOME/Library/Application Support/Arc/User Data/NativeMessagingHosts"
CHR_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

[[ -d "$HOME/Library/Application Support/Arc" ]]           && { write_nm_manifest "$ARC_DIR"; INSTALLED_FOR+=("Arc"); }
[[ -d "$HOME/Library/Application Support/Google/Chrome" ]] && { write_nm_manifest "$CHR_DIR"; INSTALLED_FOR+=("Chrome"); }

if [[ ${#INSTALLED_FOR[@]} -eq 0 ]]; then
    warn "Neither Arc nor Chrome found. Install the browser first, then re-run."
else
    echo "  ✓ Native host installed for: ${INSTALLED_FOR[*]}"
fi

# ── 6. Config ─────────────────────────────────────────────────────────────────
mkdir -p "$DOWNLOAD_DIR"
CONFIG="$DOWNLOAD_DIR/mysub_config.json"

if [[ -f "$CONFIG" ]]; then
    warn "Config already exists at $CONFIG — skipping."
else
    info "Setting up WeTube config..."
    echo ""
    read -rp "  WeTube URL (e.g. https://wetube-two.vercel.app): " WETUBE_URL
    read -rp "  Upload API key: " UPLOAD_KEY
    read -rp "  Max upload size in MB [500]: " MAX_MB
    MAX_MB=${MAX_MB:-500}
    python3 -c "
import json
cfg = {'wetube_url': '$WETUBE_URL', 'upload_key': '$UPLOAD_KEY', 'max_upload_mb': int('$MAX_MB')}
print(json.dumps(cfg, indent=2))
" > "$CONFIG"
    echo "  ✓ Config saved."
fi

# ── 7. Summary ────────────────────────────────────────────────────────────────
echo ""
bold "  Installation complete!"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Load the extension:"
echo "     Open Arc/Chrome → chrome://extensions"
echo "     Enable Developer mode → Load unpacked"
echo "     Select: $INSTALL_DIR"
echo ""
echo "  2. Start the uploader (runs in background):"
echo "     nohup python3 $INSTALL_DIR/native/mysub_uploader.py > /tmp/mysub_uploader.log 2>&1 &"
echo ""
echo "  3. (Optional) Auto-start on login:"
echo "     Add the command above to System Settings → General → Login Items"
echo ""
