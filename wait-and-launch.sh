#!/usr/bin/env bash
# =============================================================================
# wait-and-launch.sh — Wait for HTTP server, then launch Chromium in kiosk mode
#
# Called by desktop autostart. Loops until the app is ready, then opens
# Chromium with GPU-optimised flags for Raspberry Pi 3.
# =============================================================================

set -euo pipefail

URL="${1:-http://localhost:3000}"
LOG="/tmp/kiosk-launch.log"

echo "[kiosk] Waiting for ${URL} ..." | tee "${LOG}"

# Wait up to 60s for the HTTP server
for i in $(seq 1 60); do
    if curl -sf -o /dev/null "${URL}" 2>/dev/null; then
        echo "[kiosk] Server ready after ${i}s" | tee -a "${LOG}"
        break
    fi
    sleep 1
done

# Hide cursor
unclutter -idle 0.5 -root &

# Determine Chromium binary
if command -v chromium &>/dev/null; then
    CHROME=chromium
elif command -v chromium-browser &>/dev/null; then
    CHROME=chromium-browser
else
    echo "[kiosk] ERROR: No Chromium found" | tee -a "${LOG}"
    exit 1
fi

echo "[kiosk] Launching ${CHROME} → ${URL}" | tee -a "${LOG}"

# Launch with auto-restart on crash
while true; do
    "${CHROME}" \
        --kiosk \
        --enable-gpu-rasterization \
        --enable-zero-copy \
        --ignore-gpu-blocklist \
        --num-raster-threads=2 \
        --use-gl=egl \
        --disable-smooth-scrolling \
        --disable-low-res-tiling \
        --disable-dev-shm-usage \
        --noerrdialogs \
        --no-first-run \
        --disable-infobars \
        --password-store=basic \
        --disable-features=TranslateUI \
        --check-for-update-interval=31536000 \
        "${URL}" >> "${LOG}" 2>&1

    echo "[kiosk] Chromium exited ($?), restarting in 3s..." | tee -a "${LOG}"
    sleep 3
done
