#!/usr/bin/env bash
# =============================================================================
# prepare-sd.sh — Prepare a FullPageOS SD card for the Slideshow kiosk
#
# Run this on your Mac AFTER flashing FullPageOS with RPi Imager.
# The SD card's boot partition must be mounted (re-insert if Imager ejected it).
#
# What this does:
#   1. Copies the pre-built static site + sync.py + config onto the boot partition
#   2. Creates a first-boot setup script that auto-deploys everything on the Pi
#   3. Sets the FullPageOS kiosk URL to http://localhost:3000
#
# After running this: eject the SD card, insert into Pi, power on. Done.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[prep]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
abort() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PORT="3000"

# ── Preflight ────────────────────────────────────────────────────────────────
[[ -d "${SCRIPT_DIR}/svelte/build" ]] || abort "No build found. Run: cd svelte && pnpm build"
[[ -f "${SCRIPT_DIR}/sync.py" ]]      || abort "Missing sync.py"
[[ -f "${SCRIPT_DIR}/config.json" ]]  || abort "Missing config.json"

# ── Find boot partition ──────────────────────────────────────────────────────
BOOT=""
for candidate in /Volumes/bootfs /Volumes/boot /Volumes/BOOT; do
    if [[ -d "$candidate" ]]; then
        BOOT="$candidate"
        break
    fi
done

if [[ -z "$BOOT" ]]; then
    echo ""
    echo "Could not find the FullPageOS boot partition."
    echo "Expected one of: /Volumes/bootfs, /Volumes/boot"
    echo ""
    echo "If RPi Imager ejected the SD card, re-insert it and try again."
    # List available volumes for debugging
    echo ""
    echo "Available volumes:"
    ls /Volumes/ 2>/dev/null || true
    exit 1
fi

info "Found boot partition: ${BOOT}"

# Verify this looks like a FullPageOS boot partition
if [[ ! -f "${BOOT}/config.txt" ]]; then
    warn "No config.txt found — this might not be a Raspberry Pi boot partition"
fi

# ── Copy payload ─────────────────────────────────────────────────────────────
PAYLOAD="${BOOT}/slideshow"
info "Copying payload to ${PAYLOAD}..."

rm -rf "${PAYLOAD}"
mkdir -p "${PAYLOAD}/svelte"

# Pre-built static site
cp -r "${SCRIPT_DIR}/svelte/build" "${PAYLOAD}/svelte/build"

# Sync script, config, tuning
cp "${SCRIPT_DIR}/sync.py"     "${PAYLOAD}/"
cp "${SCRIPT_DIR}/config.json" "${PAYLOAD}/"
cp "${SCRIPT_DIR}/tune-pi.sh"  "${PAYLOAD}/"

PAYLOAD_SIZE=$(du -sh "${PAYLOAD}" | cut -f1)
info "Payload copied (${PAYLOAD_SIZE})"

# ── Set FullPageOS kiosk URL ─────────────────────────────────────────────────
info "Setting kiosk URL → http://localhost:${APP_PORT}"
echo "http://localhost:${APP_PORT}" > "${BOOT}/fullpageos.txt"

# ── Create first-boot setup script ──────────────────────────────────────────
info "Creating first-boot setup script..."
cat > "${BOOT}/slideshow-setup.sh" << 'SETUP_EOF'
#!/bin/bash
# =============================================================================
# slideshow-setup.sh — First-boot auto-deploy for Slideshow kiosk
# Runs once on the Pi, then cleans up after itself.
# =============================================================================

exec > >(tee /var/log/slideshow-setup.log) 2>&1
echo "[setup] Starting slideshow first-boot setup at $(date)"

APP_PORT="3000"
APP_DIR="/home/pi/Slideshow"
BOOT_DIR="/boot/firmware"
SERVICE_NAME="slideshow"

# If /boot/firmware doesn't exist, try /boot (older Pi OS)
[[ -d "${BOOT_DIR}" ]] || BOOT_DIR="/boot"

PAYLOAD="${BOOT_DIR}/slideshow"

if [[ ! -d "${PAYLOAD}" ]]; then
    echo "[setup] ERROR: Payload not found at ${PAYLOAD}"
    exit 1
fi

# ── 1. Copy files to final location ─────────────────────────────────────────
echo "[setup] Copying files to ${APP_DIR}..."
mkdir -p "${APP_DIR}/svelte"
cp -r "${PAYLOAD}/svelte/build" "${APP_DIR}/svelte/build"
cp "${PAYLOAD}/sync.py"         "${APP_DIR}/"
cp "${PAYLOAD}/config.json"     "${APP_DIR}/"
cp "${PAYLOAD}/tune-pi.sh"      "${APP_DIR}/"

# Figure out the actual user (pi or whatever RPi Imager configured)
PI_USER="pi"
if id pi &>/dev/null; then
    PI_USER="pi"
elif [[ -n "$(ls /home/ 2>/dev/null | head -1)" ]]; then
    PI_USER="$(ls /home/ | head -1)"
    APP_DIR="/home/${PI_USER}/Slideshow"
    # Re-copy if user isn't pi
    if [[ "${PI_USER}" != "pi" ]]; then
        mkdir -p "${APP_DIR}/svelte"
        cp -r "${PAYLOAD}/svelte/build" "${APP_DIR}/svelte/build"
        cp "${PAYLOAD}/sync.py"         "${APP_DIR}/"
        cp "${PAYLOAD}/config.json"     "${APP_DIR}/"
        cp "${PAYLOAD}/tune-pi.sh"      "${APP_DIR}/"
    fi
