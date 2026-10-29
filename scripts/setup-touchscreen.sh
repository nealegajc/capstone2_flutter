#!/usr/bin/env bash
# ==============================================================================
# Otto Scents Smart Shelf - Touchscreen Hardware & X11 Driver Optimizer
# ==============================================================================
# Configures udev and X11 for the wch.cn TouchScreen (USB 27c0:0859)
# 1. Binds touch digitizer events strictly to interface 00
# 2. Disables redundant mouse emulation interface (02) to prevent dual-cursor jitter
# ==============================================================================

set -euo pipefail

echo "Configuring touchscreen udev rules and X11 quirks..."

# 1. Install udev rule targeting interface 00 as touch and ignoring interface 02
UDEV_RULE_FILE="/etc/udev/rules.d/99-touchscreen.rules"
sudo tee "$UDEV_RULE_FILE" > /dev/null << 'EOF'
# Otto Scents Smart Shelf - wch.cn TouchScreen Optimization (27c0:0859)
# Interface 00: Multi-touch digitizer
ACTION=="add|change", KERNEL=="event*", ATTRS{idVendor}=="27c0", ATTRS{idProduct}=="0859", ATTRS{bInterfaceNumber}=="00", MODE="0666", GROUP="input", ENV{ID_INPUT}="1", ENV{ID_INPUT_TOUCHSCREEN}="1"

# Interface 02: Secondary mouse emulation - disable to eliminate duplicate conflicting events in X11
ACTION=="add|change", KERNEL=="event*", ATTRS{idVendor}=="27c0", ATTRS{idProduct}=="0859", ATTRS{bInterfaceNumber}=="02", ENV{ID_INPUT}="0", ENV{ID_INPUT_MOUSE}="0", ENV{ID_INPUT_TOUCHSCREEN}="0"
EOF

# 2. Install X11 quirk to ensure Xorg ignores the secondary mouse interface
XORG_CONF_DIR="/etc/X11/xorg.conf.d"
sudo mkdir -p "$XORG_CONF_DIR"
XORG_QUIRK_FILE="$XORG_CONF_DIR/99-touchscreen.conf"
sudo tee "$XORG_QUIRK_FILE" > /dev/null << 'EOF'
Section "InputClass"
    Identifier "Ignore wch.cn TouchScreen Mouse Emulation"
    MatchUSBID "27c0:0859"
    MatchIsPointer "on"
    Option "Ignore" "on"
EndSection
EOF

# 3. Reload and trigger udev
echo "Reloading udev rules..."
sudo udevadm control --reload-rules || true
sudo udevadm trigger --subsystem-match=input || true

echo "Touchscreen optimization rules successfully installed."
