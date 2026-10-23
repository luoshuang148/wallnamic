<p align="center">
  <img src="docs/assets/icon.png" width="88" height="88" alt="Wallnamic icon">
</p>

<h1 align="center">Wallnamic</h1>
<p align="center"><strong>Bring motion to your Mac.</strong><br>A native macOS video wallpaper app for your favorite videos, on every display.</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="https://github.com/luoshuang148/wallnamic/releases/latest">Download</a> ·
  <a href="docs/USER_GUIDE.en.md">User guide</a> ·
  <a href="https://github.com/luoshuang148/wallnamic/issues/new/choose">Feedback</a>
</p>

<p align="center">
  <a href="https://github.com/luoshuang148/wallnamic/releases/latest"><img src="https://img.shields.io/github/v/release/luoshuang148/wallnamic?label=release&amp;color=2675d8" alt="Latest release"></a>
  <a href="https://github.com/luoshuang148/wallnamic/actions/workflows/ci.yml"><img src="https://github.com/luoshuang148/wallnamic/actions/workflows/ci.yml/badge.svg" alt="macOS CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-555555?logo=apple&amp;logoColor=white" alt="macOS 14 or newer">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2675d8" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/download-Apple%20Silicon-2675d8" alt="Apple Silicon download">
</p>

![Wallnamic brand illustration: flowing video across two displays, not an app screenshot](docs/assets/hero.svg)

Wallnamic is for Mac users who want video wallpapers, a personal wallpaper library, or support for importing Wallpaper Engine video projects. Built with SwiftUI, AppKit, and AVFoundation, it plays local video projects and uses SteamCMD to download Workshop videos your account can access.

> **Before downloading:** The published app is **0.9.3**, for **macOS 14+ and Apple Silicon (M-series chips)**. The app interface is currently **Simplified Chinese**. Only **video wallpapers** are supported; Scene, web, and application wallpapers are outside the current scope. The app is not notarized by Apple.

