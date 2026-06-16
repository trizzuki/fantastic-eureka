#!/bin/bash

set -e

# =========================
# Config
# =========================
SKIP_QCOW2_DOWNLOAD=0

VM_DIR="$HOME/qemu"
QCOW2_DISK="$VM_DIR/windows.qcow2"
VIRTIO_ISO="$VM_DIR/virtio-win.iso"
NOVNC_DIR="$HOME/noVNC"

OVMF_DIR="$HOME/qemu/ovmf"
OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

mkdir -p "$OVMF_DIR"
mkdir -p "$VM_DIR"

# =========================
# Install Dependency
# =========================
sudo apt update

sudo apt install -y \
qemu-system-x86 \
qemu-utils \
git \
wget \
python3-websockify \
curl

# =========================
# Download OVMF
# =========================
if [ ! -f "$OVMF_CODE" ]; then
    wget -O "$OVMF_CODE" \
    https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
fi

if [ ! -f "$OVMF_VARS" ]; then
    wget -O "$OVMF_VARS" \
    https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
fi

# =========================
# Download QCOW2
# =========================
if [ "$SKIP_QCOW2_DOWNLOAD" -ne 1 ]; then
    if [ ! -f "$QCOW2_DISK" ]; then
        wget -O "$QCOW2_DISK" https://bit.ly/45hceMn
    fi
fi

if [ ! -f "$QCOW2_DISK" ]; then
    qemu-img create -f qcow2 "$QCOW2_DISK" 50G
fi

# =========================
# VirtIO
# =========================
if [ ! -f "$VIRTIO_ISO" ]; then
    wget -O "$VIRTIO_ISO" \
    https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
fi

# =========================
# noVNC
# =========================
if [ ! -d "$NOVNC_DIR/.git" ]; then
    git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
fi

# =========================
# Cloudflared
# =========================
if ! command -v cloudflared >/dev/null 2>&1; then
    wget -O cloudflared.deb \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb

    sudo dpkg -i cloudflared.deb || sudo apt -f install -y
fi

# =========================
# Kill old process
# =========================
pkill -f qemu-system-x86_64 || true
pkill -f novnc_proxy || true
pkill -f cloudflared || true

# =========================
# Start QEMU
# =========================
nohup qemu-system-x86_64 \
-enable-kvm \
-cpu host \
-smp 8 \
-m 28672 \
-M q35 \
-device usb-tablet \
-device virtio-balloon-pci \
-vga virtio \
-net nic,model=virtio-net-pci \
-net user,hostfwd=tcp::3389-:3389 \
-boot c \
-device virtio-serial-pci \
-device virtio-rng-pci \
-drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
-drive if=pflash,format=raw,file="$OVMF_VARS" \
-drive file="$QCOW2_DISK",format=qcow2,if=virtio \
-drive file="$VIRTIO_ISO",media=cdrom \
-vnc :0 \
-display none \
> /tmp/qemu.log 2>&1 &

sleep 5

# =========================
# Start noVNC
# =========================
nohup "$NOVNC_DIR/utils/novnc_proxy" \
--vnc localhost:5900 \
--listen 2016 \
> /tmp/novnc.log 2>&1 &

sleep 5

# =========================
# Start Cloudflare Tunnel
# =========================
nohup cloudflared tunnel \
--no-autoupdate \
--url http://localhost:2016 \
> /tmp/cloudflared.log 2>&1 &

sleep 10

URL=$(grep -o 'https://[a-zA-Z0-9.-]*trycloudflare.com' /tmp/cloudflared.log | head -n1)

echo ""
echo "======================================"
echo "Windows Ready"
echo "$URL/vnc.html"
echo "======================================"
echo ""

while true
do
    sleep 300
done
