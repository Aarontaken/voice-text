# VoiceText

VoiceText 是轻量 macOS **菜单栏** 语音输入工具：通过 **按住 Option（⌥）** 触发录音，将音频送至 ASR WebSocket 服务，并把识别文本插入 **当前前台应用** 的焦点输入框（浏览器、编辑器与常见终端）。

## 功能概览

- 菜单栏常驻，适合在任何可输入场景中快速口述。
- **按住 ⌥**：达 0.25s 阈值后开始录音，松手结束本轮（短按不会误触）。
- **双击 Control**：切换「常亮」连续录音（再双击停止）；与长按 Option 互斥时长按优先。
- 识别过程有 **HUD 预览**，最终以增量方式写入目标位置。
- 账号登录后持久化 ASR 鉴权信息。
- 可调整 **完成停顿**（`silence4StopInMilli`），影响一句结束后的分段时机。

## 下载与安装

预编译包见 **[GitHub Releases](https://github.com/Aarontaken/voice-text/releases)**，下载 zip 后解压，将 `VoiceText.app` 拖入 **应用程序** 文件夹。

若系统提示未验证开发者，可在 **系统设置 → 隐私与安全性** 中允许运行，或对 App 右键 **打开** 一次。

从源码构建：

```bash
./scripts/build_app_bundle.sh
open build/VoiceText.app
```

产物为 ad-hoc 签名的 `build/VoiceText.app`，可手动拷贝到 `/Applications`。

## 环境要求

- macOS **13** 或更高。
- 开发/运行需 **Swift Package Manager**；跑测试建议使用带 XCTest 的完整 **Xcode**（或等效工具链），版本与当前 Swift 语言模式匹配即可（仓库为 Swift 5.9+）。

## 本地运行与测试

```bash
swift run VoiceTextApp
```

```bash
swift test
```

## 配置

所有配置通过菜单栏 **设置** 面板完成，无需手动编辑文件。

### 账号登录

填写 `test` 或 `production` 环境、手机号、密码，点击 **登录并保存**。

### 快捷键

| 操作 | 作用 |
|------|------|
| 按住 **⌥ Option**（约 0.25s 后） | 开始录音 |
| 松开 Option | 结束本轮 |
| 双击 **Control** | 切换「常亮」连续录音 |

### 高级

仅一项可调：**完成停顿**（默认 500ms，范围 200~10000ms）。越小越容易在短停顿处分段，越大越「等说完」但响应更慢。

## 文本插入策略

1. **终端模拟器**：Terminal、iTerm2、Warp、Ghostty、Kitty、Alacritty、WezTerm、Hyper、Tabby 在前台时，直接走剪贴板 + 合成 `⌘V`，完成后恢复剪贴板原有内容。
2. **一般应用**：辅助功能授权后，以前台 App 的 accessibility 树查找焦点元素，优先通过写入选区或追加 `AXValue` 插入。
3. **回退**：无障碍路径不可用时，回退到剪贴板 + `⌘V`。

## 权限

- **麦克风**：录音时需要。
- **辅助功能**：无障碍写入与合成快捷键（`⌘V`）。首次尝试插入文字时若未授权会自动弹窗提示，也可在菜单栏手动授权。

如需在 **系统设置 → 隐私与安全性 → 辅助功能** 中勾选 VoiceText。部分系统版本可能还需在 **输入监控**（Input Monitoring）中授权。

## 常见问题

### 终端里没有文字 / 只响一声

- **Terminal.app**：菜单 **Shell → 安全键盘输入** 若开启会拦截第三方按键注入，请关闭后再试。iTerm2 等类似「安全输入」选项也需关闭。
- 确认终端窗口在前台，且光标位于可编辑行（vim 普通模式等场景表现会异常）。

### 蓝牙耳机切换后录音中断

连接或断开蓝牙耳机时，系统音频路由变更可能导致录音自动停止并提示重新开始。这是正常的硬件路由保护行为，重新长按 Option 即可继续。

### `swift test` 报 `no such module 'XCTest'`

多为 `xcode-select` 指向 Command Line Tools 而非完整 Xcode：

```bash
xcode-select -p
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift test
```

### 保存设置时不想弹麦克风权限

仅保存配置不会访问麦克风，**只有开始录音**时才会请求授权。

## 仓库

<https://github.com/Aarontaken/voice-text>
