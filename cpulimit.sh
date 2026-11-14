#!/bin/bash

set -e

echo "================================"
echo "     CPU LIMIT INSTALLER"
echo "     Powered by SHIVAMBROOG"
echo "================================"

cd "$HOME"

echo "[1/7] Downloading cpulimit..."
wget -q https://github.com/denji/cpulimit/archive/refs/heads/master.zip -O cpulimit.zip

echo "[2/7] Extracting files..."
unzip -oq cpulimit.zip

echo "[3/7] Entering source folder..."
cd "$HOME/cpulimit-master"

echo "[4/7] Compiling cpulimit..."
make

echo "[5/7] Installing to ~/bin..."
mkdir -p "$HOME/bin"
cp build/cpulimit "$HOME/bin/cpulimit"
chmod +x "$HOME/bin/cpulimit"

echo "[6/7] Updating PATH..."
touch "$HOME/.bashrc"

if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
fi

export PATH="$HOME/bin:$PATH"

echo "[7/7] Checking installation..."
"$HOME/bin/cpulimit" -V

echo "================================"
echo "     INSTALLATION SUCCESS!"
echo "     CPU LIMIT READY"
echo "================================"
