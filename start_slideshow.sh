#!/bin/bash
# Startup script for the slideshow system

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
MAX_RESTART_ATTEMPTS=5
RESTART_DELAY=10

echo "Slideshow directory: $SCRIPT_DIR"

# Wait for network
echo "Waiting for network..."
sleep 10

# Navigate to slideshow directory
cd "$SCRIPT_DIR"

# Check for config file
if [ ! -f "config.json" ]; then
    echo "ERROR: config.json not found!"
    echo "Please create config.json with your settings."
    exit 1
fi

# Start Flask server in background
echo "Starting Flask server..."
python3 server.py > server.log 2>&1 &
SERVER_PID=$!

# Wait for server to start
sleep 5

# Check if server started successfully
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "ERROR: Flask server failed to start. Check server.log for details."
    exit 1
fi

echo "Flask server running (PID: $SERVER_PID)"

# Hide mouse cursor (if unclutter is installed)
if command -v unclutter &> /dev/null; then
    unclutter -idle 0 &
fi

# Disable screen blanking
xset s off 2>/dev/null
xset -dpms 2>/dev/null
xset s noblank 2>/dev/null

# Function to start Chromium
start_chromium() {
    echo "Starting Chromium in kiosk mode..."
    chromium-browser \
        --kiosk \
        --noerrdialogs \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --disable-features=TranslateUI \
        --autoplay-policy=no-user-gesture-required \
        http://localhost:5000
}

# Main loop with restart protection
restart_count=0

while true; do
    start_chromium

    # Chromium exited
    restart_count=$((restart_count + 1))
    echo "Chromium exited (restart attempt $restart_count of $MAX_RESTART_ATTEMPTS)"

    if [ $restart_count -ge $MAX_RESTART_ATTEMPTS ]; then
        echo "Max restart attempts reached. Stopping."
        kill $SERVER_PID 2>/dev/null
        exit 1
    fi

    echo "Restarting in $RESTART_DELAY seconds..."
    sleep $RESTART_DELAY
done
