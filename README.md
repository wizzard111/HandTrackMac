<div align="center">

<img src="src/handtrack/assets/icon.png" width="96" alt="HandTrack">

# HANDTRACK — macOS

**Жесты, взгляд, скрытие лица и рисование в воздухе — прямо в ваших звонках.**
Zoom, Telegram, Discord, Google Meet через OBS Virtual Camera.

*In collaboration with [Claude](https://claude.ai).*

[⬇ Скачать](../../releases/latest) · [Пошаговая установка](HOW-TO-INSTALL.txt) · [Windows](https://github.com/OWNER/HandTrackWindows) · [Linux](https://github.com/OWNER/HandTrackLinux) · [English](#english)

<img src="docs/screenshots/live.png" width="880" alt="HandTrack">

</div>

## Установка

1. [Releases](../../releases/latest) → **handtrack-macos.zip** → двойной щелчок.
2. Дважды щёлкните **Install HandTrack.command**. macOS предупредит, что не может проверить файл:
   «Системные настройки → Конфиденциальность и безопасность → Всё равно открыть» (macOS 15+)
   или «правой кнопкой → Открыть» (macOS 12–14). Права на запуск уже выставлены.
3. Установщик соберёт HandTrack.app на вашем Mac (3–6 минут), положит в «Программы»
   и предложит поставить OBS — его виртуальная камера нужна для звонков.

Подробно: [HOW-TO-INSTALL.txt](HOW-TO-INSTALL.txt). Удаление: **Uninstall HandTrack.command**.

**Почему OBS:** Apple разрешает виртуальные камеры только приложениям с платной подписью
разработчика (Camera Extension). Поэтому HandTrack отправляет кадры в бесплатную
OBS Virtual Camera; сам OBS при этом держать открытым не нужно.

**Почему сборка на вашем Mac:** собранное локально приложение macOS не блокирует как
«скачанное из интернета», и разрешения на камеру выдаются нормально.

## Устройство репозитория

```
Install HandTrack.command     установщик
Uninstall HandTrack.command   деинсталлятор
HOW-TO-INSTALL.txt            пошаговая инструкция
src/handtrack/                программа (тот же код, что и в Windows/Linux)
packaging/macos/              сборка HandTrack.app (PyInstaller, иконка .icns)
tests/                        тесты
```

## Лицензия

[MIT](LICENSE). Сторонние компоненты — [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).

---

<a id="english"></a>

## English

Download **handtrack-macos.zip** from [Releases](../../releases/latest), double-click
**Install HandTrack.command** (macOS 15+: System Settings → Privacy & Security → "Open Anyway";
macOS 12–14: right-click → Open). The installer builds HandTrack.app on your Mac, puts it in
Applications and offers to install OBS, whose virtual camera carries the picture into your calls.
Uninstall with **Uninstall HandTrack.command**. Step by step: [HOW-TO-INSTALL.txt](HOW-TO-INSTALL.txt).
