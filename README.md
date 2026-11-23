<h1 align="center">Click</h1>

<a href="#"><img width="256" height="256" src="./.github/images/icon_512x512.png" align="left" /></a>

<br />

### Mechanical Keyboard sounds.

Transform your Mac typing experience with the satisfying sounds of premium mechanical keyboards. Using high-quality [Mechvibes](https://github.com/hainguyents13/mechvibes/) sound packs, Click brings the tactile audio feedback of mechanical switches to any keyboard.

> **Credit & Attribution:** This repository is a fork of [**Click**](https://github.com/pruizlezcano/click) originally created by **Pablo Ruiz ([@pruizlezcano](https://github.com/pruizlezcano))**. All original design, code, and assets are credited to the original author under the [GPL-3.0 License](./LICENSE), with sound packs adapted from [Mechvibes](https://github.com/hainguyents13/mechvibes/).
>
> You can also support the original author via the [Mac App Store](https://apps.apple.com/us/app/click-keyboard-sounds/id6740429323).

<a href="https://apps.apple.com/us/app/click-keyboard-sounds/id6740429323"><img height="56" src="./.github/images/app_store_badge.svg"/></a>

## Features

🎵 Premium Sound Quality
- Authentic mechanical keyboard recordings
- Multiple popular switch types including EG Crystal Purple, EG Oreo, NK Cream, and more
- Zero latency audio playback

⚡ Performance Focused
- Minimal CPU usage
- Runs efficiently in the background
- No impact on battery life

⚙️ Easy to Use
- Works instantly with your existing keyboard
- Simple, intuitive controls
- Clean, native macOS design

## Installation

### Option 1: Prebuilt Installation Packages (Recommended)

1. Download the latest installer package from [GitHub Releases](https://github.com/mzia/click/releases/latest):
   - **`Click-1.2.dmg`** — open the disk image and drag **Click.app** into **Applications**
   - **`Click-1.2.zip`** — unzip and move **Click.app** into **Applications**
2. Launch **Click** from `/Applications`.
   - Because fork builds are locally ad-hoc signed (not notarized with an Apple Developer ID), if macOS blocks the first launch, right-click **Click.app** → **Open** (or allow it in **System Settings → Privacy & Security**).
3. Grant Accessibility permissions when prompted:
   - Open **System Settings → Privacy & Security → Accessibility** (scroll down the right-hand list in Privacy & Security, or click the arrow button in Click's authorization window).
   - If an older **Click** entry already exists, remove it with **`-`** first, then click **`+`** to add `/Applications/Click.app` and toggle it **ON**.
   - Quit and relaunch Click if it does not automatically switch to the main window.
4. Select your preferred switch sound and start typing!

### Option 2: Build and Install from Source

Requires Xcode on macOS 14.0+.

```bash
# Build and install directly to /Applications/Click.app
./scripts/build-and-install.sh --install

# Build universal (Apple Silicon + Intel) and create DMG/ZIP packages in ./dist
./scripts/build-and-install.sh --universal --package
```

### Option 3: Original Mac App Store Release

Install the original author's release from the [Mac App Store](https://apps.apple.com/us/app/click-keyboard-sounds/id6740429323) for automatic updates.

## Changes in This Fork

- Updated the pinned `Defaults` SwiftPM revision in `Package.resolved` to a reachable commit on `main` (`9.0.9`) so source builds resolve cleanly.
- Added [`scripts/build-and-install.sh`](./scripts/build-and-install.sh) to build, ad-hoc sign (without Hardened Runtime so embedded `ogg`/`vorbis` frameworks load cleanly), install to `/Applications/Click.app`, and generate `.dmg` and `.zip` installation packages.
- Published prebuilt `.dmg` and `.zip` installation packages on [GitHub Releases](https://github.com/mzia/click/releases).

## System Requirements

- macOS 14.0 Sonoma or later
- Compatible with Apple Silicon and Intel processors
- Minimal disk space required

## Privacy & Permissions

Click requires Accessibility permissions to detect keystrokes. Click does not collect or store any typing data — all processing happens locally on your device.

## Support & Troubleshooting

### Troubleshooting

If you don't hear any sounds or **Enable Click** is greyed out:
- Open **System Settings → Privacy & Security → Accessibility** (scroll down in Privacy & Security).
- If you previously installed a different build of Click, remove the old entry with **`-`**, re-add `/Applications/Click.app` with **`+`**, and enable it.
- Check your system volume and output device.
- Quit and relaunch Click.

### Need Help?

- For issues specific to this fork or its installation packages, open an issue on [mzia/click Issues](https://github.com/mzia/click/issues).
- For upstream Click development, visit the original repository at [pruizlezcano/click](https://github.com/pruizlezcano/click).

## Credits & License

- **Original Author:** Pablo Ruiz ([@pruizlezcano](https://github.com/pruizlezcano)) — [pruizlezcano/click](https://github.com/pruizlezcano/click)
- **Sound Packs:** [Mechvibes](https://github.com/hainguyents13/mechvibes/)
- **License:** [GNU General Public License v3.0](./LICENSE)
