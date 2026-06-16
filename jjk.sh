#!/bin/bash

set -e

# =========================
# CONFIG
# =========================
SKIP_QCOW2_DOWNLOAD=0

VM_DIR="$HOME/qemu"
QCOW2_DISK="$VM_DIR/windows.qcow2"
VIRTIO_ISO="$VM_DIR/virtio-win.iso"
NOVNC_DIR="$HOME/noVNC"

OVMF_DIR="$VM_DIR/ovmf"
OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

mkdir -p "$VM_DIR"
mkdir -p "$OVMF_DIR"

# =========================
# INSTALL DEPENDENCIES
# =========================
apt update

apt install -y \
wget \
curl \
git \
qemu-system-x86 \
qemu-utils \
python3-websockify

# =========================
# INSTALL CLOUDFLARED
# =========================
if ! command -v cloudflared >/dev/null 2>&1; then
    wget -O /tmp/cloudflared.deb \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb

    dpkg -i /tmp/cloudflared.deb || apt -f install -y
fi

# =========================
# DOWNLOAD OVMF
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
# DOWNLOAD QCOW2
# =========================
if [ "$SKIP_QCOW2_DOWNLOAD" -ne 1 ]; then
    if [ ! -f "$QCOW2_DISK" ]; then
        echo "Downloading QCOW2..."
        wget -O "$QCOW2_DISK" "https://bit.ly/45hceMn"
    fi
fi

if [ ! -f "$QCOW2_DISK" ]; then
    echo "Creating QCOW2..."
    qemu-img create -f qcow2 "$QCOW2_DISK" 50G
fi

# =========================
# DOWNLOAD VIRTIO
# =========================
if [ ! -f "$VIRTIO_ISO" ]; then
    wget -O "$VIRTIO_ISO" \
    https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
fi

# =========================
# CLONE noVNC
# =========================
if [ ! -d "$NOVNC_DIR/.git" ]; then
    git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
fi

# =========================
# STOP OLD PROCESS
# =========================
pkill -f qemu-system-x86_64 || true
pkill -f novnc_proxy || true
pkill -f cloudflared || true

sleep 2

# =========================
# START QEMU
# TANPA KVM
# =========================
echo "Starting QEMU..."

nohup qemu-system-x86_64 \
-machine q35,accel=tcg \
-cpu qemu64 \
-smp 2 \
-m 4096 \
-vga std \
-net nic \
-net user \
-vnc :0 \
-display none \
-drive file="$QCOW2_DISK",format=qcow2 \
> /tmp/qemu.log 2>&1 &

sleep 10

# =========================
# CEK QEMU
# =========================
if ! pgrep -f qemu-system-x86_64 >/dev/null; then
    echo ""
    echo "QEMU FAILED!"
    echo ""
    cat /tmp/qemu.log
    exit 1
fi

# =========================
# START noVNC
# =========================
echo "Starting noVNC..."

nohup "$NOVNC_DIR/utils/novnc_proxy" \
--vnc localhost:5900 \
--listen 2016 \
> /tmp/novnc.log 2>&1 &

sleep 5

# =========================
# START CLOUDFLARE
# =========================
echo "Starting Cloudflare Tunnel..."

nohup cloudflared tunnel \
--no-autoupdate \
--url http://127.0.0.1:2016 \
> /tmp/cloudflared.log 2>&1 &

sleep 15

URL=$(grep -o 'https://[a-zA-Z0-9.-]*trycloudflare.com' /tmp/cloudflared.log | head -n1)

echo ""
echo "=========================================="

if [ -n "$URL" ]; then
    echo "Windows QEMU Ready"
    echo ""
    echo "$URL/vnc.html"
else
    echo "Cloudflare tunnel failed"
    echo ""
    cat /tmp/cloudflared.log
fi

echo "=========================================="
echo ""

# =========================
# KEEP ALIVE
# =========================
while true
do
    sleep 300
done
