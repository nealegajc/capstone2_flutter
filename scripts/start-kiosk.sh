#!/usr/bin/env bash
# ==============================================================================
# Otto Scents Smart Shelf - Linux Touchscreen Kiosk Master Startup Orchestrator
# ==============================================================================
# This script handles complete unattended kiosk startup on boot:
# 1. Configures X11 display, disables screen sleep/blanking/DPMS
# 2. Configures multi-camera USB bandwidth and udev rules
# 3. Boots and verifies the Python Vision AI Backend (YOLO + PaddleOCR)
# 4. Launches and monitors the Flutter Linux Kiosk in fullscreen
# ==============================================================================

set -u

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="/tmp/smart-shelf-logs"
mkdir -p "$LOG_DIR"

# Singleton Lock: Prevent multiple concurrent instances from conflicting on display & cameras
LOCK_FILE="/tmp/smart-shelf-kiosk.lock"
if [ -f "$LOCK_FILE" ]; then
    PREV_PID="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    if [ -n "$PREV_PID" ] && [ "$PREV_PID" != "$$" ] && kill -0 "$PREV_PID" 2>/dev/null; then
        if grep -q -E "start-kiosk|smart_shelf" /proc/"$PREV_PID"/cmdline 2>/dev/null; then
            echo "Notice: Another kiosk instance is already running (PID $PREV_PID). Exiting duplicate launcher."
            exit 0
        fi
    fi
fi
echo "$$" > "$LOCK_FILE"

cleanup() {
    echo "Received termination signal, shutting down kiosk processes..."
    killall -9 smart_shelf_linux 2>/dev/null || true
    pkill -P $$ 2>/dev/null || true
    rm -f "$LOCK_FILE"
    exit 0
}
trap cleanup SIGTERM SIGINT SIGHUP

echo "=========================================================="
echo " Starting Otto Scents Smart Shelf Kiosk                   "
echo " Base Directory: $BASE_DIR                                "
echo " Logs Directory: $LOG_DIR                                "
echo "=========================================================="

# 1. Ensure Display and Prevent Screen Sleep / Blanking
export DISPLAY="${DISPLAY:-:0}"

if [ -z "${XAUTHORITY:-}" ] || [ ! -f "${XAUTHORITY:-}" ]; then
    UID_NUM="$(id -u)"
    if [ -f "/run/user/$UID_NUM/gdm/Xauthority" ]; then
        export XAUTHORITY="/run/user/$UID_NUM/gdm/Xauthority"
    elif [ -f "/run/user/$UID_NUM/Xauthority" ]; then
        export XAUTHORITY="/run/user/$UID_NUM/Xauthority"
    elif [ -f "$HOME/.Xauthority" ]; then
        export XAUTHORITY="$HOME/.Xauthority"
    fi
fi

# Wait for X server to become available
MAX_WAIT_X=30
WAITED_X=0
while ! xset q >/dev/null 2>&1; do
    echo "Waiting for X display ($DISPLAY)... ($WAITED_X/$MAX_WAIT_X s)"
    sleep 1
    WAITED_X=$((WAITED_X + 1))
    if [ "$WAITED_X" -ge "$MAX_WAIT_X" ]; then
        echo "Warning: X server not responding on $DISPLAY after $MAX_WAIT_X seconds. Proceeding anyway..."
        break
    fi
done

# Disable screen blanking, screensaver, and energy saving power-off
echo "Configuring display power settings (no blanking, no sleep)..."
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Hide mouse cursor when idle if unclutter is installed
if command -v unclutter >/dev/null 2>&1; then
    pkill -f "unclutter" 2>/dev/null || true
    # Prefer unclutter-xfixes (does not create fake input-intercepting windows)
    if unclutter --help 2>&1 | grep -q "hide-on-touch"; then
        unclutter --hide-on-touch --timeout 1 >/dev/null 2>&1 &
    else
        # For legacy unclutter, use -grab mode to prevent creating fake subwindows that eat the first touch
        unclutter -idle 1 -root -grab >/dev/null 2>&1 &
    fi
fi

