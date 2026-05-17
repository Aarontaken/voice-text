# VoiceText

轻量 macOS **菜单栏** 语音输入工具：按住 Option 说话，松开后识别文本自动插入当前输入框。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/Aarontaken/voice-text/main/install.sh | bash
```

或从 [Releases](https://github.com/Aarontaken/voice-text/releases) 下载 zip，解压拖入 `/Applications`。

> 首次打开若提示未验证开发者，右键 App 选择 **打开** 即可。

## 使用

| 操作 | 效果 |
|------|------|
| 按住 **⌥ Option**（0.25s 后触发） | 开始录音 |
| 松开 Option | 结束并识别 |
| 双击 **Control** | 切换连续录音 |

识别过程显示 HUD 预览，结果写入前台应用焦点位置。支持浏览器、编辑器及 Terminal / iTerm2 / Warp / Ghostty / Kitty / Alacritty / WezTerm 等常见终端。

在菜单栏 **设置** 中登录账号，可调整 **完成停顿**（默认 500ms，范围 200~10000ms）控制分段速度。

## 权限

- **麦克风** — 录音必需
- **辅助功能** — 写入文字和模拟粘贴。首次插入时如未授权会自动提示

## 常见问题

**终端里没有文字？** 检查 Terminal 菜单 **Shell → 安全键盘输入** 是否关闭；iTerm2 等其他终端类似选项也需关闭。确保光标在可编辑位置。

**蓝牙耳机切换后录音中断？** 音频路由变更会保护性停止，重新长按 Option 即可继续。

**按住 Option 无反应？** 检查系统设置 → 隐私与安全性 → 辅助功能中是否勾选 VoiceText。部分系统可能还需授权输入监控。

## 开发

macOS 13+，Swift 5.9+。

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
