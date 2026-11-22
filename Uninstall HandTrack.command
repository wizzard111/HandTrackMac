#!/bin/bash
# HandTrack uninstaller for macOS: removes HandTrack.app and its camera /
# accessibility permissions; asks about the settings. OBS is left alone.
APP="/Applications/HandTrack.app"
BUNDLE_ID="io.github.handtrack"
SETTINGS="$HOME/Library/Application Support/HandTrack"
RED=$'\033[1;31m'; GRN=$'\033[1;32m'; PUR=$'\033[35m'; RST=$'\033[0m'
cd "$(dirname "$0")" || exit 1

printf "${PUR}==================================================${RST}\n"
printf "   H A N D T R A C K   —   uninstall\n"
printf "${PUR}==================================================${RST}\n"
read -r -p "Also delete settings and calibration? [y/N] " a

printf "${RED}>> Removing HandTrack.app${RST}\n"
osascript -e 'quit app "HandTrack"' 2>/dev/null
sleep 1
if [ -d "$APP" ]; then
    rm -rf "$APP" 2>/dev/null || sudo rm -rf "$APP"
fi
tccutil reset Camera "$BUNDLE_ID" >/dev/null 2>&1
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1
# Local build files of the installer (Python, libraries) next to this script.
[ -d build ] && [ -f src/handtrack/__init__.py ] && rm -rf build

if [[ "$a" =~ ^[Yy] ]]; then
    rm -rf "$SETTINGS" && echo "Settings deleted."
elif [ -d "$SETTINGS" ]; then
    echo "Settings kept: $SETTINGS"
fi
printf "\n${GRN}HandTrack has been removed. OBS, if installed, is removed separately (drag it to the Bin).${RST}\n"
read -r -n 1 -p "Press any key" _; echo