fi

chown -R "${PI_USER}:${PI_USER}" "${APP_DIR}"
echo "[setup] Files deployed for user: ${PI_USER}"

# ── 2. Install python3-requests ──────────────────────────────────────────────
echo "[setup] Installing python3-requests..."
apt-get update -qq
apt-get install -y python3-requests --no-install-recommends

# ── 3. Create systemd service ───────────────────────────────────────────────
echo "[setup] Creating systemd service: ${SERVICE_NAME}..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SVC
[Unit]
Description=Slideshow App (HTTP server + sync)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${PI_USER}
WorkingDirectory=${APP_DIR}/svelte/build
ExecStart=/usr/bin/env bash -c 'python3 ${APP_DIR}/sync.py & python3 -m http.server ${APP_PORT}'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
echo "[setup] Service installed and enabled"

# ── 4. Inject Pi 3 GPU-optimized Chromium flags ─────────────────────────────
CHROMIUM_SCRIPT="/opt/custompios/scripts/start_chromium_browser"
if [[ -f "${CHROMIUM_SCRIPT}" ]]; then
    echo "[setup] Injecting Chromium GPU flags..."
    if ! grep -q "enable-gpu-rasterization" "${CHROMIUM_SCRIPT}"; then
        sed -i '/^flags=(/,/)/ {
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
        echo "[setup] GPU flags injected"
    else
        echo "[setup] GPU flags already present"
    fi
else
    echo "[setup] WARNING: Chromium launcher not found at ${CHROMIUM_SCRIPT}"
fi

# ── 5. Run system tuning ────────────────────────────────────────────────────
echo "[setup] Running system tuning..."
bash "${APP_DIR}/tune-pi.sh"

# ── 6. Clean up payload from boot partition ──────────────────────────────────
echo "[setup] Cleaning up boot partition..."
rm -rf "${PAYLOAD}"
rm -f "${BOOT_DIR}/slideshow-setup.sh"

echo "[setup] First-boot setup complete at $(date)"
echo "[setup] Rebooting to apply all changes..."

# Force a reboot to apply boot config changes from tune-pi.sh
sleep 2
reboot
SETUP_EOF

chmod +x "${BOOT}/slideshow-setup.sh"

# ── Hook into firstrun.sh ───────────────────────────────────────────────────
# RPi Imager may have created firstrun.sh (for WiFi, user creation, etc.)
# We append our setup call. If no firstrun.sh exists, we create one.

if [[ -f "${BOOT}/firstrun.sh" ]]; then
    info "Found existing firstrun.sh (RPi Imager) — appending setup hook..."
    # Insert our setup call before the cleanup at the end of firstrun.sh
    # RPi Imager's firstrun.sh typically ends with:
    #   rm -f /boot/firmware/firstrun.sh
    #   sed -i ... cmdline.txt
    #   exit 0
    # We insert our call before the 'rm -f' line
    if grep -q "rm -f.*firstrun.sh" "${BOOT}/firstrun.sh"; then
        sed -i '' '/rm -f.*firstrun\.sh/i\
\
# ── Slideshow kiosk auto-deploy ──\
bash /boot/firmware/slideshow-setup.sh || bash /boot/slideshow-setup.sh || true\
' "${BOOT}/firstrun.sh"
    else
        # No standard cleanup found — just append
        echo "" >> "${BOOT}/firstrun.sh"
        echo "# ── Slideshow kiosk auto-deploy ──" >> "${BOOT}/firstrun.sh"
        echo 'bash /boot/firmware/slideshow-setup.sh || bash /boot/slideshow-setup.sh || true' >> "${BOOT}/firstrun.sh"
    fi
else
    info "No firstrun.sh found — creating one..."
    cat > "${BOOT}/firstrun.sh" << 'FIRSTRUN_EOF'
#!/bin/bash
set +e

# ── Slideshow kiosk auto-deploy ──
bash /boot/firmware/slideshow-setup.sh || bash /boot/slideshow-setup.sh || true

rm -f /boot/firmware/firstrun.sh
sed -i 's| systemd\.[^ ]*||g' /boot/firmware/cmdline.txt
exit 0
FIRSTRUN_EOF
    chmod +x "${BOOT}/firstrun.sh"

    # Add the systemd.run trigger to cmdline.txt so firstrun.sh actually executes
    CMDLINE="${BOOT}/cmdline.txt"
    if [[ -f "${CMDLINE}" ]]; then
        if ! grep -q "systemd.run=" "${CMDLINE}"; then
            info "Adding firstrun trigger to cmdline.txt..."
            # Append to the single line in cmdline.txt
            sed -i '' 's|$| systemd.run=/boot/firmware/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target|' "${CMDLINE}"
        fi
    else
        warn "cmdline.txt not found — firstrun.sh may not execute automatically"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  SD card prepared!                                       ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  1. Eject the SD card                                    ║${NC}"
echo -e "${GREEN}║  2. Insert into Pi 3                                     ║${NC}"
echo -e "${GREEN}║  3. Power on                                             ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║  First boot will:                                        ║${NC}"
echo -e "${GREEN}║    • Deploy the slideshow app                            ║${NC}"
echo -e "${GREEN}║    • Install dependencies (needs WiFi)                   ║${NC}"
echo -e "${GREEN}║    • Configure Chromium GPU flags                        ║${NC}"
echo -e "${GREEN}║    • Tune system for kiosk performance                   ║${NC}"
echo -e "${GREEN}║    • Reboot into the running kiosk                       ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║  Setup log: /var/log/slideshow-setup.log                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
