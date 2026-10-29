#!/bin/bash
# ==============================================================================
# Smart Shelf Camera Audio Disabler
# Disables snd-usb-audio driver binding for SunplusIT (5843:d527) & Jieli (5258:4a55)
# This prevents audio endpoint conflicts, USB bandwidth saturation, and camera freezes.
# ==============================================================================

set -e

echo "=== Disabling Audio on Smart Shelf Cameras ==="

UNBIND_PATH="/sys/bus/usb/drivers/snd-usb-audio/unbind"
COUNT=0

# Unbind all camera audio interfaces on USB bus 1 (interfaces :1.2 and :1.3)
for iface in /sys/bus/usb/drivers/snd-usb-audio/1-*:1.2 /sys/bus/usb/drivers/snd-usb-audio/1-*:1.3; do
  if [ -e "$iface" ]; then
    name=$(basename "$iface")
    echo "Unbinding audio interface: $name"
    echo -n "$name" | sudo tee "$UNBIND_PATH" > /dev/null 2>&1 || true
    COUNT=$((COUNT + 1))
  fi
done

echo "Successfully unbound $COUNT audio interfaces."
echo "=== Done! Camera audio interfaces disabled ==="

