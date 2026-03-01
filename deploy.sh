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
sudo apt-get install -y curl git unclutter --no-install-recommends

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

# ── 5. Kiosk launcher script ──────────────────────────────────────────────────
info "Writing kiosk launcher..."
LAUNCH_SCRIPT="${APP_DIR}/wait-and-launch.sh"

sudo -u "${CURRENT_USER}" tee "${LAUNCH_SCRIPT}" > /dev/null <<EOF
#!/usr/bin/env bash
# Launched by systemd --user after graphical-session.target.
# Waits for the SvelteKit server, then opens Chromium in kiosk mode.
URL="${KIOSK_URL}"
CHROMIUM="${CHROMIUM_BIN}"

# Disable screen blanking (X11)
if command -v xset &>/dev/null; then
    xset s off s noblank -dpms 2>/dev/null || true
fi

# Hide cursor after 1s idle (X11 only; no-op on Wayland)
if command -v unclutter &>/dev/null; then
    unclutter -idle 1 -root &
fi

# Wait up to 30s for the Node server
for i in \$(seq 1 30); do
    curl -sf "\${URL}" > /dev/null 2>&1 && break
    sleep 1
done

exec "\${CHROMIUM}" \\
    --kiosk \\
    --noerr \\
    --disable-infobars \\
    --no-first-run \\
    --disable-restore-session-state \\
    --disable-session-crashed-bubble \\
    --disable-translate \\
    --disable-features=TranslateUI \\
    --check-for-update-interval=31536000 \\
    --ozone-platform-hint=auto \\
    --enable-gpu-rasterization \\
    --enable-zero-copy \\
    --num-raster-threads=2 \\
    "\${URL}"
EOF
chmod +x "${LAUNCH_SCRIPT}"

# ── 6. Boot to desktop with autologin ────────────────────────────────────────
info "Configuring Pi to boot to Desktop Autologin..."
if command -v raspi-config &>/dev/null; then
    sudo raspi-config nonint do_boot_behaviour B4
    info "Boot behaviour set to Desktop Autologin (B4)"
else
    warn "raspi-config not found — set boot to 'Desktop Autologin' manually via: sudo raspi-config"
fi

# ── 7. Kiosk autostart — all three mechanisms ─────────────────────────────────
info "Installing kiosk autostart (systemd user + XDG + LXDE + Wayfire)..."

# 7a. systemd --user service (most reliable, works on all desktops)
SYSTEMD_USER_DIR="${USER_HOME}/.config/systemd/user"
sudo -u "${CURRENT_USER}" mkdir -p "${SYSTEMD_USER_DIR}"
sudo -u "${CURRENT_USER}" tee "${SYSTEMD_USER_DIR}/slideshow-kiosk.service" > /dev/null <<EOF
[Unit]
Description=Slideshow Kiosk Browser
After=graphical-session.target network.target
Wants=graphical-session.target

[Service]
Type=simple
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u "${CURRENT_USER}")
ExecStartPre=/bin/sleep 5
ExecStart=${LAUNCH_SCRIPT}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical-session.target
EOF

# Enable the user service (persists across reboots)
sudo -u "${CURRENT_USER}" \
    XDG_RUNTIME_DIR="/run/user/$(id -u "${CURRENT_USER}")" \
    systemctl --user enable slideshow-kiosk.service 2>/dev/null || \
    loginctl enable-linger "${CURRENT_USER}"

# 7b. XDG autostart .desktop (GNOME, LXQt, etc.)
AUTOSTART_DIR="${USER_HOME}/.config/autostart"
sudo -u "${CURRENT_USER}" mkdir -p "${AUTOSTART_DIR}"
sudo -u "${CURRENT_USER}" tee "${AUTOSTART_DIR}/slideshow-kiosk.desktop" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Slideshow Kiosk
Exec=${LAUNCH_SCRIPT}
X-GNOME-Autostart-enabled=true
EOF

# 7c. LXDE autostart (Pi OS Bullseye and older)
LXDE_AUTOSTART="${USER_HOME}/.config/lxsession/LXDE-pi/autostart"
if [[ -d "$(dirname "${LXDE_AUTOSTART}")" ]]; then
    [[ -f "${LXDE_AUTOSTART}" ]] || \
        sudo -u "${CURRENT_USER}" cp /etc/xdg/lxsession/LXDE-pi/autostart "${LXDE_AUTOSTART}" 2>/dev/null || \
        sudo -u "${CURRENT_USER}" touch "${LXDE_AUTOSTART}"
    if ! grep -q "wait-and-launch" "${LXDE_AUTOSTART}" 2>/dev/null; then
        echo "@${LAUNCH_SCRIPT}" | sudo -u "${CURRENT_USER}" tee -a "${LXDE_AUTOSTART}" > /dev/null
        info "Added entry to LXDE autostart"
    fi
fi

# 7d. Wayfire autostart (Pi OS Bookworm with Wayfire compositor)
WAYFIRE_INI="${USER_HOME}/.config/wayfire.ini"
if [[ -f "${WAYFIRE_INI}" ]]; then
    if ! grep -q "slideshow" "${WAYFIRE_INI}"; then
        printf '\n[autostart]\nslideshow = %s\n' "${LAUNCH_SCRIPT}" | \
            sudo -u "${CURRENT_USER}" tee -a "${WAYFIRE_INI}" > /dev/null
        info "Added entry to Wayfire autostart"
    fi
fi

# 7e. labwc autostart (Pi OS Bookworm with labwc compositor — default since late 2024)
LABWC_AUTOSTART="${USER_HOME}/.config/labwc/autostart"
if [[ -d "$(dirname "${LABWC_AUTOSTART}")" ]] || command -v labwc &>/dev/null; then
    sudo -u "${CURRENT_USER}" mkdir -p "$(dirname "${LABWC_AUTOSTART}")"
    if ! grep -q "wait-and-launch" "${LABWC_AUTOSTART}" 2>/dev/null; then
        echo "${LAUNCH_SCRIPT} &" | sudo -u "${CURRENT_USER}" tee -a "${LABWC_AUTOSTART}" > /dev/null
        info "Added entry to labwc autostart"
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
