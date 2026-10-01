# Always Yes

> 拍一下 Mac，自动按回车。专为 Claude Code、Cursor、Windsurf 等 AI 编程助手打造。

**English summary:** Always Yes is an open-source macOS utility for AI-native coding workflows. On supported Apple Silicon Macs, a light tap on the MacBook body can send Enter to tools such as Codex, Claude Code, Cursor, Windsurf, VS Code, and terminal apps. It runs locally, does not upload data, and is designed to reduce repetitive confirmation friction during supervised AI coding.

当 AI 第八十次问你「Run this command? (y/N)」时，你的手早就抬起来了。**Always Yes** 通过 Apple Silicon 内置的加速度计感应你拍击 Mac 的动作，自动按下回车键。

```
   ✋        💢          ⏎
 (拍一下) → (感应到) → (按回车)
```

📺 **功能介绍视频**：[【AI能有什么坏心思呢？只是需要鼓励罢了】](https://b23.tv/g2LBNHR)（B 站）

---

## 它能做什么

- ✅ 拍一下 Mac 机身 → 自动按回车
- ✅ 默认只在终端 / VS Code / Cursor / Zed 等 AI 编程场景里触发，不会误伤聊天和文档
- ✅ 灵敏度可调（轻拍 → 重击 → 愤怒砸桌）
- ✅ 一键暂停 / 切换「所有应用」/「只在 AI 编程应用」
- ✅ 完全本地运行，不联网，不上传任何数据

---

## 硬件要求

**只能在带有 BMI286 加速度计的 Apple Silicon Mac 上工作**：

| 芯片 | 是否支持 |
|---|---|
| M2 / M2 Pro / M2 Max / M2 Ultra | ✅ |
| M3 / M4 / M5（全系列） | ✅ |
| M1 Pro / M1 Max | ✅ |
| **M1 / M1 Air** | ❌（这一代没有 IMU） |
| Intel Mac | ❌ |

打开 app 时会自动检测，如果你的 Mac 不支持，菜单栏会显示状态。

---

## 安装

### 方式 1：下载预编译版（推荐）

1. 到 [Releases](../../releases) 下载最新的 `Always Yes.app.zip`
2. 解压后把 `Always Yes.app` 拖到 `/Applications/`
3. 因为是 ad-hoc 签名，第一次打开时 macOS 会拦截，需要执行：
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Always Yes.app"
   ```
4. 双击 `Always Yes.app` 启动

### 方式 2：自己编译（需要 Swift 工具链）

```bash
git clone https://github.com/359392475-blue-sky/always-yes.git
cd always-yes/app
./Bundle/build-app.sh
cp -r build/Always\ Yes.app /Applications/
```

要求：macOS 13+，Swift 5.9+（系统自带 Xcode Command Line Tools 即可，无需 Xcode.app）。

---

## 第一次启动

启动后，状态栏顶部会出现一个 ✋ 图标。然后会依次弹出两个权限请求：

### 1️⃣ 守护进程安装（输入 Mac 开机密码）

为了读取传感器，Always Yes 需要安装一个后台守护进程。这是**一次性**的，输入一次密码后永久生效，重启 Mac 也不需要再输。

### 2️⃣ 辅助功能权限（点一下开关）

为了能模拟按下回车键，需要在「系统设置 → 隐私与安全性 → 辅助功能」里给 Always Yes 打勾。

> **小贴士**：如果第一次没弹出，点状态栏的 ✋ 图标，菜单里会有「辅助功能：未授权（点此申请）」选项，点一下即可。

---

## 怎么用

### 拍哪里？

拍 MacBook 的**外壳左右两侧**或**键盘下方机身**（不要砸屏幕）。轻拍即可，不需要使劲。

如果触发不灵，把灵敏度往「轻拍 Mac」那一侧拉；如果误触发，往「重击」侧拉。

### 状态栏菜单

点状态栏的 ✋ 图标，会看到：

```
┌──────────────────────────────────┐
│ 🎚️ 灵敏度  [轻拍 Mac ──●── 愤怒砸桌] │
├──────────────────────────────────┤
│ 暂停                              │
├──────────────────────────────────┤
│ 应用范围  ▶  ✓ 所有 AI 编程应用    │
│              所有应用              │
├──────────────────────────────────┤
│ 守护进程：已启用                   │
│ 辅助功能：已授权                   │
├──────────────────────────────────┤
│ 退出 Always Yes                   │
└──────────────────────────────────┘
```

### 默认 AI 编程应用白名单

开箱即用支持以下应用（前台是它们时才会触发）：

- **运行 AI 命令的终端**：Terminal、iTerm2、Ghostty、Warp、kitty、Alacritty、Hyper、Tabby、WezTerm
- **AI 编程 IDE / 编辑器**：Cursor、Windsurf、Zed、VS Code、Xcode

如果你想在浏览器、聊天软件等任何应用里都能用，切到「所有应用」即可。

---

## 常见问题

**Q: 拍了没反应？**
A: 检查菜单里「辅助功能」是否「已授权」。如果状态是「未授权」，点击它，在系统设置里打勾后重启 app。

**Q: 误触太多怎么办？**
A: 把灵敏度滑块往「重击」方向拉。默认 0.144 适合轻拍，0.25+ 需要明显的拍击力度。

**Q: 重启 Mac 后还要重装吗？**
A: 不用。守护进程会随系统启动。Always Yes 菜单栏 app 也可以加到「登录项」里自动启动。

**Q: 会不会偷传我的数据？**
A: 不会。完整源码开源，所有处理都在本地。守护进程只读加速度计，菜单栏 app 只发送回车键，没有任何网络请求。

**Q: 为什么需要管理员密码？**
A: 因为 IMU 传感器属于内核级硬件接口，必须由根权限的守护进程读取。这是 macOS 的硬性要求，不是我们想这样做。

**Q: 日志会不会越占越多？**
A: 不会。守护进程的输出全部丢弃到 `/dev/null`，只通过 macOS 的 unified logging 输出，由系统自动轮转。

---

## 项目结构

```
always-yes/
├── app/                          ← Phase 2: Swift 菜单栏 app（主要产品）
│   ├── Package.swift
│   ├── Sources/
│   │   ├── SlapToYes/            菜单栏 app（用户态）
│   │   ├── SlapDaemon/           守护进程（root，读传感器）
│   │   └── SharedTypes/          XPC 协议 / 共享数据类型
│   └── Bundle/
│       ├── build-app.sh          一键打包脚本
│       ├── Info.plist
│       ├── ai.slaptoyes.daemon.plist
│       └── AppIcon.icns
└── (根目录)                       ← Phase 1: Go CLI 参考实现
    ├── main.go, detect.go, ...   早期验证版本，命令行 + sudo
    └── config.example.toml
```

### 架构

```
┌─────────────────────────────┐  XPC  ┌──────────────────────────┐
│ Always Yes.app（菜单栏）     │ ◄───► │ slap-daemon（root 后台） │
│                             │       │                          │
│ • 状态栏 UI                  │       │ • 读 BMI286 IMU（1kHz）   │
│ • 灵敏度 / 暂停 / 应用范围    │       │ • 高通滤波 + 阈值检测     │
│ • 收到 slap 后判断前台 app    │       │ • 检测到拍击 → XPC 推送   │
│ • 模拟按下 Enter（CGEvent）   │       │                          │
└─────────────────────────────┘       └──────────────────────────┘
```

把检测逻辑（要 root）和按键逻辑（要辅助功能权限、要 GUI session）分到两个进程，是 macOS 沙盒模型的最佳实践。

---

## 路线图

- [x] **v0.1**：Go CLI 验证，命令行 + sudo（保留为参考）
- [x] **v0.2**：Swift 菜单栏 app，端到端可用
- [ ] **v0.3**：拍击力度反馈（轻拍 / 重击区分），登录项一键开启
- [ ] **v0.4**：完整 6 路检测器算法（STA/LTA + CUSUM + 峰度），减少误触
- [ ] **v0.5**：申请 Developer ID，正式签名 + Notarize，去掉手动 quarantine 步骤

---

## 致谢

- IMU 读取借鉴了 [`taigrr/apple-silicon-accelerometer`](https://github.com/taigrr/apple-silicon-accelerometer)（MIT），其本身是 [`olvvier/apple-silicon-accelerometer`](https://github.com/olvvier/apple-silicon-accelerometer) 研究项目的 Go 移植
- 创意起源：[`taigrr/spank`](https://github.com/taigrr/spank)（拍一下笔记本它会喊「ow!」），我们只是把动作改成了按回车
- 灵感来源：每天被 AI 问「Run this command?」无数次的疲惫

---

## License

[MIT](LICENSE) © 2026 Wang Junjie

---

> 如果你觉得这个项目有意思，欢迎点个 ⭐️ 或者拍一下你的 Mac 表示支持（误）。
