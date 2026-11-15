# VoiceText

轻量 macOS **菜单栏** 语音输入工具：按住 Option 说话，松开后由 **豆包流式语音识别（一句话识别）** 返回整句结果，并自动插入当前输入框。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/Aarontaken/voice-text/main/install.sh | bash
```

或从 [Releases](https://github.com/Aarontaken/voice-text/releases) 下载 zip，解压拖入 `/Applications`。

> 首次打开若提示未验证开发者，右键 App 选择 **打开** 即可。

## 首次配置

1. 在[火山引擎控制台](https://console.volcengine.com/speech/new/overview)开通「豆包流式语音识别」，并获取 **API Key**（控制台 → 豆包语音 → API Key 管理）。
2. 打开菜单栏 VoiceText → **设置**，填写 API Key。
3. 选择与控制台已开通资源一致的 **模型版本**（默认「2.0 小时版」），保存。

> 豆包按音频时长计费，使用前请确认账号已开通对应资源。

## 使用

| 操作 | 效果 |
|------|------|
| 按住 **⌥ Option**（0.25s 后触发） | 开始录音 |
| 松开 Option | 结束录音；按设置里的识别方式返回结果并写入输入框 |
| 双击 **Control** | 切换连续录音 |

识别过程显示 HUD 预览，结果写入前台应用焦点位置。支持浏览器、编辑器及 Terminal / iTerm2 / Warp / Ghostty / Kitty / Alacritty / WezTerm 等常见终端。

设置里的 **识别方式**：

- **一句话识别**（默认）：松手后返回整句，准确率更高
- **实时识别**：边说边出字，按分句立即插入；适合长句或连续口述

设置里可调整 **完成停顿**（VAD 静音判停阈值，默认 800ms，范围 300–5000ms）：调小返回更快但更容易提前切断，调大更稳但等待更久。

## 权限

- **麦克风** — 录音必需
- **辅助功能** — 写入文字和模拟粘贴。首次插入时如未授权会自动提示

## 常见问题

**终端里没有文字？** 检查 Terminal 菜单 **Shell → 安全键盘输入** 是否关闭；iTerm2 等其他终端类似选项也需关闭。确保光标在可编辑位置。

**蓝牙耳机切换后录音中断？** 音频路由变更会保护性停止，重新长按 Option 即可继续。

**按住 Option 无反应？** 检查系统设置 → 隐私与安全性 → 辅助功能中是否勾选 VoiceText。部分系统可能还需授权输入监控。

**提示需要 API Key / 服务返回鉴权错误？** 到设置里检查 API Key 是否填写正确，以及「模型版本」是否与控制台开通的资源一致。

**松手后一直没出字？** 查看 `/tmp/voicetext.log` 里的连接与响应日志；常见原因是网络不可达、API Key 失效或资源未开通。

## 开发

macOS 13+，Swift 5.9+，无第三方依赖。

```bash
# 运行
swift run VoiceTextApp

# 测试
swift test

# 打包
./scripts/build_app_bundle.sh
```

推送 `v*` 标签触发 GitHub Actions 自动构建发布。

## 仓库

<https://github.com/Aarontaken/voice-text>
