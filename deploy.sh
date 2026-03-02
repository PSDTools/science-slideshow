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
sudo apt-get update
sudo apt-get install -y git curl unclutter \
    python3 python3-requests --no-install-recommends

# Chromium package name changed in Pi OS Bookworm (2023+)
if apt-cache show chromium &>/dev/null; then
    sudo apt-get install -y chromium --no-install-recommends
    CHROMIUM_BIN="chromium"
elif apt-cache show chromium-browser &>/dev/null; then
    sudo apt-get install -y chromium-browser --no-install-recommends
    CHROMIUM_BIN="chromium-browser"
else
    abort "Neither 'chromium' nor 'chromium-browser' found in apt. Install Chromium manually."
fi
info "Chromium binary: ${CHROMIUM_BIN}"

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

info "Stopping service during build..."
sudo systemctl stop "${SERVICE_NAME}" 2>/dev/null || true

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
WorkingDirectory=${APP_DIR}/svelte/build
Environment=PORT=${APP_PORT}
ExecStart=/usr/bin/env bash -c 'python3 ${APP_DIR}/sync.py & python3 -m http.server ${APP_PORT}'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"
info "Service started. Check with: sudo systemctl status ${SERVICE_NAME}"

# ── 5. Desktop autostart (kiosk launcher) ──────────────────────────────────
info "Installing kiosk autostart..."

LAUNCHER="${APP_DIR}/wait-and-launch.sh"
chmod +x "${LAUNCHER}"

# ── labwc (Raspberry Pi OS Bookworm default Wayland compositor) ────────────
LABWC_DIR="${USER_HOME}/.config/labwc"
sudo -u "${CURRENT_USER}" mkdir -p "${LABWC_DIR}"
sudo -u "${CURRENT_USER}" tee "${LABWC_DIR}/autostart" > /dev/null <<EOF
# Slideshow kiosk
${LAUNCHER} ${KIOSK_URL} &
EOF
info "  labwc autostart → ${LABWC_DIR}/autostart"

# ── wayfire ────────────────────────────────────────────────────────────────
WAYFIRE_DIR="${USER_HOME}/.config/wayfire"
sudo -u "${CURRENT_USER}" mkdir -p "${WAYFIRE_DIR}"
WAYFIRE_INI="${WAYFIRE_DIR}/wayfire.ini"
if [[ -f "${WAYFIRE_INI}" ]]; then
    # Append autostart if not already present
    if ! grep -q "wait-and-launch" "${WAYFIRE_INI}"; then
        sudo -u "${CURRENT_USER}" tee -a "${WAYFIRE_INI}" > /dev/null <<EOF

[autostart]
slideshow = ${LAUNCHER} ${KIOSK_URL}
EOF
    fi
else
    sudo -u "${CURRENT_USER}" tee "${WAYFIRE_INI}" > /dev/null <<EOF
[autostart]
slideshow = ${LAUNCHER} ${KIOSK_URL}
EOF
fi
info "  wayfire autostart → ${WAYFIRE_INI}"

# ── LXDE (legacy Pi OS) ───────────────────────────────────────────────────
LXDE_DIR="${USER_HOME}/.config/lxsession/LXDE-pi"
sudo -u "${CURRENT_USER}" mkdir -p "${LXDE_DIR}"
LXDE_AUTO="${LXDE_DIR}/autostart"
if [[ -f "${LXDE_AUTO}" ]]; then
    if ! grep -q "wait-and-launch" "${LXDE_AUTO}"; then
        echo "@${LAUNCHER} ${KIOSK_URL}" | sudo -u "${CURRENT_USER}" tee -a "${LXDE_AUTO}" > /dev/null
    fi
else
    sudo -u "${CURRENT_USER}" tee "${LXDE_AUTO}" > /dev/null <<EOF
@${LAUNCHER} ${KIOSK_URL}
EOF
fi
info "  LXDE autostart → ${LXDE_AUTO}"

# ── XDG autostart (fallback for other DEs) ────────────────────────────────
XDG_DIR="${USER_HOME}/.config/autostart"
sudo -u "${CURRENT_USER}" mkdir -p "${XDG_DIR}"
sudo -u "${CURRENT_USER}" tee "${XDG_DIR}/slideshow-kiosk.desktop" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Slideshow Kiosk
Exec=${LAUNCHER} ${KIOSK_URL}
X-GNOME-Autostart-enabled=true
EOF
info "  XDG autostart → ${XDG_DIR}/slideshow-kiosk.desktop"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Deploy complete!                                    ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  App URL:  ${KIOSK_URL}                          ║${NC}"
echo -e "${GREEN}║  Service:  sudo systemctl status ${SERVICE_NAME}       ║${NC}"
echo -e "${GREEN}║  Logs:     journalctl -u ${SERVICE_NAME} -f            ║${NC}"
echo -e "${GREEN}║  Kiosk:    Auto-launches in Chromium on boot      ║${NC}"
echo -e "${GREEN}║  Reboot the Pi to test autostart + kiosk mode        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
