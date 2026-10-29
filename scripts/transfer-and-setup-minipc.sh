#!/usr/bin/env bash
# ==============================================================================
# Otto Scents Smart Shelf - Mini PC Deployment & Autostart Setup Script
# ==============================================================================
# Usage:
#   On Host (Build & Package):
#     ./scripts/transfer-and-setup-minipc.sh --package
#
#   On Mini PC (Automated Setup & Autostart Config):
#     ./scripts/transfer-and-setup-minipc.sh --install
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCHIVE_NAME="smart_shelf_kiosk_deployment.tar.gz"

package_kiosk() {
    echo "=========================================================="
    echo " [1/4] Building Otto Scents Flutter Linux Release Bundle "
    echo "=========================================================="
    cd "$BASE_DIR"
    
    if ! command -v flutter >/dev/null 2>&1; then
        if [ -x "$HOME/flutter/bin/flutter" ]; then
            export PATH="$PATH:$HOME/flutter/bin"
        fi
    fi

    if ! command -v flutter >/dev/null 2>&1; then
        echo "Error: flutter CLI not found in PATH or $HOME/flutter/bin. Please install Flutter SDK."
        exit 1
    fi

    echo "Running flutter build linux --release..."
    flutter build linux --release

    BUNDLE_DIR="$BASE_DIR/build/linux/x64/release/bundle"
    if [ ! -d "$BUNDLE_DIR" ]; then
        echo "Error: Release bundle not found at $BUNDLE_DIR"
        exit 1
    fi

    echo "=========================================================="
    echo " [2/4] Syncing Assets, Weights, and Environment Config    "
    echo "=========================================================="
    # Copy .env if present
    if [ -f "$BASE_DIR/.env" ]; then
        cp "$BASE_DIR/.env" "$BUNDLE_DIR/.env"
        echo "Copied .env to release bundle."
    fi

    # Copy camera assignments if present
    if [ -f "$BASE_DIR/camera_assignments.json" ]; then
        cp "$BASE_DIR/camera_assignments.json" "$BUNDLE_DIR/camera_assignments.json"
        echo "Copied camera_assignments.json to release bundle."
    fi

    # Copy best.pt weights
    if [ -f "$BASE_DIR/best.pt" ]; then
        cp "$BASE_DIR/best.pt" "$BUNDLE_DIR/best.pt"
        echo "Copied best.pt model weights."
    fi

    echo "=========================================================="
    echo " [3/4] Creating Deployment Tarball: $ARCHIVE_NAME        "
    echo "=========================================================="
    cd "$BASE_DIR"

    # Ensure scripts have execute permission
    chmod +x scripts/*.sh

    tar --exclude='vision_backend/venv' \
        --exclude='vision_backend/__pycache__' \
        --exclude='.dart_tool' \
        --exclude='build/linux/x64/debug' \
        -czvf "$ARCHIVE_NAME" \
        build/linux/x64/release/bundle \
        best.pt \
        .env \
        camera_assignments.json \
        vision_backend \
        scripts

    echo "=========================================================="
    echo " [4/4] Package Ready!                                    "
    echo " File: $BASE_DIR/$ARCHIVE_NAME                            "
    echo " Size: $(du -h "$BASE_DIR/$ARCHIVE_NAME" | cut -f1)      "
    echo "=========================================================="
    echo ""
    echo "To transfer and deploy to the Mini PC, run:"
    echo "  1. scp $BASE_DIR/$ARCHIVE_NAME <user>@<minipc-ip>:~/"
    echo "  2. ssh <user>@<minipc-ip>"
    echo "  3. mkdir -p ~/capstone-flutter && tar -xzvf ~/$ARCHIVE_NAME -C ~/capstone-flutter"
    echo "  4. cd ~/capstone-flutter && ./scripts/transfer-and-setup-minipc.sh --install"
    echo ""
}

install_kiosk() {
    echo "=========================================================="
    echo " Installing Otto Scents Smart Shelf Kiosk on Mini PC     "
    echo " Working Directory: $BASE_DIR                             "
    echo " User: $USER                                              "
    echo "=========================================================="

    # 1. System dependencies
    echo "[1/6] Installing necessary Linux packages..."
    sudo apt-get update -y
    sudo apt-get install -y \
        curl \
        x11-xserver-utils \
        v4l-utils \
        libgtk-3-0 \
        libblkid1 \
        liblzma5 \
        unclutter-xfixes \
        ffmpeg \
        xinput \
        gnome-shell-extensions-extra \
        python3 \
        python3-pip \
        python3-venv \
        libgl1 \
        libglib2.0-0

    # 2. Permissions
    echo "[2/6] Configuring user device permissions (video, dialout)..."
    sudo usermod -a -G video "$USER" 2>/dev/null || true
    sudo usermod -a -G dialout "$USER" 2>/dev/null || true

    # 3. Setup Cameras and Touchscreen udev rules
    echo "[3/6] Installing persistent camera & touchscreen udev rules..."
    if [ -f "$BASE_DIR/scripts/setup-cameras.sh" ]; then
        chmod +x "$BASE_DIR/scripts"/*.sh
        bash "$BASE_DIR/scripts/setup-cameras.sh"
    fi
    if [ -f "$BASE_DIR/scripts/setup-touchscreen.sh" ]; then
        bash "$BASE_DIR/scripts/setup-touchscreen.sh"
    fi

    # 4. Setup Python Vision AI Environment
    echo "[4/6] Setting up Python Vision AI virtual environment..."
    cd "$BASE_DIR/vision_backend"
    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    source venv/bin/activate
    pip install --upgrade pip
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    fi
    deactivate

    # 5. Setup XDG Autostart & Global Symlink
    echo "[5/6] Configuring XDG Autostart for automated boot launch..."
    sudo ln -sf "$BASE_DIR/scripts/start-kiosk.sh" /usr/local/bin/start-kiosk.sh
    sudo chmod +x "$BASE_DIR/scripts/start-kiosk.sh" /usr/local/bin/start-kiosk.sh

    AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cp "$BASE_DIR/scripts/smart-shelf-kiosk.desktop" "$AUTOSTART_DIR/smart-shelf-kiosk.desktop"
    chmod 644 "$AUTOSTART_DIR/smart-shelf-kiosk.desktop"

    # Also install user systemd unit if preferred
    SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_USER_DIR"
    cp "$BASE_DIR/scripts/smart-shelf-kiosk.service" "$SYSTEMD_USER_DIR/smart-shelf-kiosk.service"
    systemctl --user daemon-reload 2>/dev/null || true

    # 6. Disable screen lock / sleep in GNOME/X11 if gsettings exists
    echo "[6/6] Disabling screen lock, screensaver, sleep, and configuring fast boot..."
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
        gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
        gsettings set org.gnome.shell enabled-extensions "['no-overview@fthx', 'disable-workspace-switcher@jbradaric.me']" 2>/dev/null || true
        gsettings set org.gnome.desktop.wm.preferences num-workspaces 1 2>/dev/null || true
        gsettings set org.gnome.mutter dynamic-workspaces false 2>/dev/null || true
        gsettings set org.gnome.desktop.interface enable-hot-corners false 2>/dev/null || true
        gsettings set org.gnome.mutter edge-tiling false 2>/dev/null || true
    fi

    # Set GRUB boot timeout to 0 for instant boot
    if [ -f "/etc/default/grub" ]; then
        echo "Setting GRUB boot menu timeout to 0 seconds..."
        sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0\nGRUB_TIMEOUT_STYLE=hidden\nGRUB_RECORDFAIL_TIMEOUT=0/' /etc/default/grub 2>/dev/null || true
        sudo update-grub 2>/dev/null || true
    fi

    echo "=========================================================="
    echo " Kiosk Installation & Autostart Successfully Configured!  "
    echo "=========================================================="
    echo ""
    echo "Key Verification Steps:"
    echo "  1. Test launch right now by running:"
    echo "     bash $BASE_DIR/scripts/start-kiosk.sh"
    echo ""
    echo "  2. Ensure Automatic Login is enabled on Mini PC:"
    echo "     - In Ubuntu/Debian Settings -> Users -> Automatic Login: ON"
    echo "     - Or edit /etc/gdm3/custom.conf (or /etc/lightdm/lightdm.conf)"
    echo "       AutomaticLoginEnable=True"
    echo "       AutomaticLogin=$USER"
    echo ""
    echo "  3. Reboot the Mini PC to test full automated kiosk startup:"
    echo "     sudo reboot"
    echo "=========================================================="
}

case "${1:-}" in
    --package)
        package_kiosk
        ;;
    --install)
        install_kiosk
        ;;
    *)
        echo "Otto Scents Mini PC Kiosk Deployment Tool"
        echo ""
        echo "Usage:"
        echo "  $0 --package   Build Flutter release and package deployment tarball on host"
        echo "  $0 --install   Install dependencies, udev rules, and autostart on Mini PC"
        echo ""
        exit 1
        ;;
esac
