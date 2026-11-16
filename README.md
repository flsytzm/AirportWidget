# 机场流量 · iOS 原生 App + 桌面小组件

原生 SwiftUI 应用，附带一个中号（systemMedium）桌面小组件。测速用 `NWConnection` 发起裸 TCP 连接并对 `ready` 状态计时，**不发 HTTP、不做 TLS、DNS 不计入**，与 PassWall2 首页 / 小火箭节点延迟是同一个物理动作。

## 目录结构

```
AirportWidget/
├── project.yml                      XcodeGen 工程描述
├── Sources/
│   ├── Shared/Net.swift             订阅请求、流量头解析、节点解析、TCP 测速
│   ├── App/SettingsView.swift       设置页（SwiftUI）
│   └── Widget/FlowWidget.swift      WidgetKit 小组件
└── .github/workflows/build.yml      GitHub Actions 自动出 ipa
```

## 功能

- 读取订阅响应头 `subscription-userinfo`，得到总量 / 已用 / 剩余 / 到期
- 从订阅正文解析 `server` + `port`，自动对第一个节点做 TCP 握手计时
- 也可手动指定节点地址和端口
- 小组件显示：机场名、可用百分比、剩余流量（>=50% 绿 / 20–50% 橙 / <20% 红）、进度条、已用/总量+到期、延迟毫秒
- 延迟配色：<300 绿 / <600 橙 / 其余红
- 数据通过 App Group（`group.com.example.airportwidget`）在 App 和小组件间共享

## 安装（三选一）

### 路径 A：有 Mac

1. `brew install xcodegen`
2. 在本目录执行 `xcodegen generate`
3. 打开 `AirportWidget.xcodeproj`
4. Xcode → Signing & Capabilities → Team 选择你的 Apple ID（免费账号即可）
5. 如果 bundle id 冲突，把 `project.yml` 里的 `com.example.airportwidget` 改成你自己的，重新 generate
6. 手机连上电脑，选真机运行

> 免费 Apple ID 签名的 App **7 天后过期**，到期重跑一次即可。付费开发者账号（99 美元/年）为一年。

### 路径 B：只有 Windows

1. 把整个 `AirportWidget` 目录推到你的 GitHub 仓库
2. 进入仓库 Actions 页，选 `Build IPA`，点 `Run workflow`
3. 等 5–8 分钟，下载 artifact `AirportWidget-ipa`，解压得到 `AirportWidget.ipa`
4. Windows 上装 [Sideloadly](https://sideloadly.io/)
5. iPhone 用数据线连电脑，Sideloadly 里填入 ipa、输入你的 Apple ID，点 Start
6. 手机上「设置 → 通用 → VPN与设备管理」信任你的开发者证书
7. App 需要开启「开发者模式」：设置 → 隐私与安全性 → 开发者模式 → 打开并重启

> 同样受 7 天签名限制。

### 路径 C：想永久有效

买一个 Apple Developer Program（99 美元/年），用你的 Team 签名，一年内不用重签，且可给朋友装。

## 注意

- App 首次打开必须填订阅链接，否则小组件显示「读取失败」
- 若订阅返回的是 base64 编码的 v2ray 节点列表（而非 Clash YAML），节点解析会失败，此时改用「手动指定节点」填节点地址和端口
- 组件的刷新频率受 iOS 限制，实际最快约 15 分钟一次，`刷新间隔` 只是期望值
- 机场 token 请勿外泄，建议在机场后台重置订阅后再填进 App
