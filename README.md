<div align="center">

<img src="src/handtrack/assets/icon.png" width="96" alt="HandTrack">

# HANDTRACK — macOS

**Gestures, gaze, face hiding and drawing in the air, right inside your calls.**
Zoom, Telegram, Discord and Google Meet through OBS Virtual Camera.

*In collaboration with [Claude](https://claude.ai).*

[⬇ Download](../../releases/latest) · [Step-by-step install](HOW-TO-INSTALL.txt) · [Windows](https://github.com/OWNER/HandTrackWindows) · [Linux](https://github.com/OWNER/HandTrackLinux)

<img src="docs/screenshots/live.png" width="880" alt="HandTrack">

</div>

## Install

1. [Releases](../../releases/latest) → **handtrack-macos.zip** → double-click it.
2. Double-click **Install HandTrack.command**. macOS warns that it cannot verify the file:
   "System Settings → Privacy & Security → Open Anyway" (macOS 15+)
   or "right-click → Open" (macOS 12–14). The files are already executable.
3. The installer builds HandTrack.app on your Mac (3–6 minutes), puts it in Applications
   and offers to install OBS, whose virtual camera carries the picture into your calls.

Step by step: [HOW-TO-INSTALL.txt](HOW-TO-INSTALL.txt). Uninstall: **Uninstall HandTrack.command**.
Running the installer again only rebuilds or copies what changed.

**Why OBS:** Apple only allows virtual cameras in apps with a paid developer signature
(Camera Extension). So HandTrack sends its frames to the free OBS Virtual Camera; OBS itself
does not have to stay open.

**Why build on your Mac:** macOS does not block a locally built app as "downloaded from the
internet", and camera permissions are granted normally.

## Repository layout

```
Install HandTrack.command     installer
Uninstall HandTrack.command   uninstaller
HOW-TO-INSTALL.txt            step-by-step guide
src/handtrack/                the program (same code as on Windows/Linux)
packaging/macos/              HandTrack.app build (PyInstaller, .icns icon)
tests/                        tests
```

## License

[MIT](LICENSE). Third-party components: [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
