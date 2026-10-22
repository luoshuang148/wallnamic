<p align="center">
  <img src="docs/assets/icon.png" width="88" height="88" alt="Wallnamic 图标">
</p>

<h1 align="center">Wallnamic</h1>
<p align="center"><strong>让 Mac 桌面流动起来。</strong><br>原生 macOS 视频壁纸应用，将你喜欢的视频带到每一块屏幕。</p>

<p align="center">
  <a href="README.en.md">English</a> ·
  <a href="https://github.com/luoshuang148/wallnamic/releases/latest">下载安装</a> ·
  <a href="docs/USER_GUIDE.md">使用指南</a> ·
  <a href="https://github.com/luoshuang148/wallnamic/issues/new/choose">反馈与建议</a>
</p>

<p align="center">
  <a href="https://github.com/luoshuang148/wallnamic/releases/latest"><img src="https://img.shields.io/github/v/release/luoshuang148/wallnamic?label=release&amp;color=2675d8" alt="最新发布版本"></a>
  <a href="https://github.com/luoshuang148/wallnamic/actions/workflows/ci.yml"><img src="https://github.com/luoshuang148/wallnamic/actions/workflows/ci.yml/badge.svg" alt="macOS CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-555555?logo=apple&amp;logoColor=white" alt="macOS 14 或更新版本">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2675d8" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/download-Apple%20Silicon-2675d8" alt="下载适用于 Apple Silicon">
</p>

![Wallnamic 品牌插画：流动的视频画面延伸到两块显示器，并非应用截图](docs/assets/hero.svg)

Wallnamic 适合希望在 Mac 上播放视频壁纸、管理自己的壁纸库，或导入 Wallpaper Engine 视频作品的用户。它使用 SwiftUI、AppKit 和 AVFoundation 构建，支持本地视频项目，以及通过 SteamCMD 下载有权访问的创意工坊视频作品。

> **下载前请确认：** 公开安装包为 **0.9.3**，要求 **macOS 14+、Apple Silicon（M 系列芯片）**；应用界面目前为简体中文。仅支持**视频壁纸**，不支持 Scene、网页或程序壁纸。安装包尚未经过 Apple 公证。

