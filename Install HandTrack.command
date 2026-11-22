#!/bin/bash
# HandTrack installer for macOS 12+ (Apple Silicon and Intel).
# Double-click: Terminal opens and shows every step.
#   1. fetches uv, which installs a private Python 3.12 (nothing system-wide);
#   2. builds HandTrack.app on this Mac and puts it into Applications;
#   3. offers to install OBS — macOS only allows signed camera extensions,
#      so the virtual camera for calls is "OBS Virtual Camera".
# Running it again only does what is missing: uv, Python and libraries are
# reused, the app is rebuilt only when the source changed and copied only when
# the installed one differs.
cd "$(dirname "$0")" || exit 1
LOG="$PWD/install.log"
exec > >(tee "$LOG") 2>&1

RED=$'\033[1;31m'; GRN=$'\033[1;32m'; PUR=$'\033[35m'; RST=$'\033[0m'
step() { printf "\n${RED}>> %s${RST}\n" "$*"; }
have() { printf "   present: %s\n" "$*"; }
did() { printf "   + %s\n" "$*"; }
fail() {
    printf "\n${RED}INSTALL FAILED: %s${RST}\nLog: %s\n" "$*" "$LOG"
    read -r -n 1 -p "Press any key" _; echo; exit 1
}
ask() { local a; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy] ]]; }

APP="/Applications/HandTrack.app"
printf "${PUR}==================================================${RST}\n"
printf "   H A N D T R A C K   —   installer\n"
printf "   macOS %s, %s\n" "$(sw_vers -productVersion)" "$(uname -m)"
printf "${PUR}==================================================${RST}\n"
[ -f src/handtrack/__init__.py ] || fail "the src folder is missing next to this file"

# ---------------------------------------------------------------- 1. Python via uv
case "$(uname -m)" in
    arm64) UVARCH=aarch64-apple-darwin ;;
    *)     UVARCH=x86_64-apple-darwin ;;
esac
step "Python 3.12 and libraries"
UVDIR="$PWD/build/uv"
if [ -x "$UVDIR/uv" ]; then have uv; else
    mkdir -p "$UVDIR"
    curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/uv-$UVARCH.tar.gz" \
        | tar -xz -C "$UVDIR" --strip-components=1 || fail "could not download uv"
    did uv
fi
export UV_PYTHON_INSTALL_DIR="$PWD/build/python"
VENV="$PWD/build/venv"
PY="$VENV/bin/python"
if "$PY" -c "import sys; sys.exit(0 if sys.version_info[:2] == (3, 12) else 1)" 2>/dev/null; then
    have "Python 3.12"
else
    echo "   Installing Python 3.12 (first time ~1 minute)"
    "$UVDIR/uv" venv --clear --python 3.12 "$VENV" || fail "uv venv"
    did "Python 3.12"
fi
# Offline first: succeeds without the network when every library is already
# installed (or cached); only otherwise download what is missing.
# Older installs carry the GUI OpenCV builds, matplotlib and sounddevice. All
# OpenCV builds share one cv2 folder, so remove them together with the
# headless one; it is reinstalled cleanly just below.
EXTRAS="$("$UVDIR/uv" pip list --python "$PY" --format freeze 2>/dev/null \
    | grep -ioE '^(opencv-python|opencv-contrib-python|matplotlib|sounddevice)==' | tr -d '=' | tr '\n' ' ')"
if [ -n "$EXTRAS" ]; then
    "$UVDIR/uv" pip uninstall --python "$PY" $EXTRAS opencv-python-headless >/dev/null 2>&1
    did "removed unneeded packages: $EXTRAS"
fi
# overrides.txt drops mediapipe's unneeded extras (GUI OpenCV, matplotlib, audio).
if "$UVDIR/uv" pip install --offline --quiet --python "$PY" -r packaging/requirements-dev.txt pyvirtualcam \
        --override packaging/overrides.txt >/dev/null 2>&1; then
    have "libraries"
else
    echo "   Downloading libraries (first time ~3-6 minutes)"
    "$UVDIR/uv" pip install --python "$PY" -r packaging/requirements-dev.txt pyvirtualcam \
        --override packaging/overrides.txt || fail "pip install"
    did "libraries"
