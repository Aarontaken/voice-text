# VoiceText

VoiceText 是一个轻量 macOS 状态栏语音输入工具。它通过全局快捷键启动录音，把音频流发送到公司 ASR WebSocket 服务，并将识别结果插入当前焦点输入框。

## 运行

```bash
swift run VoiceTextApp
```

打包为 `.app`：

```bash
./scripts/build_app_bundle.sh
open build/VoiceText.app
```

## 配置

首次启动会在 `~/Library/Application Support/VoiceText/settings.json` 生成配置。也可以从状态栏菜单打开“设置”填写：

- `environment`：`test` 或 `production`
- `userId`：ASR URL query 和 init params 使用的用户 ID
- `role`：`student` 或 `teacher`，首版仅保存，后续自动取 Cookie 时使用
- `deviceId`：传给 ASR init params 的设备 ID
- `cookieHeader`：手动复制的 Cookie header，例如 `sid=abc; uid=123`
- `hotkeyKeyCode` / `hotkeyModifiers`：默认 `Option + Space`

## 权限

VoiceText 需要：

- 麦克风权限：采集语音。
- 辅助功能权限：向当前焦点输入框写入文本。

如果 Accessibility 写入失败，应用会降级为写入剪贴板并模拟 `Cmd+V`。
