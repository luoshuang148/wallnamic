# 本地化与多语言支持

Wallnamic 的界面文案全部通过 `L("key")` 在 `Localizable.strings` 中查找。主应用和内嵌登录项 WallFlowPlayer 各自携带同一套表，开发语言为 `zh-Hans`。

## 支持的语言

| 语言 | 目录 | Steam 工坊语言 |
| --- | --- | --- |
| 简体中文（开发语言） | `zh-Hans.lproj` | `schinese` |
| 繁體中文 | `zh-Hant.lproj` | `tchinese` |
| English | `en.lproj` | `english` |
| 日本語 | `ja.lproj` | `japanese` |
| 한국어 | `ko.lproj` | `koreana` |
| Deutsch | `de.lproj` | `german` |
| Français | `fr.lproj` | `french` |
| Español | `es.lproj` | `spanish` |
| Русский | `ru.lproj` | `russian` |
| Português (Brasil) | `pt-BR.lproj` | `brazilian` |

系统按“系统设置 → 通用 → 语言与地区”中的首选语言匹配最接近的表；葡萄牙语（葡萄牙）等地区变体会匹配到 `pt-BR`，没有匹配的语言回退到开发语言 `zh-Hans`。两个 `Info.plist` 的 `CFBundleLocalizations` 声明了全部语言。用户自带的壁纸标题、Steam 账号名、显示器硬件名，以及错误提示里的文件名保持原文。

## 应用内语言设置

设置 → 语言（`settings.language`）可随时切换界面语言，默认“跟随系统”。选项为跟随系统加 10 种语言，名称使用各语言自称。切换立即生效：主窗口、设置、菜单栏状态菜单和应用菜单同步刷新，正在播放的壁纸不会中断。

选择保存在 `local.zongzihao.Wallnamic.shared` 的 `interfaceLanguage` 键（`system` 或语言代码），并通过分布式通知 `local.zongzihao.Wallnamic.languageChanged` 通知内嵌的 WallFlowPlayer 重新读取语言表；播放器之后的菜单与弹窗使用新语言。`system` 按系统首选语言匹配，匹配不到回退 `zh-Hans`。没有保存值或保存了已移除的语言代码时，也按系统语言处理。

`WorkshopBrowser` 在打开工坊页面时读取当前语言的 Steam 代码；已经打开的网页需要重新打开后才会切换工坊语言。

## 校验

```sh
python3 scripts/check_localization.py
python3 -m unittest discover -s scripts -p 'test_*.py'
./build.sh
```

`check_localization.py` 会自动发现 `Resources/*.lproj`，要求 `en` 与 `zh-Hans` 存在，并逐语言检查：键集合一致、无重复键、无空值、`%@`/`%ld` 等格式参数一致，Swift 中 `L("...")` 和嵌入脚本里的 `error('...')` 都有定义，以及两个 `Info.plist` 的 `CFBundleLocalizations` 与发现的 `.lproj` 完全对应。新增语言不需要改脚本。

`build.sh` 会复制全部 `*.lproj` 到两个 App，并在构建前运行本地化检查；可用 `WALLNAMIC_CHECK_LOCALIZATION=0` 跳过。单独校验语法：

```sh
for f in Resources/*.lproj/Localizable.strings; do plutil -lint "$f"; done
```

## 新增一种语言

1. 复制 `Resources/en.lproj/Localizable.strings` 为 `Resources/<code>.lproj/Localizable.strings`。
2. 逐条翻译值，键名、顺序、`\n` 与格式占位符保持不变；`workshop.browser.steamLanguage` 填 Steam 语言代码，不是界面文字。
3. 在 `Resources/Info.plist` 与 `Resources/PlayerInfo.plist` 的 `CFBundleLocalizations` 中加入该语言代码。
4. 运行上面的校验与 `./build.sh`；确认两个 App 的 `Contents/Resources` 都包含新增的 `.lproj`。

## 验收状态

- 0.9.4 的 zh-Hans 与 en 做过一轮实机界面验收（记录见下）。
- 2026-10-23 新增的繁体中文、日语、韩语、德语、法语、西班牙语、俄语和巴西葡萄牙语来自集中翻译初稿，已通过键值/格式校验与构建，但尚未由母语者审校，也未做实机界面验收。发布多语言安装包前，需逐语言检查主窗口、设置、创意工坊、菜单栏、弹窗和长文本截断；未经实机验收不要对外宣称完整的多语言体验。
- 同日完成自动校验：10 种语言 × 333 键通过 `check_localization.py` 与 23 个单元测试；`dist/Wallnamic.app` 及内嵌 `WallFlowPlayer.app` 均包含 10 个 `.lproj`，`codesign --verify --deep --strict` 通过；用独立探测 App 以 `-AppleLanguages` 逐语言读取 `library.settings` 与 `workshop.browser.steamLanguage`，返回值与表一致，`pt-PT` 匹配到 `pt-BR`，未支持的语言回退到 `zh-Hans`。
- 同日用隔离的 `CFFIXED_USER_HOME` 启动 `dist/Wallnamic.app`，在设置 → 语言中依次选择 English、日本語、简体中文和跟随系统：窗口、设置、状态菜单与应用菜单即时切换，偏好写入正确，辅助功能树只暴露当前设置页。播放器的分布式通知接收端已接入，但未完成“应用内切换后播放器弹窗实时换语言”的双进程验收。

## 实机 UI 验收记录（0.9.4）

2026-10-22 夜间，本机以 `/Applications/Wallnamic.app`（build 23，ad-hoc 签名）分别用 `-AppleLanguages '(en)'` 与 `'(zh-Hans)'` 完成一轮界面验收；两种语言之间完全退出主应用与后台播放器后再启动，避免争用。验收手段为辅助功能树与 Vision OCR，截图仅用于核对，未对外发布，且未保留含账号/路径的图。

已覆盖：

- 主窗口：品牌名、侧栏（我的壁纸、搜索、筛选、排序、创意工坊、设置）、详情区（应用到 / 画面显示 / 声音、视频参数、显示器列表）。
- 设置 sheet：壁纸库与自动播放；性能与电源（桌面完全被遮挡时暂停、电池供电时暂停、低电量模式时暂停）；停止壁纸并完全退出。
- 创意工坊 sheet：下载账号、已登录账号、登录下载账号、选择工具…、浏览工坊…、读取 Steam 订阅…、其他来源、完成。
- 菜单栏状态菜单：管理壁纸…/恢复播放（暂停态）/退出；应用菜单退出与编辑菜单。
- 辅助功能标签：搜索我的壁纸、壁纸排序、重命名壁纸、收藏壁纸、查看壁纸详情。
- 用户壁纸标题、Steam 账号名与显示器硬件名保持原文；内建显示器名走系统本地化。
- 英文与中文词条表键集一致，抽样与界面实测文案一致；视频参数格式为 `W × H · 秒/sec`。

未覆盖（仍不宣称完整英文体验的边界）：

- 空库空状态、导入失败/转码失败弹窗、系统通知、分组重命名等低频弹窗。
- 英文长文案在极端窄窗下的截断，以及全部显示器/电源组合。
- 未做录屏与对外发布截图。

复验命令：

```sh
python3 scripts/check_localization.py
./build.sh
open -n /Applications/Wallnamic.app --args -AppleLanguages '(en)'
# 完全退出后
open -n /Applications/Wallnamic.app --args -AppleLanguages '(zh-Hans)'
```
