# 更新日志 / Changelog

仅记录已有提交能确认的变化。日期使用 Asia/Shanghai。

## 未发布 / Unreleased — 资源优化候选，build 23

- 默认保留桌面原画质；新增独立省电模式（最长边 1920、最高 30fps、不放大），原件回退、HDR 提示、单任务生成与 1 GiB 缓存。
- 状态心跳调整为 5 秒，设置以通知同步、30 秒元数据兜底；减少重复写入和不变状态的界面发布。
- 静音预览使用无声轨素材，桌面循环项遵守当前声音路由；挂起和长期遮挡时卸载闲置解码资源。
- 取消过时准备任务，列表和封面改用异步缩略图及 24 MiB 缓存；同路径封面在重新导入或打开时刷新。
- 修复慢加载期间的状态过期、恢复时短暂出声、再次挂起后旧恢复任务复活，以及崩溃残留的省电临时文件。

- Preserve original desktop quality by default; add an optional 1920 / 30fps energy-saving mode, source fallback, HDR messaging, serial generation, and a 1 GiB cache.
- Replace frequent polling with notifications, a five-second heartbeat, and a 30-second metadata fallback; avoid duplicate writes and unchanged UI updates.
- Use silent preview assets, enforce audio policy across loop items, release inactive decoders, and cancel obsolete preparations.
- Bound asynchronous thumbnails to 24 MiB and refresh replaced covers on import/reopen. Harden restoration, status freshness, and abandoned export cleanup.

Validation and measured limits: [resource efficiency report](docs/performance/resource-efficiency-results.md). Candidate only; no public release or installed app replacement.

## [0.9.3](https://github.com/luoshuang148/wallflow/releases/tag/v0.9.3) — 2026-10-15

本次公开发布包含 0.8.0–0.9.3 的全部开发改动，build 22。
This release includes all development changes from 0.8.0 through 0.9.3 (build 22).

### 新增与改进 / Added and improved

- 内嵌官方 Steam 创意工坊浏览、筛选与视频下载；浏览和订阅读取共享网页会话。
- 独立后台播放器：退出管理界面或按 `⌘Q` 后继续播放、轮播、声音及自动暂停规则；再次打开连接已有播放进度。
- 设置中的“停止壁纸并完全退出”停止后台并保留各屏当前 Space 的静态画面。
- 登录启动默认直接运行后台播放器；迁移旧登录项，保留用户关闭选择与系统授权状态。
- 新版 WallFlow 图标、面向公众的双语文档和 MIT 许可证。

- Browse the official Steam Workshop in-app, filter videos, and download eligible items using SteamCMD.
- Keep wallpaper playback, playlists, audio, and pause policies running in an independent player after quitting management.
- Reconnect to the running player on reopen; use the complete-exit action in Settings to stop playback and save still frames for each display's current Space.
- Launch the background player directly at login, preserving user choices and macOS approval status during migration.
- Updated branding, public bilingual documentation, and the MIT License.

### 更新提示 / Updating

从 0.7.1 升级：先从旧版菜单栏退出再替换应用。使用 0.9.x 开发版时，先在设置中选择“停止壁纸并完全退出”。保留原媒体和本地数据。签名仍为 ad-hoc，尚无 Developer ID 签名或 Apple 公证；安装包要求 macOS 14+、Apple Silicon。

From 0.7.1, quit normally from the menu bar before replacing the app. From a 0.9.x development build, use the complete-exit action in Settings first. Keep original media and local data. The download requires macOS 14+ and Apple Silicon; it remains ad-hoc signed without Developer ID signing or Apple notarization.

### 0.9.3 登录启动修复 / Login startup fixes

- 登录项直接注册后台播放程序 WallFlowPlayer，成功后移除旧的管理程序登录项。
- 登录启动查询与修改不创建壁纸播放实例；关闭自启保留当前播放。
- 迁移尊重系统撤销的授权与用户关闭选择，失败提示并可重试。

## 0.9.2 — 开发阶段，已包含在 0.9.3 / Development changes included in 0.9.3

- 管理程序拥有菜单栏图标，普通退出和 `⌘Q` 同时移除图标并保持后台播放；重新打开软件进入设置可停止壁纸。
- 首次打开默认启用登录后后台播放，不显示管理窗口或菜单栏图标；用户关闭自启后保持选择。
- 根据系统登录启动事件仅拉起后台后退出，手动打开显示管理界面；关闭自启不会结束当前播放。

