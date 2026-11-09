#!/usr/bin/env bash

# This script downloads the Security Onion ISO and verifies its integrity and authenticity.
# It checks the SHA256 checksum and GPG signature against known values.
# Example usage:
#   MINGW64 ~
#   $ bash /c/Users/<my_user>/Documents/so-threat-fusion/scripts/download-so.sh


set -euo pipefail

ISO="securityonion-2.4.211-20260407.iso"
SIG="${ISO}.sig"
ISO_URL="https://download.securityonion.net/file/securityonion/${ISO}"
SIG_URL="https://github.com/Security-Onion-Solutions/securityonion/raw/2.4/main/sigs/${SIG}"
KEYS_URL="https://raw.githubusercontent.com/Security-Onion-Solutions/securityonion/2.4/main/KEYS"
EXPECTED_FINGERPRINT="C804 A93D 36BE 0C73 3EA1  9644 7C10 60B7 FE50 7013"

# The expected SHA256 checksum for the ISO file. Taken from the official Security Onion release page in github.
SHA256_EXPECTED="185D8CF49CD3BFDD8876B8DDE48343DA90804B0C0EC3EADF0AD90D29C55E72B7"

fetch_url() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    if [[ "$output" == "-" ]]; then
      curl -fsSL "$url"
    else
      curl -fL "$url" -o "$output"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [[ "$output" == "-" ]]; then
      wget -q -O - "$url"
    else
      wget -q --show-progress "$url" -O "$output"
    fi
  else
    echo "ERROR: need curl or wget installed." >&2
    exit 1
  fi
}

echo "==> Importing Security Onion signing key..."
fetch_url "${KEYS_URL}" - | gpg --import -

echo "==> Downloading signature file..."
fetch_url "${SIG_URL}" "${SIG}"

echo "==> Downloading ISO (this will take a while)..."
fetch_url "${ISO_URL}" "${ISO}"

echo ""
echo "==> Verifying checksums..."

SHA256_ACTUAL=$(sha256sum "${ISO}" | awk '{print toupper($1)}')

fail=0

if [[ "${SHA256_ACTUAL}" == "${SHA256_EXPECTED}" ]]; then
  echo "  [OK] SHA256: ${SHA256_ACTUAL}"
else
  echo "  [FAIL] SHA256: got ${SHA256_ACTUAL}, expected ${SHA256_EXPECTED}"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo ""
  echo "ERROR: Checksum verification failed. Do not use this ISO."
  exit 1
fi

echo ""
echo "==> Verifying GPG signature..."
GPG_OUTPUT=$(gpg --verify "${SIG}" "${ISO}" 2>&1)
echo "${GPG_OUTPUT}"

if echo "${GPG_OUTPUT}" | grep -q "Good signature"; then
  echo ""
  echo "  [OK] GPG signature is valid."
else
  echo ""
  echo "ERROR: GPG signature verification failed."
  exit 1
fi

# Extract the fingerprint from gpg output and normalize whitespace for comparison
FINGERPRINT_ACTUAL=$(echo "${GPG_OUTPUT}" | grep "Primary key fingerprint" | sed 's/.*fingerprint: //')
if [[ "${FINGERPRINT_ACTUAL}" == "${EXPECTED_FINGERPRINT}" ]]; then
  echo "  [OK] Key fingerprint matches: ${FINGERPRINT_ACTUAL}"
else
  echo "  [WARN] Fingerprint mismatch:"
  echo "         Got:      ${FINGERPRINT_ACTUAL}"
  echo "         Expected: ${EXPECTED_FINGERPRINT}"
  echo "  Verify manually before using the ISO."
fi

echo ""
echo "All checks passed. ISO is ready: ${ISO}"
echo "Next step: https://securityonion.net/docs/installation"
