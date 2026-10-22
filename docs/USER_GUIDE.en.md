# Wallnamic user guide

> **Name change:** Wallnamic was formerly called WallFlow. The published 0.9.3 downloads still use the `WallFlow` name; builds from this source produce `Wallnamic.app`.

[Back to the homepage](../README.en.md) · [简体中文](USER_GUIDE.md)

Installation and menu paths below describe the published **0.9.3 (build 22)** app. For newer source builds, also check the [changelog](../CHANGELOG.md).

## Installation and updates

Download `WallFlow-0.9.3-macOS-arm64.dmg` (or the same-named `.zip`) from the [latest release](https://github.com/luoshuang148/wallnamic/releases/latest). Open the DMG and move `WallFlow.app` to Applications. For the ZIP, extract it first. Requires macOS 14+ and Apple Silicon. Intel has no prebuilt download and has not been fully tested.

The app is ad-hoc signed, without Developer ID signing or notarization. If macOS blocks it, try opening it first, then follow [Apple's instructions](https://support.apple.com/en-us/102445) under System Settings → Privacy & Security → Open Anyway. The release includes no wallpapers, SteamCMD, or FFmpeg.

Place `SHA256SUMS.txt` beside the DMG or ZIP and check integrity with:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

Before updating, choose **停止壁纸并完全退出** (Stop wallpaper and completely quit) in Settings and wait for the player to stop. On version 0.8.x and earlier, quit normally from the menu bar. Replace the app while keeping your original media and local data.

## Import and play

1. Choose **创意工坊 → 其他来源 → 导入壁纸文件夹…** (Workshop → Other sources → Import wallpaper folder) and select a complete folder containing `project.json` and its video.
2. Select a wallpaper, choose **应用到** (Display), **画面显示** (Fill/Fit), and **声音** (Audio), then apply. Audio choices take effect immediately and are saved.
3. Right-click the wallpaper or use the pencil beside its title to rename it. Use the star to mark favorites.
4. Open **设置 → 壁纸库与自动播放** (Settings → Library and autoplay) for groups, playlists, app rules, and login startup.
5. Open **设置 → 性能与电源** (Settings → Performance and power) for automatic pause policies.

Wallnamic references the original video files; keep them accessible. Removing an entry does not delete source media. Custom names remain local and do not modify `project.json`.

Closing the window hides management while playback continues. Menu-bar Quit and Command-Q quit management and remove its menu-bar icon; the independent **WallFlowPlayer** keeps playing videos, audio, and playlists and applying pause policies. Reopening Wallnamic reconnects to the running player without resetting playback.

To stop playback, choose **停止壁纸并完全退出** (Stop wallpaper and completely quit) at the bottom of Settings. This stops the background player and saves the current video frame as the system wallpaper. If an app rule released the player, the assigned video's first frame is used. Relaunching after a complete exit restores assignments, audio, and pause settings without promising the exact previous playback position.

Static wallpaper changes affect only each display's **current Space**. Other Spaces retain their system wallpapers. Force-quitting cannot perform exit saving.

Playlists are off by default and app rules start empty. On first launch, login startup defaults to running the background player directly, without a management window or menu-bar icon. Disabling startup in Settings is remembered. Login startup uses macOS Login Items and may need approval and an installation in Applications. macOS may also ask for access to protected folders containing imported media; files you deny access to cannot play.

## Quality and resource use (source candidate build 23)

Under **设置 → 性能与电源 → 画质模式** (Settings → Performance and power → Quality mode):

- **原画质** (Original) is the default. Desktop playback retains the source resolution and frame rate and creates no energy-saving copy.
- **省电** (Energy saving) prepares a copy capped at 1920 pixels on the longest edge and 30fps, without upscaling. Unprepared displays keep playing their original videos, with a preparation message. New copies are generated only on AC power, outside Low Power Mode and system suspension. Ready copies can play on battery.

HDR and unsupported conversions retain original quality and show a message. Switching back uses the source; originals are never overwritten. Published copies use a 1 GiB cache, excluding files currently playing from eviction. If pinned files exhaust the budget, new copies fall back to the source. Generation also needs temporary disk space and briefly consumes resources; assess playback savings after preparation finishes.

With occlusion pausing enabled, a desktop covered continuously for 30 seconds releases its decoder and restores when visible. Disabling that setting keeps hidden playback running. Lock, display sleep, and inactive sessions release resources immediately. Manual pause on a visible desktop keeps its still frame. Covers use a bounded image cache; animated previews retain original quality.

See the [performance report](performance/resource-efficiency-results.md) for measurements and validation limits. These source changes are not included in the public 0.9.3 build 22 download.

## Optional tools

### FFmpeg

Natively playable MP4 video projects do not require FFmpeg. Other formats are converted to H.264/MP4 with optional AAC audio. Re-encoding may reduce quality and consumes cache space; original files remain in place.

Install through Homebrew:

```bash
brew install ffmpeg
```

Alternatively, place an executable at `MediaTools/ffmpeg` beside the app. Wallnamic also checks `/opt/homebrew/bin/ffmpeg` and `/usr/local/bin/ffmpeg`. FFmpeg and conversion caches are not included in this repository.

### SteamCMD and Workshop

Workshop downloads require [Valve's SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) and a Steam account that owns Wallpaper Engine and can access the item. Local imports do not require either. SteamCMD, credentials, and wallpapers are not bundled.

Choose the `steamcmd` executable from the Workshop screen, or use this layout:

```text
Applications/
├── WallFlow.app
└── SteamTools/
    └── MacOS/
        └── steamcmd
```

The macOS SteamCMD tool is an Intel application and may require Rosetta on Apple Silicon. Keep the tool outside the signed application bundle so it can update independently.

Enter your account name under **下载账号** (Download account), then click **登录下载账号** (Log in to download account). Complete Steam login and Steam Guard in the terminal opened by the app. You can paste a Workshop link or item ID, or read your subscriptions and select video items to download and import.

**浏览工坊…** (Browse Workshop) opens the official website inside the app, initially filtered to Video. Search and select an item, then use **下载此作品** (Download this item) on eligible video details pages. Downloads are validated and imported without automatically changing the desktop. Browsing and subscription reading share the persistent WebKit web session.

Steam's web session and SteamCMD's download session are separate. Reading subscriptions does not subscribe, unsubscribe, or delete local wallpapers. Access depends on Steam and your account; deleted, hidden, or restricted items may be unavailable.

## Local data

For compatibility, settings remain under `~/Library/Application Support/VideoWallpaper/`:

| File or folder | Purpose |
| --- | --- |
| `state.json` | Library, display assignments, custom names, playback, and automation settings |
| `workshop.json` | Download account name and tool paths |
| `ConvertedVideos/` | Converted media cache; keep files still in use |
| `PlaybackVariants/` | Regenerable energy-saving copies; can be cleared after completely quitting the app |
| `Runtime/` | Singleton lease, current player session, and shutdown requests; no account credentials |
| `ExitWallpapers/` | Static frames installed as system wallpapers; older images may still be used by other Spaces |

WebKit manages the web session; SteamCMD manages download login. Wallnamic does not extract or copy passwords, cookies, or login tokens into the repository. Build output, media, tool folders, local settings, Steam sessions, logs, and common credentials are excluded by `.gitignore`.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Cannot open the app | System requirements and Apple's Open Anyway procedure above |
| Import rejected | A complete video project with `project.json`; Scene, web, and application projects are unsupported |
| Media cannot be found | Original folder remains accessible; macOS has permitted access where required |
| Conversion fails | FFmpeg executable, readable source media, and free cache space |
| Download requests login | SteamCMD needs its own login even if the webpage is logged in |
| Wallpaper stays paused | Your power, occlusion, and per-app playback policies |
| Playback continues after closing | Closing and management Quit preserve playback; use the complete-exit action in Settings |

See [known issues](KNOWN_ISSUES.md) for validation limits. If the issue remains, use the [bug report form](https://github.com/luoshuang148/wallnamic/issues/new?template=bug_report.yml), or the [help form](https://github.com/luoshuang148/wallnamic/issues/new?template=question.yml) for usage questions. Remove account details, personal paths, credentials, and session data from attachments.

## Uninstall

Disable login startup in Settings, then choose **停止壁纸并完全退出** (Stop wallpaper and completely quit). Once the background player has stopped, move the app to Trash.

Deleting the app does not remove local settings. If you no longer need them, open `~/Library/Application Support/VideoWallpaper/` with Finder's Go to Folder and manually remove settings and caches. This does not delete original videos. Replace system wallpapers before removing `ExitWallpapers/`, because other Spaces may still reference these images.