[功能](#功能亮点) · [安装](#下载安装) · [开始使用](#开始使用) · [常见问题](#常见问题) · [贡献](#参与项目)

## 功能亮点

| 功能 | 你可以做什么 |
| --- | --- |
| 多屏播放 | 为各显示器独立分配视频，选择铺满或完整显示 |
| 动态预览 | 在应用前静音预览视频，保持原始画面比例 |
| 壁纸库 | 按名称或编号搜索，重命名、收藏、分组和排序 |
| 自动切换 | 设置顺序或随机轮播、日夜切换和目标屏幕 |
| 声音控制 | 选择静音或播放声音，多屏时只由一块正在播放的屏幕出声 |
| 资源优化（源码候选） | 默认保留原画质；可选最高 1920 / 30fps 省电模式，闲置时释放解码资源 |
| 播放策略 | 根据桌面遮挡、电池、低电量模式、锁屏、休眠或指定应用调整播放 |
| 创意工坊导入 | 内嵌浏览官方工坊并下载视频，按链接或编号下载，读取订阅和扫描本机项目 |
| 格式转换 | 通过可选的 FFmpeg 转换无法原生播放的视频，保留原文件 |
| 退出保留画面 | 退出管理程序后后台继续播放；完整退出时保留静态画面，重新打开恢复设置 |

源码版本的行为可能与公开安装包不同，请查看[更新日志](CHANGELOG.md)。本项目不承诺所有硬件、编码和多屏组合都已验证，具体边界见[已知问题](docs/KNOWN_ISSUES.md)。

## 下载安装

> **名称说明：** Wallnamic 原名 WallFlow。当前公开 0.9.3 安装包仍使用 `WallFlow` 名称；本仓库源码构建输出为 `Wallnamic.app`。

1. 前往 [Releases](https://github.com/luoshuang148/wallnamic/releases/latest)，下载 `WallFlow-0.9.3-macOS-arm64.dmg`（或同名 `.zip`）。
2. 打开 DMG，将 `WallFlow.app` 拖入 **应用程序** 文件夹，再打开；使用 ZIP 时先解压再拖入。
3. 如果 macOS 阻止打开，在尝试打开后前往 **系统设置 → 隐私与安全性 → 仍要打开**。请按 [Apple 官方说明](https://support.apple.com/zh-cn/102445)确认该应用的例外。

发布包使用本地 ad-hoc 签名，尚无 Developer ID 签名和 Apple 公证。Intel Mac 暂无预编译安装包，也尚未在真机完整验证。安装包不包含壁纸、SteamCMD 或 FFmpeg。

<details>
<summary>校验下载与更新已有安装</summary>

将 Release 的 `SHA256SUMS.txt` 和 DMG/ZIP 放在同一目录，然后运行：

```bash
shasum -a 256 -c SHA256SUMS.txt
```

更新前先在 **设置** 中选择 **停止壁纸并完全退出**，确认后台已停止，再替换应用；0.8.x 及更早版本使用菜单栏退出。保留原视频和本地数据目录。[详细安装与卸载说明](docs/USER_GUIDE.md)

</details>

## 开始使用

1. 准备一个包含 `project.json` 和视频文件的完整视频壁纸文件夹。
2. 在 **创意工坊 → 其他来源 → 导入壁纸文件夹…** 中选择该文件夹。
3. 选中壁纸，设置 **应用到**、**画面显示** 和 **声音**，再点击应用。

原生可播放的 MP4 视频项目无需额外工具。**本地导入不要求 Steam 账号或 Wallpaper Engine 购买记录**；创意工坊下载需要 [Valve SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) 和拥有 Wallpaper Engine、可访问对应作品的 Steam 账号。其他视频格式可能需要 FFmpeg。

Wallnamic 引用原视频文件，请保留导入文件夹。从壁纸库移除记录不会删除原文件，重命名也不会修改源 `project.json`。

查看[完整使用指南](docs/USER_GUIDE.md)，了解工具配置、轮播、电源策略、登录启动和本地数据。

## 常见问题

**支持 Wallpaper Engine 的所有壁纸吗？** 仅支持视频项目。Scene、网页和程序项目不在当前支持范围内。

**为什么关闭窗口后仍在播放？** 关闭窗口会收起管理界面。从菜单栏退出或按 `⌘Q` 会退出管理程序，独立后台播放器继续播放；在 **设置 → 停止壁纸并完全退出** 中停止播放并保留静态画面。

**退出时会更新所有桌面空间吗？** 只更新每块显示器当前所在的 Space。强制结束进程无法保存退出画面。

**网页已登录，为什么下载还需要登录？** Steam 网页和 SteamCMD 是独立会话，需要分别登录。

**遇到播放、转换或安装问题怎么办？** 先查看[使用指南](docs/USER_GUIDE.md#常见问题)和[已知问题](docs/KNOWN_ISSUES.md)，仍有问题可用[问题模板](https://github.com/luoshuang148/wallnamic/issues/new/choose)提交复现步骤。[获取帮助](SUPPORT.md)

## 源码本地化状态

当前源码已加入简体中文和英文本地化资源，并通过资源完整性与构建检查；**公开 0.9.3 安装包仍只有中文界面**。本轮未进行中英界面的实机视觉验收，发布英文安装包前还需检查完整流程。见[本地化验证说明](docs/LOCALIZATION.md)。

## 从源码构建

需要 macOS 14+ 和支持 Swift 6 的 Xcode 工具链：

```bash
git clone https://github.com/luoshuang148/wallnamic.git
cd wallnamic
./build.sh
open dist/Wallnamic.app
```

开发与模块说明、构建参数见[开发指南](docs/DEVELOPMENT.md)。CI 会构建应用并做签名检查。

## 参与项目

欢迎所有用户参与，中文或英文均可，也欢迎不写代码的贡献：

- [报告问题](https://github.com/luoshuang148/wallnamic/issues/new?template=bug_report.yml)：提供版本、设备信息和复现步骤。
- [提出建议](https://github.com/luoshuang148/wallnamic/issues/new?template=feature_request.yml)：描述真实使用场景和希望的行为。
- 改进文档、翻译说明，或提交聚焦单个问题的 Pull Request，开始前请阅读[贡献指南](CONTRIBUTING.md)。

安全漏洞请通过[私密报告入口](https://github.com/luoshuang148/wallnamic/security/advisories/new)反馈，详见[安全说明](SECURITY.md)。上传截图和日志前请隐藏账号、个人路径和会话数据。

## 许可与第三方资源

Wallnamic 以 [MIT 许可证](LICENSE)发布。第三方工具与壁纸资源不包含在本项目的授权范围内。

Wallnamic 是独立项目，与 Valve、Steam、Wallpaper Engine 无隶属或官方合作关系。第三方工具与壁纸遵循各自许可和作者授权；请只导入或分享你有权使用的资源。
