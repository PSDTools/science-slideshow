#!/usr/bin/env bash
# =============================================================================
# deploy.sh — FullPageOS deployment script for the Slideshow kiosk
#
# Assumes FullPageOS is already flashed and booted. Run this on the Pi via SSH.
#
# What this does:
#   1. Installs Node.js (via nvm) and pnpm
#   2. Builds the SvelteKit static app
#   3. Installs a systemd service (HTTP server + sync.py)
#   4. Configures FullPageOS to point at the app
#   5. Injects Pi 3 GPU-optimized Chromium flags
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
sudo apt-get install -y git curl python3 python3-requests --no-install-recommends

# ── 2. Node.js via nvm ───────────────────────────────────────────────────────
NVM_DIR="${USER_HOME}/.nvm"
if [[ ! -d "${NVM_DIR}" ]]; then
    info "Installing nvm..."
    sudo -u "${CURRENT_USER}" bash -c \
        "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
fi

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
info "Service started."

# ── 5. Configure FullPageOS ──────────────────────────────────────────────────
FPOS_TXT="/boot/firmware/fullpageos.txt"
if [[ -f "${FPOS_TXT}" ]]; then
    info "Setting FullPageOS URL → ${KIOSK_URL}"
    echo "${KIOSK_URL}" | sudo tee "${FPOS_TXT}" > /dev/null
elif [[ -f "/boot/fullpageos.txt" ]]; then
    # Older FullPageOS versions use /boot/ directly
    FPOS_TXT="/boot/fullpageos.txt"
    info "Setting FullPageOS URL → ${KIOSK_URL} (legacy path)"
    echo "${KIOSK_URL}" | sudo tee "${FPOS_TXT}" > /dev/null
else
    warn "fullpageos.txt not found — is this FullPageOS?"
fi

# ── 6. Inject Pi 3 GPU-optimized Chromium flags ─────────────────────────────
CHROMIUM_SCRIPT="/opt/custompios/scripts/start_chromium_browser"
if [[ -f "${CHROMIUM_SCRIPT}" ]]; then
    info "Injecting Pi 3 GPU flags into Chromium launcher..."
    # Check if we already patched it
    if ! grep -q "enable-gpu-rasterization" "${CHROMIUM_SCRIPT}"; then
        sudo sed -i '/^flags=(/,/)/ {
            /)/i\
   --enable-gpu-rasterization\
   --enable-zero-copy\
   --ignore-gpu-blocklist\
   --num-raster-threads=2\
   --use-gl=egl\
   --disable-smooth-scrolling\
   --disable-low-res-tiling\
   --disable-dev-shm-usage
        }' "${CHROMIUM_SCRIPT}"
        info "  GPU flags injected"
    else
        info "  GPU flags already present"
    fi
else
    warn "Chromium launcher not found at ${CHROMIUM_SCRIPT}"
fi

# ── 7. Run system tuning ────────────────────────────────────────────────────
if [[ -f "${APP_DIR}/tune-pi.sh" ]]; then
    info "Running system tuning..."
    sudo bash "${APP_DIR}/tune-pi.sh"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Deploy complete!                                    ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  App URL:  ${KIOSK_URL}                          ║${NC}"
echo -e "${GREEN}║  Service:  sudo systemctl status ${SERVICE_NAME}       ║${NC}"
echo -e "${GREEN}║  Logs:     journalctl -u ${SERVICE_NAME} -f            ║${NC}"
echo -e "${GREEN}║  Kiosk:    FullPageOS handles browser launch        ║${NC}"
echo -e "${GREEN}║  Reboot to apply all changes                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
