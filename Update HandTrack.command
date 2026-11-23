#!/bin/bash
# HandTrack updater for macOS: double-click it. Installs the newest version from GitHub; your settings are kept.
#  1. asks GitHub for the latest release and compares it with the installed version;
#  2. backs up the settings, calibration and gestures (~/Library/Application Support/HandTrack);
#  3. downloads the release, checks its SHA-256 and runs its own installer, which builds HandTrack.app
#     on this Mac and replaces the one in Applications (the old app is deleted completely).
#     The source and the build environment (Python, libraries) are kept in ~/Library/Caches/HandTrack-updater,
#     so the next update only downloads and builds what changed;
#  4. makes sure every setting is still there (restores from the backup otherwise) and deletes the download.
# The app is signed with a lasting local certificate (made once; the Mac password is asked once), so macOS
# keeps its Camera / Accessibility permissions across updates.
# After the first run, "Update HandTrack" in Applications (Launchpad) starts the updater.
# The installer starts HandTrack at the end (and asks for the camera, if macOS forgot the permission).
# Options: --check            only report whether an update exists (exit code 2 = update available)
#          --force            reinstall even when the installed version is the latest
#          --yes              no questions
#          --package FILE     install a release (handtrack-macos.zip) that is already downloaded
#          --no-launch        (ignored: the installer always starts HandTrack)
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")" || exit 1
PAUSE=""; [ $# -eq 0 ] && PAUSE=1   # double-clicked: keep the window open to read the result

# ---------------------------------------------------------------- what differs between the apps
APP_NAME="HandTrack"
REPO="wizzard111/HandTrackMac"
APP="${APPS_DIR:-/Applications}/HandTrack.app"
ASSET="handtrack-macos.zip"
SETTINGS_DIR="$HOME/Library/Application Support/HandTrack"
STATE_DIR="$HOME/Library/Application Support/HandTrack-updater"
CACHE_DIR="$HOME/Library/Caches/HandTrack-updater"
BACKUP_ROOT="$STATE_DIR/backups"
KEEP_BACKUPS=3
SKIP_IN_BACKUP=("*.log" "*.lock" "logs" "camera-permission.txt")   # logs are not settings
AFTER_NOTE=""
PERMISSIONS_NOTE="macOS asks again for the camera, and for Accessibility when you use your own key-press
gestures: allow them (System Settings > Privacy & Security, switch HandTrack on)."

is_installed() { [ -d "$APP" ]; }
installed_version() { is_installed && defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null; }
is_running() { pgrep -f "$APP/Contents/MacOS/" >/dev/null 2>&1; }
start_app() { open "$APP"; }
install_package() {
    note_signature; setup_signing   # the installer signs its build with it
    prepare_source "$1" build || return 1
    [ -f "$SRC_DIR/Update $APP_NAME.command" ] && NEW_UPDATER="$SRC_DIR/Update $APP_NAME.command"
    [ -f "$SRC_DIR/Install HandTrack.command" ] || { echo "this is not a $APP_NAME release"; return 1; }
    # The installer asks only whether to install OBS when it is missing (answer: no; the updater adds
    # nothing new) and waits for a key at the end. It closes HandTrack only when the app really changes.
    printf 'n\n\n\n' | bash "$SRC_DIR/Install HandTrack.command"
}
prepare_source() {   # prepare_source ARCHIVE KEEP...: the source in $CACHE_DIR/src, old files replaced, KEEP folders kept
    local archive="$1" top p n k keep; shift
    rm -rf "$WORK/src" && mkdir -p "$WORK/src" || return 1
    case "$archive" in
        *.zip) unzip -q "$archive" -d "$WORK/src" ;;
        *)     tar -xzf "$archive" -C "$WORK/src" ;;
    esac || { echo "cannot unpack $archive"; return 1; }
    top="$(find "$WORK/src" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$top" ] || { echo "the archive is empty"; return 1; }
    SRC_DIR="$CACHE_DIR/src"; mkdir -p "$SRC_DIR" || return 1
    for p in "$SRC_DIR"/* "$SRC_DIR"/.[!.]*; do
        [ -e "$p" ] || continue
        n="$(basename "$p")"; keep=""
        for k in "$@"; do [ "$n" = "$k" ] && keep=1; done
        [ -n "$keep" ] || rm -rf "$p"
    done
    cp -R "$top/." "$SRC_DIR/"
}

# ---------------------------------------------------------------- macOS: lasting signature + launcher (same in both apps)
# macOS keeps an app's permissions (Input Monitoring, Accessibility, Camera) across updates only when
# every version is signed by the same certificate. A free local certificate is made once, kept in its
# own keychain (its password is stored next to it, readable only by this user) and trusted for code
# signing only; trusting it asks for the Mac password once. All of the user's apps share it.
SIGN_ID="reflex local code signing"
SIGN_DIR="$HOME/Library/Application Support/reflex-local-signing"
SIGN_KC="$SIGN_DIR/signing.keychain-db"
signing_ready() {
    [ -f "$SIGN_KC" ] || return 1
    security unlock-keychain -p "$(cat "$SIGN_DIR/keychain-password" 2>/dev/null)" "$SIGN_KC" >/dev/null 2>&1 &&
        security find-identity -v -p codesigning "$SIGN_KC" 2>/dev/null | grep -q "\"$SIGN_ID\""
}
setup_signing() {
    signing_ready && return 0
    step "Lasting signature (once)"
    info "So that macOS keeps $APP_NAME's permissions after every update."
    local tmp pw; tmp="$(mktemp -d)" || return 1
    mkdir -p "$SIGN_DIR" && chmod 700 "$SIGN_DIR" || return 1
    if [ ! -f "$SIGN_KC" ]; then
        pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
        (umask 077; printf '%s' "$pw" > "$SIGN_DIR/keychain-password")
        printf '[req]\ndistinguished_name=dn\nprompt=no\nx509_extensions=ext\n[dn]\nCN=%s\n[ext]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' \
            "$SIGN_ID" > "$tmp/cert.cnf"
        if ! { /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$tmp/cert.cnf" \
                   -keyout "$tmp/key.pem" -out "$tmp/cert.pem" >/dev/null 2>&1 &&
               /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$SIGN_ID" -out "$tmp/id.p12" \
                   -passout "pass:$pw" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1 &&
               security create-keychain -p "$pw" "$SIGN_KC" &&
               security set-keychain-settings "$SIGN_KC" &&          # never locks by itself
               security unlock-keychain -p "$pw" "$SIGN_KC" &&
               security import "$tmp/id.p12" -k "$SIGN_KC" -P "$pw" -T /usr/bin/codesign >/dev/null &&
               security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pw" "$SIGN_KC" >/dev/null; }; then
            info "(could not create the certificate; $APP_NAME keeps its own signature)"
            rm -rf "$tmp" "$SIGN_KC"; return 1
        fi
    fi
    security find-certificate -c "$SIGN_ID" -p "$SIGN_KC" > "$tmp/cert.pem" 2>/dev/null
    info "Your Mac password is needed once, to trust the certificate for code signing:"
    if ! sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$tmp/cert.pem"; then
        info "(not trusted; $APP_NAME keeps its own signature)"; rm -rf "$tmp"; return 1
    fi
    rm -rf "$tmp"
    signing_ready || return 1
    info "done"
}
sign_app() {   # sign_app APP: sign with the lasting certificate, when it is set up; never leaves the app unsigned
    signing_ready || return 0
    codesign -dv "$1" 2>&1 | grep -qx "Authority=$SIGN_ID" && return 0   # already signed with it
    if codesign --force --deep --timestamp=none --keychain "$SIGN_KC" --sign "$SIGN_ID" "$1" >/dev/null 2>&1 &&
       codesign --verify --deep "$1" >/dev/null 2>&1; then
        info "Signed: $(basename "$1")"
    else
        info "(could not sign $(basename "$1"); it keeps a local signature)"
        codesign --force --deep --sign - "$1" >/dev/null 2>&1
    fi
    return 0
}
install_launcher() {   # install_launcher UPDATER: a local copy of it + "Update <app>" in Applications that opens it
    local src="$1" copy="$STATE_DIR/Update $APP_NAME.command" dir app
    [ -f "$src" ] && mkdir -p "$STATE_DIR" || return 0
    if [ "$src" != "$copy" ]; then
        # New file (a running copy keeps reading the old one); cat leaves the download's quarantine flag behind.
        rm -f "$copy"; cat "$src" > "$copy" && chmod +x "$copy" || return 0
    fi
    dir="${APPS_DIR:-/Applications}"; [ -w "$dir" ] || { dir="$HOME/Applications"; mkdir -p "$dir"; }
    app="$dir/Update $APP_NAME.app"
    [ -d "$app" ] && return 0
    osacompile -o "$app" -e "do shell script \"open -a Terminal \" & quoted form of \"$copy\"" >/dev/null 2>&1 &&
        info "Added \"Update $APP_NAME\" to $dir (and Launchpad): it starts this updater."
    return 0
}
WAS_SIGNED=""
note_signature() {   # before installing: was the installed app signed with the lasting certificate already?
    WAS_SIGNED=""
    is_installed && codesign -dv "$APP" 2>&1 | grep -qx "Authority=$SIGN_ID" && WAS_SIGNED=1
    return 0
}
after_install() {
    install_launcher "${NEW_UPDATER:-$SELF}"
    if ! signing_ready; then AFTER_NOTE="$PERMISSIONS_NOTE"
    elif [ -z "$WAS_SIGNED" ]; then AFTER_NOTE="$PERMISSIONS_NOTE
Only this once: from now on $APP_NAME keeps its permissions after updates."
    fi
}

# ---------------------------------------------------------------- common part (same in every app)
CHECK=""; FORCE=""; YES=""; LAUNCH=1; PACKAGE=""; SETUP=""; SIGN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --force) FORCE=1 ;;
        --yes|-y) YES=1 ;;
        --no-launch) LAUNCH="" ;;
        --package) PACKAGE="${2:-}"; shift ;;
        --pause) PAUSE=1 ;;                     # started from a menu entry: keep the window open
        --setup) SETUP=1 ;;                     # (macOS, used by the installer) signing identity + launcher
        --sign) SIGN="${2:-}"; shift ;;          # (macOS, used by the installer) sign a freshly built app
        -h|--help) sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
    esac
    shift
done

BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; RST=$'\033[0m'
step() { printf "\n${BOLD}==> %s${RST}\n" "$*"; }
info() { printf "    %s\n" "$*"; }
pause() { [ -n "$PAUSE" ] && read -r -p "Press Enter to close this window." _; return 0; }
fail() {
    printf "\n${RED}Update failed: %s${RST}\n" "$*"
    [ -n "$BACKUP" ] && echo "Your settings are backed up in $BACKUP"
    pause; exit 1
}
ask() {   # yes by default; no answer possible (no terminal) = no
    [ -n "$YES" ] && return 0
    local a; read -r -p "$1 [Y/n] " a || return 1
    [[ -z "$a" || "$a" =~ ^[Yy] ]]
}
ver() { printf '%s' "$1" | grep -oE '[0-9]+(\.[0-9]+)*' | head -n 1; }
ver_ge() {   # ver_ge A B: A >= B (numeric, part by part)
    awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); k = n > m ? n : m
        for (i = 1; i <= k; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 } exit 0 }'
}
fetch() {   # fetch URL FILE  (FILE "-" = print it)
    if command -v curl >/dev/null 2>&1; then
        if [ "$2" = - ]; then curl -fsSL --retry 3 --retry-delay 2 --max-time 60 -A "$APP_NAME-updater" "$1"
        else curl -fL --retry 3 --retry-delay 2 --progress-bar -A "$APP_NAME-updater" -o "$2" "$1"; fi
    elif command -v wget >/dev/null 2>&1; then
        wget -q -U "$APP_NAME-updater" -O "$2" "$1"
    else
        fail "neither curl nor wget is installed"
    fi
}
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
setting_files() {   # relative paths of the files that count as settings (logs and locks left out)
    [ -d "$SETTINGS_DIR" ] || return 0
    local args=(-name "${SKIP_IN_BACKUP[0]}") p
    for p in "${SKIP_IN_BACKUP[@]:1}"; do args+=(-o -name "$p"); done
    (cd "$SETTINGS_DIR" && find . \( "${args[@]}" \) -prune -o -type f -print | sed 's|^\./||')
}
copy_files() {   # copy_files FROM TO < list of relative paths
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        mkdir -p "$2/$(dirname "$f")" && cp -p "$1/$f" "$2/$f" || return 1
    done
}
# shellcheck disable=SC2329  # run by the EXIT trap
cleanup() {
    type cleanup_app >/dev/null 2>&1 && cleanup_app
    [ -n "$WORK" ] && rm -rf "$WORK"
    [ -n "$LOCKED" ] && rm -rf "$STATE_DIR/update.lock"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Called by an installer: only set up the signing identity and the launcher / sign its build, then stop.
if [ -n "$SETUP$SIGN" ]; then
    type sign_app >/dev/null 2>&1 || { echo "--setup and --sign are for macOS"; exit 1; }
    if [ -n "$SETUP" ]; then setup_signing; install_launcher "$SELF"; fi
    if [ -n "$SIGN" ]; then sign_app "$SIGN"; fi
    exit 0
fi

echo "================================================"
echo "  $APP_NAME updater"
echo "================================================"
mkdir -p "$STATE_DIR" || fail "cannot create $STATE_DIR"

# One updater at a time (a lock left by a crashed run is taken over).
if ! mkdir "$STATE_DIR/update.lock" 2>/dev/null; then
    pid="$(cat "$STATE_DIR/update.lock/pid" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then fail "another update of $APP_NAME is already running"; fi
    rm -rf "$STATE_DIR/update.lock"; mkdir "$STATE_DIR/update.lock" || fail "cannot lock $STATE_DIR"
fi
LOCKED=1; echo $$ > "$STATE_DIR/update.lock/pid"

# ---------------------------------------------------------------- 1. versions
INSTALLED=""
if is_installed; then
    INSTALLED="$(ver "$(installed_version)")"
    # The version this updater installed last; the newer one counts (an app may report an old number).
    saved="$(ver "$(cat "$STATE_DIR/installed-version" 2>/dev/null)")"
    if [ -n "$saved" ] && { [ -z "$INSTALLED" ] || ! ver_ge "$INSTALLED" "$saved"; }; then INSTALLED="$saved"; fi
    info "Installed: ${INSTALLED:+v}${INSTALLED:-unknown version}"
else
    info "Installed: not installed"
fi

LATEST=""; URL=""; DIGEST=""
if [ -n "$PACKAGE" ]; then
    [ -f "$PACKAGE" ] || fail "file not found: $PACKAGE"
    PACKAGE="$(cd "$(dirname "$PACKAGE")" && pwd)/$(basename "$PACKAGE")"
    info "Package:   $PACKAGE"
    [ -n "$CHECK" ] && fail "--check needs the internet (it cannot be used with --package)"
else
    json="$(fetch "https://api.github.com/repos/$REPO/releases/latest" - 2>/dev/null)" || json=""
    TAG="$(printf '%s' "$json" | tr -d '\n' | grep -oE '"tag_name": *"[^"]*"' | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')"
    if [ -z "$TAG" ]; then
        # The GitHub API answers 60 questions an hour per address; the release page names the latest version too.
        json=""
        TAG="$(curl -fsSIL --max-time 30 -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null |
               sed -n 's|.*/releases/tag/||p')"
        [ -n "$TAG" ] || fail "could not ask GitHub for the latest version. Check the internet connection."
    fi
    LATEST="$(ver "$TAG")"
    if [ -n "$ASSET" ] && [ -z "$json" ]; then
        URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"; DIGEST="-"
        info "Latest:    v$LATEST"
    elif [ -n "$ASSET" ]; then
        # The release's assets: name ... size ... digest ... browser_download_url (one field per line here).
        # shellcheck disable=SC2020  # tr: each of , { } starts a new line
        read -r URL DIGEST SIZE <<< "$(printf '%s' "$json" | tr ',{}' '\n\n\n' | awk -v want="$ASSET" '
            /"name": *"/ { n = $0; sub(/.*"name": *"/, "", n); sub(/".*/, "", n); cur = n; d = "-"; s = 0 }
            cur != want { next }
            /"size": *[0-9]/ { s = $0; gsub(/[^0-9]/, "", s) }
            /"digest": *"sha256:/ { d = $0; sub(/.*sha256:/, "", d); sub(/".*/, "", d) }
            /"browser_download_url": *"/ { u = $0; sub(/.*"browser_download_url": *"/, "", u); sub(/".*/, "", u)
                                          print u, d, s; exit }')"
        DIGEST="${DIGEST:--}"; SIZE="${SIZE:-0}"
        [ -n "$URL" ] || fail "release $TAG has no $ASSET"
        info "Latest:    v$LATEST ($(awk -v s="$SIZE" 'BEGIN { printf "%.1f", s / 1048576 }') MB)"
    else
        # No ready-made program for this computer: the release's source code is built here.
        URL="https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"; DIGEST="-"
        info "Latest:    v$LATEST (source code, built on this computer)"
    fi
    UP_TO_DATE=""
    [ -n "$INSTALLED" ] && ver_ge "$INSTALLED" "$LATEST" && UP_TO_DATE=1
    if [ -n "$CHECK" ]; then
        if [ -n "$UP_TO_DATE" ]; then echo "$APP_NAME is up to date."; exit 0; fi
        echo "An update is available: v$LATEST"; exit 2
    fi
    if [ -n "$UP_TO_DATE" ] && [ -z "$FORCE" ]; then
        printf "\n${GRN}%s is up to date.${RST} (--force reinstalls it.)\n" "$APP_NAME"; pause; exit 0
    fi
