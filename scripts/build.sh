#!/bin/bash
# Backwards-compatible app-only entry point.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/build.sh" --app-only "$@"
