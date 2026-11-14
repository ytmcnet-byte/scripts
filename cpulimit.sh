#!/bin/bash

set -e

echo "=================================="
echo " CPU LIMIT INSTALLER"
echo " Powered by SHIVAMBROOG"
echo "=================================="

cd "$HOME"

echo "[1/7] Downloading..."
wget -q https://github.com/denji/cpulimit/archive/refs/heads/master.zip -O cpulimit.zip

echo "[2/7] Extracting..."
unzip -oq cpulimit.zip

echo "[3/7] Compiling..."
cd "$HOME/cpulimit-master"
make

echo "[4/7] Installing..."
mkdir -p "$HOME/bin"
cp build/cpulimit "$HOME/bin/cpulimit"
chmod +x "$HOME/bin/cpulimit"

echo "[5/7] Configuring PATH..."

for file in "$HOME/.bashrc" "$HOME/.profile"; do
    touch "$file"
    if ! grep -Fq 'export PATH="$HOME/bin:$PATH"' "$file"; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$file"
    fi
done

echo "[6/7] Updating current shell..."
export PATH="$HOME/bin:$PATH"
hash -r

echo "[7/7] Testing..."
if command -v cpulimit >/dev/null 2>&1; then
    cpulimit -V
else
    echo "ERROR: cpulimit command not found!"
    exit 1
fi

echo "=================================="
echo " INSTALLATION SUCCESSFUL!"
echo " Run: cpulimit -V"
echo "=================================="
