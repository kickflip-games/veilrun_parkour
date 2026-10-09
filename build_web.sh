#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Build with the installed stable runtime and matching Web templates.
# Set GODOT_BIN to override the executable (its export templates must match).
if [[ -z "${GODOT_BIN:-}" ]]; then
    stable_runtime="$HOME/Library/Application Support/Godot/app_userdata/Godots/versions/Godot_v4_6-stable_macos_universal/Godot.app/Contents/MacOS/Godot"
    if [[ -x "$stable_runtime" ]]; then
        GODOT_BIN="$stable_runtime"
    elif command -v godot >/dev/null 2>&1; then
        GODOT_BIN="$(command -v godot)"
    elif command -v godot4 >/dev/null 2>&1; then
        GODOT_BIN="$(command -v godot4)"
    else
        echo "Set GODOT_BIN to a Godot executable with matching Web export templates." >&2
        exit 1
    fi
fi

mkdir -p build/web build/staging
touch build/.gdignore
find build/web -maxdepth 1 -type f -delete
# Only the runtime logger is staged from addons; editor tools stay in source.
# An isolated export checkout keeps the desktop editor's import cache intact.
rsync -a --delete --delete-excluded --exclude '.git/' --exclude '.claude/' --exclude '.agents/' --exclude '.codex/' --exclude '.env*' --exclude '.godot/' --exclude 'build/' --exclude 'archive/' \
    --include '/addons/' --include '/addons/logger/***' --exclude '/addons/***' \
    --exclude 'scenes/general/debug_menu/' --exclude 'tools/' --exclude '_*validation*' ./ build/staging/
python3 - "$GODOT_BIN" <<'PY'
from pathlib import Path
import re, subprocess, sys
p = Path('build/staging/project.godot')
s = p.read_text()
s = re.sub(r'^DebugMenu=.*\n', '', s, flags=re.M)
s = re.sub(r'^\w+=\"\*res://addons/(?!logger/)[^\"]*\"\n', '', s, flags=re.M)
s = re.sub(r'^enabled=PackedStringArray\(.*\)$', 'enabled=PackedStringArray()', s, flags=re.M)
s = s.replace('Log="*uid://b4w2rvoel3ush"', 'Log="*res://addons/logger/logger.gd"')
version = subprocess.check_output([sys.argv[1], '--version'], text=True).strip()
match = re.match(r'(\d+\.\d+)', version)
if match:
    s = re.sub(r'config/features=PackedStringArray\(.*\)', f'config/features=PackedStringArray("{match[1]}", "GL Compatibility")', s)
p.write_text(s)
# Keep the share build independent of ignored local export presets.
Path('build/staging/export_presets.cfg').write_text('''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter="addons/godot_ai/*,archive/*,build/*,tests/*,tools/*"
script_export_mode=2
[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
''')
print('Export runtime:', version)
PY
"$GODOT_BIN" --headless --path build/staging --editor --quit > build/import.log 2>&1
"$GODOT_BIN" --headless --path build/staging --export-release Web ../web/index.html > build/export.log 2>&1
# Godot can return success after a script/export error. Fail on diagnostics too.
python3 - <<'PYLOG'
from pathlib import Path
import re, sys
errors = [f"{path}: {line}" for path in (Path('build/import.log'), Path('build/export.log'))
          for line in path.read_text().splitlines() if re.search(r'ERROR:|SCRIPT ERROR:|Parse Error:', line)]
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit('Web build reported errors. Inspect build/import.log and build/export.log.')
PYLOG
if [[ ! -s build/web/index.html || ! -s build/web/index.wasm || ! -s build/web/index.pck ]]; then
    echo "Web export incomplete. Inspect build/import.log and build/export.log." >&2
    exit 1
fi
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
with ZipFile('build/nightreach-web.zip', 'w', ZIP_DEFLATED) as archive:
    for file in sorted(Path('build/web').iterdir()):
        if file.is_file(): archive.write(file, file.name)
print('Ready: build/nightreach-web.zip')
PY
