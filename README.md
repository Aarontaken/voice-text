# VoiceText

VoiceText 是一个轻量 macOS 状态栏语音输入工具。它通过 Control 快捷键启动录音，把音频流发送到 ASR WebSocket 服务，并将识别结果插入当前焦点输入框。

## 功能

- 状态栏常驻，适合在任意输入框里快速语音输入。
- 支持按住 Control 说话，松开结束。
- 支持双击 Control 开始或停止连续录音。
- 支持账号登录并自动保存 ASR 鉴权配置。
- 支持微调“完成停顿”参数，控制说完一句话后多久返回分段结果。
- 识别中展示实时预览，最终结果自动插入当前焦点位置。

## 环境要求

- macOS 13 或更高版本。
- Xcode 16.4 或包含 XCTest 的完整 Xcode 工具链。
- Swift Package Manager。

如果刚安装 Xcode，需要先完成首次初始化：

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

## 运行

```bash
swift run VoiceTextApp
```

打包为 `.app`：

```bash
./scripts/build_app_bundle.sh
open build/VoiceText.app
```

运行测试：

```bash
swift test
```

## 配置

首次启动会在 `~/Library/Application Support/VoiceText/settings.json` 生成配置。推荐从状态栏菜单打开“设置”填写账号和高级选项。

### 账号登录

设置页的“账号登录”区域包含：

- `environment`：`test` 或 `production`
- `phoneNumber`：老师账号手机号
- `password`：老师账号密码

登录成功后会保存 `userId`、`authToken`、`cookieHeader` 等 ASR 连接所需信息。

### 快捷键

当前录音触发方式：

- 按住 Control：开始录音。
- 松开 Control：结束本次录音。
- 双击 Control：开始连续录音，再次双击停止。

配置文件中仍保留 `hotkeyKeyCode` / `hotkeyModifiers` 字段，默认值用于兼容旧配置。

### 高级 ASR 设置

设置页只暴露影响体验最大的参数：

- `silence4StopInMilli`：完成停顿，默认 `500`，最小 `200`，单位毫秒。

这个值越小，识别结果返回越快，但更容易在短暂停顿时提前切断；值越大，等待更稳，但一句话结束后的返回会更慢。

其他 ASR 参数使用应用内默认值：

- `useAutoVAD=true`
- `silence4TimeoutInMilli=500`
- `needNormalization=false`
- `needDenoise=true`

### 配置文件字段

`settings.json` 会包含以下主要字段：

- `environment`：ASR 环境，`test` 或 `production`。
- `userId`：ASR URL query 和 init params 使用的用户 ID。
- `role`：用户角色，`student` 或 `teacher`。
- `deviceId`：传给 ASR init params 的设备 ID。
- `cookieHeader`：ASR 请求使用的 Cookie header。
- `phoneNumber` / `password`：设置页登录信息。
- `authToken` / `additionalHeaders`：登录或刷新 Cookie 后保存的鉴权信息。
- `silence4StopInMilli`：完成停顿配置。

## 权限

VoiceText 需要：

- 麦克风权限：采集语音。
- 辅助功能权限：向当前焦点输入框写入文本。

如果 Accessibility 写入失败，应用会降级为写入剪贴板并模拟 `Cmd+V`。

## 常见问题

### `swift test` 提示 `no such module 'XCTest'`

通常是当前开发者目录指向了 Command Line Tools，而不是完整 Xcode。可以检查：

```bash
xcode-select -p
```

如果不是 `/Applications/Xcode.app/Contents/Developer`，切换后重新运行测试：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift test
```

### 保存设置时不应该触发麦克风权限

保存账号或高级设置只会更新配置。只有实际开始录音时才需要麦克风权限。
