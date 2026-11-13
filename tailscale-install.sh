#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="$HOME/tailscale"
STATE_DIR="$INSTALL_DIR/state"
SOCKET="$INSTALL_DIR/tailscaled.sock"
LOG="$INSTALL_DIR/tailscaled.log"
PIDFILE="$INSTALL_DIR/tailscaled.pid"
VERSION="1.104.6"

echo "================================"
echo "     TAILSCALE AUTO INSTALLER"
echo "     Powered by SHIVAMBROOG"
echo "================================"

# Architecture detection
ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        TS_ARCH="amd64"
        ;;
    aarch64|arm64)
        TS_ARCH="arm64"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "[OK] Architecture: $TS_ARCH"

# Dependencies
for CMD in curl tar nohup; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR: Missing command: $CMD"
        exit 1
    fi
done

mkdir -p "$INSTALL_DIR" "$STATE_DIR"
cd "$INSTALL_DIR"

# Download
ARCHIVE="tailscale_${VERSION}_${TS_ARCH}.tgz"
URL="https://pkgs.tailscale.com/stable/$ARCHIVE"

echo "[1/5] Downloading Tailscale..."

if [ ! -f "$ARCHIVE" ]; then
    curl -fL --retry 3 "$URL" -o "$ARCHIVE"
fi

# Extract
echo "[2/5] Extracting..."

tar -xzf "$ARCHIVE"

BINARY_DIR="$INSTALL_DIR/tailscale_${VERSION}_${TS_ARCH}"

if [ ! -x "$BINARY_DIR/tailscaled" ] ||
   [ ! -x "$BINARY_DIR/tailscale" ]; then
    echo "ERROR: Tailscale binaries not found."
    exit 1
fi

DAEMON="$BINARY_DIR/tailscaled"
CLIENT="$BINARY_DIR/tailscale"

# Stop old instance owned by this installer
echo "[3/5] Checking existing daemon..."

if [ -f "$PIDFILE" ]; then
    OLD_PID="$(cat "$PIDFILE")"
    if [[ "$OLD_PID" =~ ^[0-9]+$ ]] &&
       kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null || true
        sleep 2
    fi
    rm -f "$PIDFILE"
fi

# Start userspace daemon
echo "[4/5] Starting userspace networking..."

nohup "$DAEMON" \
    --tun=userspace-networking \
    --state="$STATE_DIR/tailscaled.state" \
    --socket="$SOCKET" \
    --socks5-server=127.0.0.1:1055 \
    >> "$LOG" 2>&1 </dev/null &

PID=$!
echo "$PID" > "$PIDFILE"

# Wait for socket
for i in $(seq 1 15); do
    if [ -S "$SOCKET" ]; then
        break
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "ERROR: Daemon stopped. Check $LOG"
        exit 1
    fi
    sleep 1
done

if [ ! -S "$SOCKET" ]; then
    echo "ERROR: Tailscale socket not created."
    echo "Check: $LOG"
    exit 1
fi

# Login
echo "[5/5] Opening Tailscale login..."

"$CLIENT" --socket="$SOCKET" up

echo
echo "================================"
echo "       INSTALLATION READY"
echo "================================"

"$CLIENT" --socket="$SOCKET" status

echo
echo "SOCKS5: 127.0.0.1:1055"
echo "LOG: $LOG"
echo "PID: $PIDFILE"
echo "================================"