## 0.9.1 — 开发阶段，已包含在 0.9.3 / Development changes included in 0.9.3

- 菜单栏“退出 WallFlow”和 `⌘Q` 都只退出管理程序，保持后台动态播放；完整退出入口统一保留在设置。
- 保留点击已应用壁纸名称查看详情的功能。

## 0.9.0 — 开发阶段，已包含在 0.9.3 / Development changes included in 0.9.3

- `⌘Q` 退出管理程序后，独立后台播放器继续播放；重新打开管理程序连接已有后台，不重新开始视频。
- 设置底部提供“停止壁纸并完全退出”，停止后台并沿用退出静态画面保存机制。
- 后台继续负责轮播、多屏声音、应用规则、休眠、锁屏和电源暂停；登录启动仍需用户选择启用。
- 通过单实例锁和会话绑定退出请求防止重复播放器及旧请求误停；管理程序与后台协调保存设置，冲突会提示重试。
- 更新应用前需要完全退出后台；构建脚本先签名嵌套播放器，再签名主应用。
- 后台启动只读取已应用到在线屏幕的壁纸，轮播到其他作品时再校验；未使用的目录不影响播放恢复。
- 设置面板打开时也能正常 ⌘Q 或完整退出，退出通知通过原生事件循环处理，避免异步保存画面时发生等待。

## 0.8.0 — 开发阶段，已包含在 0.9.3 / Development changes included in 0.9.3

- 创意工坊首页优先展示浏览和订阅读取；文件夹导入、链接下载和本机已下载导入收进“其他来源”菜单。
- 新增内嵌 Steam 创意工坊浏览入口，使用官方搜索、分类、排序和详情页；默认筛选 Video。
- 在支持的视频详情页点击“下载此作品”即可使用现有 SteamCMD 会话下载并导入，保留手动链接输入和当前桌面设置。
- 浏览与订阅读取共享网页会话；页面切换、关闭或取消后忽略过期作品信息。
- 更新为用户确认的 WallFlow 图标：双色蓝、叠层圆角框、齿轮与中心流动符号。

## [0.7.1](https://github.com/luoshuang148/wallflow/releases/tag/v0.7.1) — 2026-10-14

### 修复 / Fixed

- 正常退出时将各屏幕已应用视频的当前画面保存为 macOS 静态壁纸，避免退出后壁纸消失。屏幕播放器已被应用规则释放时使用已分配视频的首帧。
- 退出期间冻结播放、轮播和待处理的异步应用操作，阻止晚到请求重新播放或覆盖设置。
- 某屏幕保存失败不会阻碍其他屏幕；可重试或仍然退出，失败屏幕保留原系统壁纸。
- 再次启动恢复原有壁纸分配、声音、暂停和画面显示设置。

### 发布与文档 / Distribution and documentation

- 首次 GitHub Release：macOS 14+、Apple Silicon 安装包与 SHA-256 校验文件。
- 中英文项目说明、贡献指南、问题反馈模板、安全报告说明与 macOS CI。

### 限制 / Limitations

- 退出保存只更新各屏幕当前所在的 Space；强制结束不执行保存。历史静态图片可能被其他 Space 引用，因此不自动删除。
- 预编译应用为 ad-hoc 签名，尚未 Developer ID 签名或公证；Intel 真机未完整验证。
- 默认测试不涵盖全部可选集成路径；原有遮挡集成用例仍有已知失败，见 [已知问题](docs/KNOWN_ISSUES.md)。

## 0.7.0 — 2026-10-13

### 新增 / Added

- 选中壁纸后静音循环预览，保持视频实际比例；侧栏缩略图仍为静态。
- 首帧准备期间和播放失败时回退封面；预览独立于桌面播放与声音设置。
- 窗口隐藏、最小化、完全遮挡、休眠或打开其他管理界面时释放预览播放器；快速切换时忽略过期准备结果。

此版本对应提交 `a8ae689`，未单独创建 GitHub Release。

## 0.6.4 — 2026-10-13

首次公开源码提交 `e83a208`，包含视频桌面播放、多屏分配、壁纸库管理、轮播、应用与电源策略、Steam 创意工坊导入和视频转换。未为该历史版本补发二进制安装包。
