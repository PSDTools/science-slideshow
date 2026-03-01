#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Raspberry Pi deployment script for the Slideshow app
#
# What this does:
#   1. Installs Node.js (via nvm), pnpm, and Chromium
#   2. Builds the SvelteKit app for production
#   3. Installs a systemd service so the app starts on boot
#   4. Installs a desktop autostart entry so Chromium opens in kiosk mode
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Re-run any time you want to deploy updated code.
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
APP_PORT="${APP_PORT:-3000}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="slideshow"
KIOSK_URL="http://localhost:${APP_PORT}"
NODE_VERSION="20"          # LTS
CURRENT_USER="${SUDO_USER:-$(whoami)}"
USER_HOME=$(eval echo "~${CURRENT_USER}")

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[deploy]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
abort() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────
[[ -f "${APP_DIR}/svelte/package.json" ]] || abort "Run this from the project root (can't find svelte/package.json)"
[[ "$(uname -m)" == arm* || "$(uname -m)" == aarch64 ]] || warn "Not running on ARM — are you sure this is a Pi?"

info "Deploying to: ${APP_DIR}"
info "Port:         ${APP_PORT}"
info "Running as:   ${CURRENT_USER}"

# ── 1. System packages ────────────────────────────────────────────────────────
info "Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y \
    chromium-browser \
    unclutter \
    curl \
    git \
    --no-install-recommends

# ── 2. Node.js via nvm ───────────────────────────────────────────────────────
NVM_DIR="${USER_HOME}/.nvm"
if [[ ! -d "${NVM_DIR}" ]]; then
    info "Installing nvm..."
    sudo -u "${CURRENT_USER}" bash -c \
        "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
fi

# Source nvm in this script
export NVM_DIR="${NVM_DIR}"
# shellcheck source=/dev/null
source "${NVM_DIR}/nvm.sh"

sudo -u "${CURRENT_USER}" bash --login -c "
    export NVM_DIR='${NVM_DIR}'
    source '${NVM_DIR}/nvm.sh'
    nvm install ${NODE_VERSION}
    nvm alias default ${NODE_VERSION}
    nvm use default
    npm install -g pnpm --silent
"

# Resolve the node/pnpm binaries installed by nvm
NODE_BIN=$(sudo -u "${CURRENT_USER}" bash --login -c \
    "export NVM_DIR='${NVM_DIR}'; source '${NVM_DIR}/nvm.sh'; nvm which current")
NODE_DIR="$(dirname "${NODE_BIN}")"
PNPM_BIN="${NODE_DIR}/pnpm"

info "Node: ${NODE_BIN}"
info "pnpm: ${PNPM_BIN}"

# ── 3. Install dependencies & build ──────────────────────────────────────────
info "Installing JS dependencies..."
sudo -u "${CURRENT_USER}" bash --login -c "
    export NVM_DIR='${NVM_DIR}'
    source '${NVM_DIR}/nvm.sh'
    cd '${APP_DIR}/svelte'
    pnpm install --frozen-lockfile
"

info "Building SvelteKit app..."
sudo -u "${CURRENT_USER}" bash --login -c "
    export NVM_DIR='${NVM_DIR}'
    source '${NVM_DIR}/nvm.sh'
    cd '${APP_DIR}/svelte'
    pnpm build
"

# ── 4. systemd service ────────────────────────────────────────────────────────
info "Installing systemd service: ${SERVICE_NAME}..."
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=Slideshow App
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${APP_DIR}/svelte
Environment=PORT=${APP_PORT}
ExecStart=${NODE_BIN} ${APP_DIR}/svelte/build/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"
info "Service started. Check with: sudo systemctl status ${SERVICE_NAME}"

# ── 5. Kiosk autostart ────────────────────────────────────────────────────────
info "Installing kiosk autostart..."
AUTOSTART_DIR="${USER_HOME}/.config/autostart"
mkdir -p "${AUTOSTART_DIR}"

# Wait-for-server helper script
sudo -u "${CURRENT_USER}" tee "${APP_DIR}/wait-and-launch.sh" > /dev/null <<'SCRIPT'
#!/usr/bin/env bash
# Wait until the app is responding, then launch Chromium in kiosk mode
URL="$1"
for i in $(seq 1 30); do
    curl -sf "$URL" > /dev/null 2>&1 && break
    sleep 1
done
# Hide the mouse cursor after 1 s of inactivity
unclutter -idle 1 &
# Disable screen blanking
xset s off
xset s noblank
xset -dpms
# Launch Chromium in kiosk mode
chromium-browser \
    --kiosk \
    --noerr \
    --disable-infobars \
    --no-first-run \
    --disable-restore-session-state \
    --disable-session-crashed-bubble \
    --disable-translate \
    --disable-features=TranslateUI \
    --check-for-update-interval=31536000 \
    "$URL"
SCRIPT
chmod +x "${APP_DIR}/wait-and-launch.sh"

# Desktop autostart entry (works with LXDE / Wayfire / labwc on Pi OS)
sudo -u "${CURRENT_USER}" tee "${AUTOSTART_DIR}/slideshow-kiosk.desktop" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Slideshow Kiosk
Exec=${APP_DIR}/wait-and-launch.sh ${KIOSK_URL}
X-GNOME-Autostart-enabled=true
EOF

# Also add to LXDE autostart if it exists (Pi OS Bullseye legacy)
LXDE_AUTOSTART="${USER_HOME}/.config/lxsession/LXDE-pi/autostart"
if [[ -f "${LXDE_AUTOSTART}" ]]; then
    if ! grep -q "wait-and-launch" "${LXDE_AUTOSTART}"; then
        echo "@${APP_DIR}/wait-and-launch.sh ${KIOSK_URL}" >> "${LXDE_AUTOSTART}"
        info "Added kiosk entry to LXDE autostart"
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Deploy complete!                                    ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  App URL:  ${KIOSK_URL}                          ║${NC}"
echo -e "${GREEN}║  Service:  sudo systemctl status ${SERVICE_NAME}       ║${NC}"
echo -e "${GREEN}║  Logs:     journalctl -u ${SERVICE_NAME} -f            ║${NC}"
echo -e "${GREEN}║  Reboot the Pi to test autostart + kiosk mode        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