# Disable GNOME Activities Overview and Workspace Switching upon boot
echo "Enforcing single workspace and disabling GNOME overview..."
gsettings set org.gnome.shell enabled-extensions "['no-overview@fthx', 'disable-workspace-switcher@jbradaric.me']" 2>/dev/null || true
gsettings set org.gnome.desktop.wm.preferences num-workspaces 1 2>/dev/null || true
gsettings set org.gnome.mutter dynamic-workspaces false 2>/dev/null || true
gsettings set org.gnome.desktop.interface enable-hot-corners false 2>/dev/null || true
gsettings set org.gnome.mutter edge-tiling false 2>/dev/null || true

# Optimize Touchscreen Input: Disable duplicate mouse emulation interface from wch.cn TouchScreen (27c0:0859)
# to prevent simultaneous conflicting mouse and touch events in X11
echo "Configuring and optimizing touchscreen input interfaces..."
if command -v xinput >/dev/null 2>&1; then
    for dev_id in $(xinput list --id-only 2>/dev/null); do
        if xinput list-props "$dev_id" 2>/dev/null | grep -q "10176, 2137"; then
            if xinput list-props "$dev_id" 2>/dev/null | grep -q "Natural Scrolling Enabled"; then
                echo "Disabling conflicting mouse emulation interface (device ID $dev_id)..."
                xinput disable "$dev_id" 2>/dev/null || true
            fi
        fi
    done
fi

# 2. Setup Cameras and Bandwidth
if [ -f "$BASE_DIR/scripts/setup-cameras.sh" ]; then
    echo "Running camera hardware and bandwidth configuration..."
    bash "$BASE_DIR/scripts/setup-cameras.sh" > "$LOG_DIR/camera-setup.log" 2>&1 || true
fi

# 3. Start Python Vision Backend (if not already running)
echo "Checking Python Vision AI backend service..."
if ! curl -s --max-time 2 http://127.0.0.1:8000/docs >/dev/null 2>&1; then
    echo "Starting Python Vision AI backend on http://127.0.0.1:8000..."
    if [ -f "$BASE_DIR/vision_backend/run_server.sh" ]; then
        nohup bash "$BASE_DIR/vision_backend/run_server.sh" > "$LOG_DIR/vision-backend.log" 2>&1 &
    fi

    # Wait for backend to become healthy (up to 20 seconds)
    echo "Waiting for Vision AI backend to respond..."
    MAX_WAIT=20
    WAITED=0
    while ! curl -s --max-time 1 http://127.0.0.1:8000/docs >/dev/null 2>&1; do
        sleep 1
        WAITED=$((WAITED + 1))
        if [ "$WAITED" -ge "$MAX_WAIT" ]; then
            echo "Warning: Vision backend did not respond within $MAX_WAIT seconds. Proceeding to launch UI..."
            break
        fi
    done
    echo "Vision backend ready after $WAITED seconds."
else
    echo "Vision backend is already running."
fi

# 4. Locate Flutter Linux Executable
RELEASE_BUNDLE="$BASE_DIR/build/linux/x64/release/bundle"
RELEASE_BIN="$RELEASE_BUNDLE/smart_shelf_linux"

# Ensure .env exists in release bundle if present in flutter project root
if [ -f "$BASE_DIR/.env" ] && [ -d "$RELEASE_BUNDLE" ]; then
    cp -u "$BASE_DIR/.env" "$RELEASE_BUNDLE/.env" 2>/dev/null || true
fi

# 5. Launch Flutter Kiosk with Automatic Crash-Recovery Watchdog
echo "Launching Otto Scents Smart Shelf Fullscreen Kiosk..."

while true; do
    if [ -x "$RELEASE_BIN" ]; then
        echo "Starting release binary: $RELEASE_BIN"
        cd "$RELEASE_BUNDLE"
        ./smart_shelf_linux >> "$LOG_DIR/kiosk-app.log" 2>&1
    elif [ -f "$BASE_DIR/pubspec.yaml" ]; then
        echo "Release bundle not found. Falling back to flutter run..."
        cd "$BASE_DIR"
        flutter run -d linux >> "$LOG_DIR/kiosk-app.log" 2>&1
    else
        echo "Error: Kiosk application binary or source code not found in $BASE_DIR!"
        sleep 10
        continue
    fi

    EXIT_CODE=$?
    echo "Kiosk application exited with code $EXIT_CODE at $(date)."
    echo "Restarting kiosk application in 3 seconds (Watchdog active)..."
    sleep 3
done
