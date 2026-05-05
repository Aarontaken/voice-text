# VoiceText

VoiceText 是轻量 macOS **菜单栏**语音输入工具：通过 **按住 Option（⌥）** 或 **双击 Control** 触发录音，将音频送至 ASR WebSocket 服务，并把识别文本插入 **当前前台应用** 的焦点输入框（含浏览器、编辑器与多数终端）。

## 功能概览

- 菜单栏常驻，适合在任何可输入场景中快速口述。
- **按住 ⌥**：达到约 0.25s 阈值后开始录音，松手结束本轮（短按 Option 不会误触）。
- **双击 Control**：切换「常亮」录音（再双击结束）；与长按 Option 互斥时以长按逻辑为准。
- 识别过程有 **HUD 预览**；最终以增量方式写入目标位置。
- 支持账号登录，持久化 ASR 鉴权相关配置。
- 可调整 **完成停顿**（`silence4StopInMilli`），影响一句结束后的分段时机。

## 下载与安装

预编译包见 **[GitHub Releases](https://github.com/Aarontaken/voice-text/releases)**，下载 zip 后解压，将 `VoiceText.app` 拖入 **应用程序** 文件夹即可。

若系统提示未验证开发者，可在 **系统设置 → 隐私与安全性** 中允许运行，或对 App 右键 **打开** 一次。

从源码自行打包：

```bash
./scripts/build_app_bundle.sh
open build/VoiceText.app
```

产物为已 ad-hoc 签名的 `build/VoiceText.app`，你可再手动拷贝到 `/Applications`。

## 环境要求

- macOS **13** 或更高。
- 开发/运行需 **Swift Package Manager**；跑测试建议使用带 XCTest 的完整 **Xcode**（或等效工具链），版本与当前 Swift 语言模式匹配即可（仓库为 Swift 5.9+）。

首次安装 Xcode 后可执行（按需）：

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

## 本地运行与测试

```bash
swift run VoiceTextApp
```

```bash
swift test
```

## 配置说明

首次启动会在 `~/Library/Application Support/VoiceText/settings.json` 写入默认配置。推荐用菜单栏 **设置** 填写账号与高级项。

### 账号登录

- `environment`：`test` 或 `production`
- `phoneNumber` / `password`：老师账号

登录成功后会保存 `userId`、`authToken`、`cookieHeader` 等连接 ASR 所需字段。

### 快捷键（实际行为）

与状态栏、「设置」页顶部说明一致：

| 操作 | 作用 |
|------|------|
| 按住 **⌥ Option**（约四分之一秒后） | 开始录音 |
| 松开 Option | 结束本轮 |
| **双击 Control**（短按） | 开始或停止「常亮」连续录音 |

`settings.json` 里仍保留 `hotkeyKeyCode` / `hotkeyModifiers`，用于兼容与设置页展示；**当前版本的录音触发由上述 Modifier 监听实现**，并非旧的单一全局快捷键注册路径。

### 高级 ASR

- **`silence4StopInMilli`**：完成停顿，默认 `500` ms，最小 `200`。数值越小越容易在短停顿处分段；越大越「等说完」但更慢。

内置默认还包括：`useAutoVAD=true`、`silence4TimeoutInMilli=500`、`needNormalization=false`、`needDenoise=true`。

### 配置文件字段（节选）

- `environment`、`userId`、`role`、`deviceId`
- `cookieHeader`、`phoneNumber`、`password`、`authToken`、`additionalHeaders`
- `silence4StopInMilli`、`hotkeyKeyCode`、`hotkeyModifiers`（遗留/展示）

## 文本如何插入目标 App

写入策略大致为：

1. **一般应用**：在满足辅助功能授权时，优先通过 **无障碍 API**（以前台应用的 accessibility 树根查找焦点控件，写入选区或追加 `AXValue`）。
2. **常见终端**：对 Terminal、iTerm2、Warp、Ghostty、Kitty、Alacritty、WezTerm、Hyper、Tabby 等，在前台时会 **直接使用剪贴板 + 合成 ⌘V**，并在完成后 **恢复剪贴板**（减少对其它 App 剪辑历史的破坏）。实现上参考了社区里常见的合成键与延迟做法（例如 [vox-ops](https://github.com/EricGrill/vox-ops) 等项目的剪贴板注入思路）。

若无障碍路径不可用，也会回退到「剪贴板 + ⌘V」。

## 权限

- **麦克风**：录音。
- **辅助功能**：无障碍写入与合成按键（含 ⌘V）。请在 **系统设置 → 隐私与安全性 → 辅助功能** 中勾选 VoiceText。

若其它 App 焦点下 **修饰键无反应**，可检查是否还需在 **输入法监控**（Input Monitoring）中授权（因系统版本而异）。

## 常见问题

### 终端里没有字 / 只响一下

- **Terminal.app**：菜单 **Shell → 安全键盘输入** 若开启，会拦截第三方注入的按键，请 **关闭** 后再试；iTerm2 等如有类似「安全输入」选项也需关闭。
- 确认终端窗口处于 **前台**，且光标在 shell 可编辑行（若在 `vim` 普通模式等，表现会异常）。

### `swift test` 报 `no such module 'XCTest'`

多为 `xcode-select` 指向 Command Line Tools 而非完整 Xcode：

```bash
xcode-select -p
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift test
```

### 保存设置时不想弹麦克风权限

仅保存配置不会访问麦克风；**只有开始录音**时才会请求麦克风授权。

## 仓库

<https://github.com/Aarontaken/voice-text>
