#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Generating Shine app icons..."
swift "$SCRIPT_DIR/generate-icons.swift" "$PROJECT_ROOT"
echo "Icons saved to Shine/Resources/Assets.xcassets/AppIcon.appiconset/"
