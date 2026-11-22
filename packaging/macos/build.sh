#!/bin/bash
# Builds build/dist/HandTrack.app on this Mac. Used by "Install HandTrack.command" and CI.
# PYTHON must point to a Python 3.10-3.12 with the requirements + pyinstaller + pyvirtualcam.
set -euo pipefail
cd "$(dirname "$0")/../.."
PY="${PYTHON:-python3}"
export PYTHONPATH="$PWD/src"
export HANDTRACK_VERSION="$("$PY" -c 'import handtrack; print(handtrack.__version__)')"
"$PY" packaging/fetch_deps.py

# App icon (.icns) from the 1024 px PNG with the system tools.
ICONSET=build/HandTrack.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s src/handtrack/assets/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) src/handtrack/assets/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/HandTrack.icns

"$PY" -m PyInstaller --noconfirm --clean --log-level WARN --distpath build/dist --workpath build/pyinstaller \
    packaging/macos/handtrack.spec
QT_QPA_PLATFORM=offscreen build/dist/HandTrack.app/Contents/MacOS/HandTrack --self-test
echo "Built: build/dist/HandTrack.app"
