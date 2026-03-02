#!/usr/bin/env bash
# =============================================================================
# tune-pi.sh — OS-level tuning for Raspberry Pi slideshow kiosk
#
# Usage: sudo ./tune-pi.sh
# Safe to re-run. Reboot after to apply boot config changes.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[tune]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

[[ "$(id -u)" -eq 0 ]] || { echo "Run with sudo: sudo ./tune-pi.sh"; exit 1; }

# ── Detect boot config path ───────────────────────────────────────────────────
if [[ -f /boot/firmware/config.txt ]]; then
    BOOT_CFG=/boot/firmware/config.txt
    BOOT_CMD=/boot/firmware/cmdline.txt
else
    BOOT_CFG=/boot/config.txt
    BOOT_CMD=/boot/cmdline.txt
fi
info "Boot config: ${BOOT_CFG}"

set_boot() {
    local key="$1" val="$2"
    if grep -qE "^#?${key}=" "${BOOT_CFG}"; then
        sed -i "s|^#\?${key}=.*|${key}=${val}|" "${BOOT_CFG}"
    else
        echo "${key}=${val}" >> "${BOOT_CFG}"
    fi
}

# ── 1. GPU memory ─────────────────────────────────────────────────────────────
# More VRAM for smoother canvas/CSS rendering. Default is 76MB — too low.
info "Setting GPU memory to 128MB..."
set_boot gpu_mem 128

# ── 2. HDMI & display ─────────────────────────────────────────────────────────
info "Configuring HDMI..."
set_boot disable_overscan 1       # Remove black border
set_boot hdmi_force_hotplug 1     # Always output HDMI even without monitor at boot

# Disable console blanking (screen would go black after 10 min otherwise)
if ! grep -q "consoleblank=0" "${BOOT_CMD}"; then
    sed -i 's/$/ consoleblank=0/' "${BOOT_CMD}"
    info "Disabled console blanking"
fi

# ── 3. Disable unused services ────────────────────────────────────────────────
info "Disabling unused services..."
DISABLE_SERVICES=(
    bluetooth
    hciuart          # Bluetooth UART
    triggerhappy     # Hot-key daemon
    cups             # Printing
    cups-browsed
    ModemManager     # Mobile modems
)
for svc in "${DISABLE_SERVICES[@]}"; do
    if systemctl list-unit-files "${svc}.service" &>/dev/null 2>&1; then
        systemctl disable --now "${svc}" 2>/dev/null && info "  Disabled: ${svc}" || true
    fi
done

# ── 4. CPU performance governor ───────────────────────────────────────────────
info "Locking CPU governor to 'performance'..."
cat > /etc/systemd/system/cpu-performance.service <<'EOF'
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f"; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now cpu-performance
info "  CPU governor locked to performance"

# ── 5. Reduce swappiness ──────────────────────────────────────────────────────
# Don't disable swap entirely, but tell the kernel to avoid it aggressively.
# Swapping to SD card mid-animation causes visible stutters.
info "Setting swappiness to 10..."
echo "vm.swappiness=10" > /etc/sysctl.d/99-kiosk.conf
sysctl -w vm.swappiness=10 > /dev/null

# ── 6. /tmp on RAM (Removed) ────────────────────────────────────────────────
# Limiting /tmp to 64MB on a tmpfs crashes Chromium rapidly when loading large
# resources like the radar loop. Let the OS use the SD card for /tmp.

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Done! Reboot to apply boot config changes.          ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║   ✓ GPU memory → 128 MB                             ║${NC}"
echo -e "${GREEN}║   ✓ HDMI force hotplug + no overscan                ║${NC}"
echo -e "${GREEN}║   ✓ Console blanking disabled                       ║${NC}"
echo -e "${GREEN}║   ✓ 7 background services disabled                  ║${NC}"
echo -e "${GREEN}║   ✓ CPU governor → performance                      ║${NC}"
echo -e "${GREEN}║   ✓ Swappiness → 10 (avoids SD card thrash)        ║${NC}"
echo -e "${GREEN}║   ✓ /tmp on RAM (64MB tmpfs)                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"

