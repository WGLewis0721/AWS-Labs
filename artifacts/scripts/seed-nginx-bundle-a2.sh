#!/bin/bash
set -euo pipefail

OUT_DIR="${1:-/tmp/tgw-nginx-bundle}"
RPM_DIR="$OUT_DIR/rpms"
TARBALL="$OUT_DIR/nginx-al2023-bundle.tgz"
PACKAGE_LIST="$OUT_DIR/packages.txt"
CHECKSUMS="$OUT_DIR/SHA256SUMS"

sudo dnf install -y dnf-plugins-core >/dev/null

rm -rf "$OUT_DIR"
mkdir -p "$RPM_DIR"

sudo dnf download --resolve --destdir "$RPM_DIR" nginx psmisc >/dev/null

(
  cd "$RPM_DIR"
  ls -1 *.rpm | sort > "$PACKAGE_LIST"
  sha256sum *.rpm | sort > "$CHECKSUMS"
)

tar -czf "$TARBALL" -C "$RPM_DIR" .

echo "Bundle created:"
echo "  tarball: $TARBALL"
echo "  package list: $PACKAGE_LIST"
echo "  checksums: $CHECKSUMS"