fi
ask "Install ${LATEST:+v}${LATEST:-the package} now? Your settings are kept." || { echo "Nothing changed."; pause; exit 0; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/$(printf '%s' "$APP_NAME" | tr -cd 'A-Za-z0-9')-update.XXXXXX")" || fail "cannot create a temporary folder"

# ---------------------------------------------------------------- 2. download (before closing the app)
if [ -z "$PACKAGE" ]; then
    step "Downloading ${ASSET:-the source code}"
    PACKAGE="$WORK/${ASSET:-source.tar.gz}"
    fetch "$URL" "$PACKAGE" || fail "download failed. Check the internet connection and try again."
    if [ "$DIGEST" != - ]; then
        [ "$(sha256 "$PACKAGE")" = "$DIGEST" ] || fail "the download is damaged (SHA-256 does not match). Try again."
        info "SHA-256 checked"
    fi
fi

# ---------------------------------------------------------------- 3. settings backup
BACKUP=""
FILES="$(setting_files)"
COUNT=0; [ -n "$FILES" ] && COUNT="$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')"
if [ "$COUNT" -gt 0 ]; then
    step "Backing up the settings"
    BACKUP="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)${INSTALLED:+-v$INSTALLED}"
    printf '%s\n' "$FILES" | copy_files "$SETTINGS_DIR" "$BACKUP" || fail "could not back up the settings to $BACKUP"
    info "$COUNT files -> $BACKUP"
    # Only the newest backups are kept.
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((KEEP_BACKUPS + 1)) |
        while IFS= read -r old; do rm -rf "${old:?}"; done
else
    info "No settings yet: nothing to back up."
fi

# ---------------------------------------------------------------- 4. install
WAS_RUNNING=""; is_running && WAS_RUNNING=1
step "Installing $APP_NAME${LATEST:+ v$LATEST}"
[ -n "$WAS_RUNNING" ] && info "$APP_NAME is running: it is closed for the update and started again afterwards."
install_package "$PACKAGE" || fail "the installation did not succeed (see the messages above)"
NOW="$(ver "$(installed_version)")"; NOW="${NOW:-$LATEST}"
if [ -n "$NOW" ]; then echo "$NOW" > "$STATE_DIR/installed-version"; else rm -f "$STATE_DIR/installed-version"; fi
type after_install >/dev/null 2>&1 && after_install   # (macOS) the launcher gets the new updater

# ---------------------------------------------------------------- 5. settings check
if [ "$COUNT" -gt 0 ]; then
    step "Checking the settings"
    MISSING="$(printf '%s\n' "$FILES" | while IFS= read -r f; do [ -e "$SETTINGS_DIR/$f" ] || printf '%s\n' "$f"; done)"
    if [ -n "$MISSING" ]; then
        printf '%s\n' "$MISSING" | copy_files "$BACKUP" "$SETTINGS_DIR" || fail "could not restore the settings from $BACKUP"
        info "Restored from the backup: $(printf '%s' "$MISSING" | tr '\n' ' ')"
    else
        info "All $COUNT files are in place."
    fi
fi

if [ -n "$WAS_RUNNING" ] && [ -n "$LAUNCH" ] && ! is_running; then step "Starting $APP_NAME"; start_app; fi
printf "\n${GRN}%s is updated%s. Settings kept.${RST}\n" "$APP_NAME" "${NOW:+ to v$NOW}"
[ -n "$AFTER_NOTE" ] && printf '%s\n' "$AFTER_NOTE"
pause
exit 0
