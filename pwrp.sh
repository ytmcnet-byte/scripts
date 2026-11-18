#!/usr/bin/env bash
set -euo pipefail

BINARY="pwrp"
INSTALL_DIR="${HOME}/.local/bin"
DOWNLOAD_BASE="https://portwarp.com/download"

# Detect OS
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  linux|darwin) ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  armv7l|armhf) ARCH="armv7" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

SUFFIX="${OS}-${ARCH}"

# Check dependencies
for cmd in curl tar grep awk; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd"
    exit 1
  }
done

# Get latest version
echo "Fetching latest version..."
VERSIONS_JSON="$(curl -fsSL \
  "https://client-api.portwarp.com/api/versions")"

if command -v python3 >/dev/null 2>&1; then
  VERSION="$(printf '%s' "$VERSIONS_JSON" |
    python3 -c \
    'import json,sys; print(json.load(sys.stdin).get("cli",{}).get("version",""))')"
elif command -v php >/dev/null 2>&1; then
  VERSION="$(printf '%s' "$VERSIONS_JSON" |
    php -r '$j=json_decode(file_get_contents("php://stdin"),true); echo $j["cli"]["version"] ?? "";')"
else
  VERSION="$(printf '%s' "$VERSIONS_JSON" |
    sed -nE 's/.*"cli"[[:space:]]*:[[:space:]]*\{[^}]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
fi

if [ -z "$VERSION" ]; then
  echo "Failed to determine latest version."
  exit 1
fi

ARCHIVE="pwrp-${VERSION}-${SUFFIX}.tar.gz"
URL="${DOWNLOAD_BASE}/${ARCHIVE}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading pwrp v${VERSION} for ${SUFFIX}..."
curl -fsSL "$URL" -o "${TMP_DIR}/${ARCHIVE}"

# Verify checksum
echo "Verifying checksum..."
EXPECTED="$(curl -fsSL "${DOWNLOAD_BASE}/checksums.txt" |
  awk -v file="$ARCHIVE" '$2 == file || $2 == "*"file {print $1; exit}')"

if [ -n "$EXPECTED" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL="$(sha256sum "${TMP_DIR}/${ARCHIVE}" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    ACTUAL="$(shasum -a 256 "${TMP_DIR}/${ARCHIVE}" | awk '{print $1}')"
  else
    echo "No SHA-256 utility found; cannot verify checksum."
    exit 1
  fi

  if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "Checksum mismatch!"
    exit 1
  fi
  echo "Checksum OK."
else
  echo "Warning: checksum not found for ${ARCHIVE}."
fi

# Extract and install without root
tar -xzf "${TMP_DIR}/${ARCHIVE}" -C "$TMP_DIR"

if [ ! -f "${TMP_DIR}/${BINARY}" ]; then
  echo "Error: ${BINARY} not found in archive."
  exit 1
fi

mkdir -p "$INSTALL_DIR"
chmod +x "${TMP_DIR}/${BINARY}"
mv "${TMP_DIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"

# Configure PATH for future sessions
for RC in "$HOME/.bashrc" "$HOME/.profile"; do
  if [ -f "$RC" ] && ! grep -Fq '.local/bin' "$RC"; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"
  fi
done

export PATH="$INSTALL_DIR:$PATH"

echo
echo "pwrp v${VERSION} installed to ${INSTALL_DIR}/${BINARY}"
echo "No sudo required."
echo
echo "Run these commands:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo "  pwrp login"
echo "  pwrp tunnels"
echo "  pwrp connect"
