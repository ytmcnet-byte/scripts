#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting cpulimit installation..."

cd ~
wget https://github.com/denji/cpulimit/archive/refs/heads/master.zip -O cpulimit.zip
unzip cpulimit.zip
cd cpulimit-master
make
mkdir -p ~/bin
cp build/cpulimit ~/bin/cpulimit
chmod +x ~/bin/cpulimit

# Add to PATH if not already present
if ! grep -q 'HOME/bin' ~/.bashrc; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
fi

export PATH="$HOME/bin:$PATH"

echo "Installation complete!"
cpulimit -V
