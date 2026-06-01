# XExternalHUD

An external, always-on-top game HUD for iOS — runs as a standalone TrollStore app and floats a small overlay over **any** app, system-wide. Shows session time, clock, battery, CPU, RAM, network speed and FPS without touching the game itself.

Built on [TrollSpeed](https://github.com/Lessica/TrollSpeed) (MIT) — the same render-server window-hosting trick AssistiveTouch uses.

## Features

- Floating overlay above every app (backboard-hosted window, no jailbreak)
- **Two renderers** — a clean native UIKit pill, or a Dear ImGui + Metal panel
- Metrics: app name, **per-game session timer**, clock, battery, CPU, RAM, network, **FPS**
- 9 anchor positions, font size, colors, background opacity, update interval
- Landscape rotation
- Per-game session timer — counts only while your selected game's process is alive (detected by process path, so it works even when the display name ≠ binary name)
- Hide-from-screenshots/recording toggle

## Status / known issues

- **Touch is still WIP.** Tapping/dragging the ImGui menu doesn't work yet — input gets captured but moving the window isn't wired up right. The UIKit HUD and all the metrics work fine.
- "Screen FPS" is the display/compositor refresh rate (what an external overlay can actually measure), not the game's internal render FPS.

## Requirements

- iOS 14–17, **TrollStore**
- arm64

## Install

Grab the latest `.tipa` from [Releases](../../releases) and open it with TrollStore.

## Build

Needs [Theos](https://theos.dev).

```sh
export THEOS=/path/to/theos
make package
```

Output lands in `packages/`.

## Credits

- Based on **TrollSpeed** (MIT) © [Lessica](https://github.com/Lessica/TrollSpeed)
- Dear ImGui © ocornut

## Author

**xauszulay** — [Telegram](https://t.me/xauszulay) · [GitHub](https://github.com/xauszulay)
