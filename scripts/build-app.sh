#!/usr/bin/env bash
# Dev build: assemble QuickRun.app and ad-hoc sign it for local testing.
# Ad-hoc signing has no stable identity, so Accessibility (TCC) may need
# re-granting after each rebuild. For a durable, distributable build use
# release.sh (Developer ID + notarization).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

assemble_app debug

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP_PATH"

echo "Built $APP_PATH"
