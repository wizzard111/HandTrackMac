# PyInstaller spec — macOS app bundle. Run via packaging/macos/build.sh.
import os

ROOT = os.path.abspath(os.path.join(SPECPATH, "..", ".."))
DRIVER = False
EXTRA_DATAS = []
EXTRA_EXCLUDES = []
# pyautogui is imported lazily; pyvirtualcam drives the OBS Virtual Camera.
HIDDEN_IMPORTS = ["pyautogui", "pyvirtualcam", "pyvirtualcam._native_macos_obs"]
exec(open(os.path.join(ROOT, "packaging", "common.spec.py"), encoding="utf-8").read())

VERSION = os.environ.get("HANDTRACK_VERSION", "0")
ICNS = os.path.join(ROOT, "build", "HandTrack.icns")

exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name="HandTrack", console=False,
          argv_emulation=False, strip=False, upx=False)
coll = COLLECT(exe, a.binaries, a.datas, name="HandTrack", strip=False, upx=False)
app = BUNDLE(
    coll,
    name="HandTrack.app",
    icon=ICNS if os.path.exists(ICNS) else None,
    bundle_identifier="io.github.handtrack",
    version=VERSION,
    info_plist={
        "CFBundleDisplayName": "HandTrack",
        "CFBundleShortVersionString": VERSION,
        "LSMinimumSystemVersion": "12.0",
        "NSHighResolutionCapable": True,
        "LSApplicationCategoryType": "public.app-category.video",
        "NSCameraUsageDescription": "HandTrack reads the webcam to recognise gestures and hide your face.",
        "NSAppleEventsUsageDescription": "HandTrack presses keys for your custom gestures.",
    },
)
