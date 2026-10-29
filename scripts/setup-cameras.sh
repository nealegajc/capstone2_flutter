#!/bin/bash
# ==============================================================================
# Smart Shelf 6-Camera Multi-Hub Persistent Setup Script
# Installs udev rules, unbinds camera audio interfaces, and configures video permissions.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_SRC="$SCRIPT_DIR/99-smart-shelf-cameras.rules"
RULES_DEST="/etc/udev/rules.d/99-smart-shelf-cameras.rules"

echo "=== Setting up Smart Shelf 6-Camera System ==="

# 1. Install Udev Rules
if [ -f "$RULES_SRC" ]; then
    echo "Installing persistent udev rules to $RULES_DEST..."
    sudo cp "$RULES_SRC" "$RULES_DEST"
    sudo chmod 644 "$RULES_DEST"
    echo "Reloading and triggering udev rules..."
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=video4linux
    sudo udevadm trigger --subsystem-match=usb
else
    echo "Error: $RULES_SRC not found!"
    exit 1
fi

# 2. Unbind Camera Audio Endpoints to free USB 2.0 bandwidth
echo "Disabling unused camera audio endpoints to maximize USB bandwidth..."
UNBIND_PATH="/sys/bus/usb/drivers/snd-usb-audio/unbind"
COUNT=0
for iface in /sys/bus/usb/drivers/snd-usb-audio/1-*:1.2 /sys/bus/usb/drivers/snd-usb-audio/1-*:1.3; do
    if [ -e "$iface" ]; then
        name=$(basename "$iface")
        echo "Unbinding audio interface: $name"
        echo -n "$name" | sudo tee "$UNBIND_PATH" > /dev/null 2>&1 || true
        COUNT=$((COUNT + 1))
    fi
done
echo "Unbound $COUNT audio interfaces."

# 3. Add user to video group
sudo usermod -a -G video "$USER" 2>/dev/null || true

# 4. Check persistent camera symlinks
echo ""
echo "=== Persistent Camera Status ==="
ls -l /dev/cam* 2>/dev/null || echo "Note: /dev/cam* symlinks will become active after replugging or running udevadm trigger as root."
ls -l /dev/v4l/by-name/ 2>/dev/null || true

echo ""
echo "=== Camera Setup Complete! ==="