fi

# ---------------------------------------------------------------- 2. build + install
step "HandTrack.app"
# Fingerprint of everything the build uses; the app is rebuilt only when it changes.
BUILD_ID="$( { find src packaging -type f ! -path '*/__pycache__/*' -print0 | sort -z | xargs -0 shasum
               "$PY" -V; } 2>/dev/null | shasum | cut -c1-16 )"
if [ -d build/dist/HandTrack.app ] && [ "$(cat build/.build-id 2>/dev/null)" = "$BUILD_ID" ]; then
    have "the build is up to date"
else
    echo "   Building HandTrack.app on this Mac"
    rm -f build/.build-id
    PYTHON="$PY" bash packaging/macos/build.sh || fail "the build failed"
    echo "$BUILD_ID" > build/.build-id
    did "HandTrack.app built"
fi

if [ -d "$APP" ] && diff -rq -x "Uninstall HandTrack.command" build/dist/HandTrack.app "$APP" >/dev/null 2>&1; then
    have "$APP"
else
    osascript -e 'quit app "HandTrack"' 2>/dev/null; sleep 1
    if [ -w /Applications ]; then
        rm -rf "$APP" && ditto build/dist/HandTrack.app "$APP" || fail "copy"
    else
        echo "Your Mac password is needed"
        sudo rm -rf "$APP" && sudo ditto build/dist/HandTrack.app "$APP" && sudo chown -R "$(id -un)" "$APP" || fail "copy"
    fi
    xattr -dr com.apple.quarantine "$APP" 2>/dev/null
    did "$APP"
fi
cp -f "Uninstall HandTrack.command" "$APP/Contents/Resources/" 2>/dev/null

# ---------------------------------------------------------------- 3. camera permission
# macOS asks once per app. Ask now, on behalf of HandTrack.app (not Terminal),
# so the app never waits for an unanswered prompt later.
step "Camera access"
PERM="$HOME/Library/Application Support/HandTrack/camera-permission.txt"
mkdir -p "$(dirname "$PERM")" && rm -f "$PERM"
echo "   If macOS asks whether HandTrack may use the camera, click \"Allow\"."
open -n -W "$APP" --args --request-camera   # -n: a new process, even if HandTrack is open
case "$(cat "$PERM" 2>/dev/null)" in
    authorized) did "camera allowed" ;;
    denied|restricted)
        printf "${RED}   Camera access is off for HandTrack.${RST}\n"
        echo "   Turn it on: System Settings > Privacy & Security > Camera > HandTrack." ;;
    *) echo "   (could not check the camera permission; HandTrack asks again on Start)" ;;
esac

# ---------------------------------------------------------------- 4. virtual camera (OBS)
if [ ! -d /Applications/OBS.app ]; then
    step "Virtual camera for calls"
    echo "On macOS the camera for calls comes from the free OBS Studio."
    if ask "Install OBS now?"; then
        if command -v brew >/dev/null 2>&1; then
            brew install --cask obs || open "https://obsproject.com/download"
        else
            open "https://obsproject.com/download"
            echo "Download the macOS version and drag OBS into Applications."
        fi
    fi
fi
if [ -d /Applications/OBS.app ]; then
    cat <<'EOF'

Turn the OBS camera on once:
  1. Open OBS and click "Start Virtual Camera".
  2. macOS asks to allow the system extension: System Settings > Privacy & Security
     > "Allow". Then quit OBS; it is not needed any more.
  3. In HandTrack turn on "Stream to virtual camera", and in your call
     choose the camera "OBS Virtual Camera".
EOF
fi

# ---------------------------------------------------------------- 5. start
step "Starting HandTrack"
open "$APP"
cat <<'EOF'

For your own key-press gestures: System Settings > Privacy & Security >
Accessibility > turn on HandTrack.
EOF
printf "\n${GRN}DONE. HandTrack is in Applications and Launchpad.${RST}\n"
echo "Uninstall: \"Uninstall HandTrack.command\" in this folder."
read -r -n 1 -p "Press any key" _; echo