[Features](#features) · [Install](#install) · [Get started](#get-started) · [FAQ](#faq) · [Contribute](#contribute)

## Features

| Feature | What you can do |
| --- | --- |
| Multiple displays | Assign videos independently and choose fill or fit |
| Animated previews | Preview videos silently at their original aspect ratio |
| Personal library | Search by name or ID, rename, favorite, group, and sort |
| Automatic switching | Configure sequential or random playlists, day/night switching, and target displays |
| Audio controls | Mute or play audio, with sound from only one playing display at a time |
| Resource efficiency (source candidate) | Keep original quality by default; optionally cap playback at 1920 / 30fps and release inactive decoders |
| Playback policies | Adjust playback for desktop occlusion, battery, Low Power Mode, lock, sleep, or specific apps |
| Workshop imports | Browse the official Workshop in-app and download videos, use links/IDs, read subscriptions, or scan local downloads |
| Format conversion | Use optional FFmpeg to convert unsupported videos while retaining originals |
| Still frames on exit | Keep playback running after quitting management; save a still frame on complete exit and restore settings on relaunch |

Source builds may differ from the published download; check the [changelog](CHANGELOG.md). Not every hardware, codec, or display configuration has been validated. See [known issues](docs/KNOWN_ISSUES.md).

## Install

> **Name change:** Wallnamic was formerly called WallFlow. The published 0.9.3 downloads still use the `WallFlow` name; builds from this source produce `Wallnamic.app`.

1. Open [Releases](https://github.com/luoshuang148/wallnamic/releases/latest) and download `WallFlow-0.9.3-macOS-arm64.dmg` (or the same-named `.zip`).
2. Open the DMG, move `WallFlow.app` to **Applications**, and open it. For the ZIP, extract it first, then move the app.
3. If macOS blocks the app, try opening it first, then use **System Settings → Privacy & Security → Open Anyway**. Follow [Apple's official instructions](https://support.apple.com/en-us/102445) to approve an exception for this app.

The download is ad-hoc signed, without Developer ID signing or Apple notarization. There is no prebuilt Intel download, and Intel hardware has not been fully tested. Wallpapers, SteamCMD, and FFmpeg are not bundled.

<details>
<summary>Verify your download and update an existing installation</summary>

Place the release's `SHA256SUMS.txt` beside the DMG or ZIP and run:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

Choose **停止壁纸并完全退出** (Stop wallpaper and completely quit) in Settings before replacing the app. On version 0.8.x and earlier, quit normally from the menu bar. Keep original videos and local data. [Installation and uninstall details](docs/USER_GUIDE.en.md)

</details>

## Get started

1. Prepare a complete video wallpaper folder containing `project.json` and its video.
2. Choose **创意工坊 → 其他来源 → 导入壁纸文件夹…** (Workshop → Other sources → Import wallpaper folder).
3. Select the wallpaper, choose **应用到** (Display), **画面显示** (Fill/Fit), and **声音** (Audio), then apply it.

Natively playable MP4 video projects need no additional tools. **Local imports do not require a Steam account or a Wallpaper Engine purchase.** Workshop downloads require [Valve's SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) and a Steam account that owns Wallpaper Engine and can access the item. Other video formats may require FFmpeg.

Wallnamic references original media in place, so keep imported folders available. Removing a library entry does not delete source files, and renaming does not modify the source `project.json`.

The [user guide](docs/USER_GUIDE.en.md) covers tool setup, playlists, power policies, login startup, and local data.

## FAQ

**Does it support every Wallpaper Engine wallpaper?** Only video projects. Scene, web, and application projects are not supported.

**Why does playback continue after closing the window?** Closing the window hides management. Menu-bar Quit and Command-Q quit management while the independent background player keeps playing. Use **停止壁纸并完全退出** (Stop wallpaper and completely quit) in Settings to stop playback and save a still frame.

**Does quitting update every Space?** Only the current Space on each display. Force-quitting cannot save exit frames.

**Why does downloading ask me to log in again?** Steam's webpage and SteamCMD use separate sessions.

**Having trouble installing, playing, or converting?** Check the [user guide](docs/USER_GUIDE.en.md#troubleshooting) and [known issues](docs/KNOWN_ISSUES.md), then submit reproduction steps using the [issue forms](https://github.com/luoshuang148/wallnamic/issues/new/choose). [Get help](SUPPORT.md)

## Source localization status

The source now includes ten interface languages: Simplified and Traditional Chinese, English, Japanese, Korean, German, French, Spanish, Russian, and Brazilian Portuguese. Settings → Language switches between Follow System and any of them immediately, and resource checks and compilation pass. The public **0.9.3 package still has a Chinese-only interface**. Everything beyond Simplified Chinese and English is an initial translation that has not yet been reviewed by native speakers or visually accepted in the running app, so each language still needs a full UI pass before a multilingual binary release. See [localization and language support](docs/LOCALIZATION.md).

## Build from source

Use a Swift 6-capable Xcode toolchain on macOS 14+:

```bash
git clone https://github.com/luoshuang148/wallnamic.git
cd wallnamic
./build.sh
open dist/Wallnamic.app
```

See the [development guide](docs/DEVELOPMENT.md) for the code map and build options. CI builds the app and verifies signing.

## Contribute

Everyone is welcome to participate in Chinese or English, including without writing code:

- [Report a bug](https://github.com/luoshuang148/wallnamic/issues/new?template=bug_report.yml) with your version, device details, and reproduction steps.
- [Suggest a feature](https://github.com/luoshuang148/wallnamic/issues/new?template=feature_request.yml) by describing a real use case and desired behavior.
- Improve documentation, translate guides, or submit a focused Pull Request. Read the [contributing guide](CONTRIBUTING.md) first.

Report vulnerabilities through [private vulnerability reporting](https://github.com/luoshuang148/wallnamic/security/advisories/new); see the [security policy](SECURITY.md). Remove accounts, personal paths, and session data from screenshots and logs.

## Licensing and third-party content

Wallnamic is released under the [MIT License](LICENSE). Third-party tools and wallpapers are not covered by this project's license.

Wallnamic is independent and unaffiliated with Valve, Steam, or Wallpaper Engine. Third-party tools and wallpapers retain their own licenses and author permissions. Only import or share content you are entitled to use.
