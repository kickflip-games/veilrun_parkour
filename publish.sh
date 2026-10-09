#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
ITCH_TARGET="${ITCH_TARGET:-avivajpeyi/nightreach:html5}"
case "${1:-publish}" in
    --build-only) exec ./build_web.sh ;;
    --help|-h) echo "Usage: ./publish.sh [--build-only|--check] (default target: $ITCH_TARGET)"; exit 0 ;;
    --check|publish) ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
esac
publisher="${BUTLER:-butler}"
if ! command -v "$publisher" >/dev/null 2>&1; then
    publisher="$HOME/.local/bin/butler"
fi
[[ -x "$(command -v "$publisher" || true)" ]] || { echo "Set BUTLER to your itch.io Butler executable." >&2; exit 1; }
if [[ "${1:-}" == --check ]]; then
    "$publisher" --version
    echo "Target: $ITCH_TARGET"
    exit 0
fi
./build_web.sh
"$publisher" push build/web "$ITCH_TARGET"
