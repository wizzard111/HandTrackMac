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
have() { printf "   есть / present: %s\n" "$*"; }
did() { printf "   + %s\n" "$*"; }
fail() {
    printf "\n${RED}ОШИБКА УСТАНОВКИ / INSTALL FAILED: %s${RST}\nЖурнал / log: %s\n" "$*" "$LOG"
    read -r -n 1 -p "Нажмите любую клавишу / press any key" _; echo; exit 1
}
ask() { local a; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[YyДд] ]]; }

APP="/Applications/HandTrack.app"
printf "${PUR}==================================================${RST}\n"
printf "   H A N D T R A C K   —   установка / installer\n"
printf "   macOS %s, %s\n" "$(sw_vers -productVersion)" "$(uname -m)"
printf "${PUR}==================================================${RST}\n"
[ -f src/handtrack/__init__.py ] || fail "рядом нет папки src / the src folder is missing next to this file"

# ---------------------------------------------------------------- 1. Python via uv
case "$(uname -m)" in
    arm64) UVARCH=aarch64-apple-darwin ;;
    *)     UVARCH=x86_64-apple-darwin ;;
esac
step "Python 3.12 и библиотеки / Python 3.12 and libraries"
UVDIR="$PWD/build/uv"
if [ -x "$UVDIR/uv" ]; then have uv; else
    mkdir -p "$UVDIR"
    curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/uv-$UVARCH.tar.gz" \
        | tar -xz -C "$UVDIR" --strip-components=1 || fail "не удалось скачать uv / could not download uv"
    did uv
fi
export UV_PYTHON_INSTALL_DIR="$PWD/build/python"
VENV="$PWD/build/venv"
PY="$VENV/bin/python"
if "$PY" -c "import sys; sys.exit(0 if sys.version_info[:2] == (3, 12) else 1)" 2>/dev/null; then
    have "Python 3.12"
else
    echo "   Ставлю Python 3.12 (первый раз ~1 минута) / Installing Python 3.12"
    "$UVDIR/uv" venv --clear --python 3.12 "$VENV" || fail "uv venv"
    did "Python 3.12"
fi
# Offline first: succeeds without the network when every library is already
# installed (or cached); only otherwise download what is missing.
if "$UVDIR/uv" pip install --offline --quiet --python "$PY" -r packaging/requirements-dev.txt pyvirtualcam >/dev/null 2>&1; then
    have "библиотеки / libraries"
else
    echo "   Докачиваю библиотеки (первый раз ~3-6 минут) / Downloading libraries"
    "$UVDIR/uv" pip install --python "$PY" -r packaging/requirements-dev.txt pyvirtualcam || fail "pip install"
    did "библиотеки / libraries"
fi

# ---------------------------------------------------------------- 2. build + install
step "HandTrack.app"
# Fingerprint of everything the build uses; the app is rebuilt only when it changes.
BUILD_ID="$( { find src packaging -type f ! -path '*/__pycache__/*' -print0 | sort -z | xargs -0 shasum
               "$PY" -V; } 2>/dev/null | shasum | cut -c1-16 )"
if [ -d build/dist/HandTrack.app ] && [ "$(cat build/.build-id 2>/dev/null)" = "$BUILD_ID" ]; then
    have "сборка актуальна / the build is up to date"
else
    echo "   Собираю HandTrack.app на этом Mac / Building HandTrack.app"
    rm -f build/.build-id
    PYTHON="$PY" bash packaging/macos/build.sh || fail "сборка не удалась / the build failed"
    echo "$BUILD_ID" > build/.build-id
    did "HandTrack.app собран / built"
fi

if [ -d "$APP" ] && diff -rq -x "Uninstall HandTrack.command" build/dist/HandTrack.app "$APP" >/dev/null 2>&1; then
    have "$APP"
else
    osascript -e 'quit app "HandTrack"' 2>/dev/null; sleep 1
    if [ -w /Applications ]; then
        rm -rf "$APP" && ditto build/dist/HandTrack.app "$APP" || fail "copy"
    else
        echo "Нужен пароль Mac / your Mac password is needed"
        sudo rm -rf "$APP" && sudo ditto build/dist/HandTrack.app "$APP" && sudo chown -R "$(id -un)" "$APP" || fail "copy"
    fi
    xattr -dr com.apple.quarantine "$APP" 2>/dev/null
    did "$APP"
fi
cp -f "Uninstall HandTrack.command" "$APP/Contents/Resources/" 2>/dev/null

# ---------------------------------------------------------------- 3. virtual camera (OBS)
if [ ! -d /Applications/OBS.app ]; then
    step "Виртуальная камера для звонков / Virtual camera for calls"
    echo "На macOS камеру для Zoom / Telegram / Discord даёт бесплатный OBS Studio."
    echo "On macOS the camera for calls comes from the free OBS Studio."
    if ask "Установить OBS сейчас? / Install OBS now?"; then
        if command -v brew >/dev/null 2>&1; then
            brew install --cask obs || open "https://obsproject.com/download"
        else
            open "https://obsproject.com/download"
            echo "Скачайте «macOS» версию и перетащите OBS в «Программы»."
            echo "Download the macOS version and drag OBS into Applications."
        fi
    fi
fi
if [ -d /Applications/OBS.app ]; then
    cat <<'EOF'

Один раз включите камеру OBS / Turn the OBS camera on once:
  1. Откройте OBS → кнопка «Запустить виртуальную камеру» (Start Virtual Camera).
  2. macOS попросит разрешить расширение: Системные настройки → Конфиденциальность
     и безопасность → «Разрешить». Затем закройте OBS — он больше не нужен.
  3. В HandTrack включите «Транслировать в виртуальную камеру», а в звонке
     выберите камеру «OBS Virtual Camera».
EOF
fi

# ---------------------------------------------------------------- 4. start
step "Запускаю HandTrack / Starting HandTrack"
open "$APP"
cat <<'EOF'

macOS спросит доступ к камере — нажмите «Разрешить».
macOS asks for camera access — click "Allow".
Для своих жестов с клавишами: Системные настройки → Конфиденциальность и безопасность →
Универсальный доступ → включите HandTrack.
EOF
printf "\n${GRN}ГОТОВО. HandTrack — в «Программах» и в Launchpad.${RST}\n"
printf "${GRN}DONE. HandTrack is in Applications and Launchpad.${RST}\n"
echo "Удалить / uninstall: «Uninstall HandTrack.command» в этой папке / in this folder."
read -r -n 1 -p "Нажмите любую клавишу / press any key" _; echo
