# 已知问题与验证边界

以下适用于当前公开版本 0.9.4，并保留早期版本的验证记录。已知问题与尚未验证的环境分开记录，避免将基础测试通过等同于全部集成场景通过。

## 已知问题

- 可选集成测试 `PolicyRuntimeTests.testOcclusionPausesOnlyCoveredDisplayAndRespectsGlobalPause` 曾出现两个断言失败，且已在初始 `e83a208` 基线复现。默认测试未提供媒体环境时会跳过此用例；0.9.3 本次发布未重新运行这一可选场景。遮挡策略的多屏边界仍需进一步验证。
- `SubscriptionBrowser` 和订阅测试存在 `Any?` 到 `Any` 的编译警告。
- `DesktopPlaybackHost` 的主 RunLoop 回调存在 actor 隔离编译警告。当前以 Swift 5 语言模式构建，打包播放器启动、退出与登录状态查询测试通过；切换 Swift 6 语言模式前仍需处理此警告。

## 平台与行为边界

- 发布包仅提供 Apple Silicon / arm64，要求 macOS 14+。Intel 真机、其他设备和全部多屏/电源组合尚未完整验证。
- 应用使用本地 ad-hoc 签名，没有 Developer ID 公证，首次打开可能被 macOS 阻止。
- 设置中的“停止壁纸并完全退出”只保存各显示器当前 Space 的静态壁纸；其他 Space 保持原系统壁纸。强制结束进程不能执行保存。
- 重开恢复设置与动态播放，不承诺退出时间点的精确续播。
- 旧的 `ExitWallpapers/` 图片可能仍被其他 Space 使用，因此不会自动清理。
- Steam 网页结构、SteamCMD 登录与作品访问权限受外部服务影响；网页登录不等于下载会话已登录。
- 仅支持视频项目。原生解码受 AVFoundation 支持范围限制；转码依赖可用的 FFmpeg，并可能损失画质。

## 发布验证

0.9.4（build 24），2026-10-29：本机临时测试包执行 166 项测试，跳过 34 项，失败 0 项；另有 1 项测试环境检查。测试包加载应用的中文资源，并修正了一项旧测试对性能设置 JSON 类型的过时断言。真实 Steam 账号的订阅读取和界面交互已验证；未覆盖全部设备、多屏和电源组合。


0.9.3（build 22），2026-10-15：

- 本机默认测试 165 项，跳过 34 项，失败 0 项。
- 使用本次 Release 构建的播放器并启用真实公开 Steam 页面测试后，全套测试 165 项，跳过 31 项，失败 0 项。验证包括打包播放器的正常停止、登录状态查询不启动播放，以及公开工坊浏览和视频详情。
- Release 构建和主应用/嵌套播放器严格签名检查通过。未执行真实账号下载、个人媒体场景、全部多屏电源组合或旧遮挡集成用例；跳过项不代表已验证。

### 历史记录

2026-10-14 的本机默认测试执行 113 项，跳过 31 项，失败 0 项。跳过项依赖媒体样本、工具或账号环境；这不代表全部可选集成测试通过。准确的 CI 结果与跳过项以 [Actions 日志](https://github.com/luoshuang148/wallnamic/actions) 为准。

0.8.0 开发版本机默认测试执行 123 项，跳过 32 项，失败 0 项；额外启用真实公开 Steam 页面测试，WebKit 列表浏览与视频详情信息验证通过。本轮未执行真实账号的作品下载，也未重新验证原有遮挡集成场景。

报告新问题时，请附版本、系统、芯片、显示器数量及复现步骤，并对日志脱敏。

## English

These notes cover the published 0.9.4 release, retaining earlier validation records. Known failures and untested environments are listed separately.

### Known issues

- The optional occlusion integration test `PolicyRuntimeTests.testOcclusionPausesOnlyCoveredDisplayAndRespectsGlobalPause` previously failed two assertions, also reproduced at the initial `e83a208` baseline. It is skipped without media fixtures and was not rerun for 0.9.3. Multi-display occlusion behavior needs further validation.
- `SubscriptionBrowser` and its tests produce `Any?` to `Any` compiler warnings.
- The main RunLoop callback in `DesktopPlaybackHost` produces an actor-isolation warning in Swift 5 language mode. Packaged player launch, exit, and login-status tests pass; the warning still needs attention before switching to Swift 6 language mode.

### Platform and behavior limits

- Prebuilt downloads require macOS 14+ and Apple Silicon. Intel, other devices, and all display/power combinations have not been fully tested.
- The app is ad-hoc signed without Developer ID signing or notarization; macOS may block first launch.
- The complete-exit action in Settings saves still frames only for the current Space on each display. Force-quitting cannot save frames, and relaunch does not promise the exact previous playback position.
- Old `ExitWallpapers/` images are retained because other Spaces may still use them.
- Steam web structure, SteamCMD login, and access permissions depend on external services. Web login does not log into SteamCMD.
- Only video projects are supported. Native playback depends on AVFoundation codec support; optional FFmpeg conversion may reduce quality.

### Validation record

For 0.9.4 (build 24), a temporary local test package ran 166 tests with 34 skips and no failures, plus one test-environment check. The package loaded the app's Chinese resources and corrected an outdated JSON-type assertion in a temporary test copy. Subscription sync and UI interaction were checked with a real Steam account; not all devices, display configurations, or power conditions were covered.


For 0.9.3 (build 22), on 2026-10-15, the local default suite ran 165 tests with 34 skips and no failures. With the release-built player and public Steam page integration enabled, the full suite ran 165 tests with 31 skips and no failures. This includes packaged helper shutdown, login-status queries without playback, and public Workshop browsing and video details. Release build and strict signing verification passed for both application bundles.

Account downloads, personal media, all display/power combinations, and the older occlusion integration were not run. Skipped tests remain unverified.


The local default suite recorded for the 0.7.1 release on 2026-10-14 ran 113 tests, skipped 31, and failed none. Skips require media, tools, or account sessions and do not establish that optional integrations work. Check [Actions logs](https://github.com/luoshuang148/wallnamic/actions) for current CI results.

Report new issues with the app version, macOS version, chip, display count, and reproduction steps. Sanitize logs before posting.
