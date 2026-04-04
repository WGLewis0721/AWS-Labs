#!/bin/bash
# Convenience wrapper for the canonical A2 validation script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/netcheck.sh" "$@"
