# Workavera iOS

Workavera（自托管 AI 工作台）的 iOS 客户端，参考 Web 版的模块与交互结构搭建。

## 技术栈

- **SwiftUI** + **Observation 框架**（`@Observable` / `@Environment`，iOS 17+）
- **async/await** + `URLSession` 直连 PocketBase HTTP API
- **NavigationSplitView**：iPad 显示侧边栏，iPhone 自动折叠为列表导航
- **ContentUnavailableView** 占位页、`AsyncImage` 头像加载
- Token 按服务器隔离存入 **Keychain**，服务器地址存 UserDefaults
- 默认要求 HTTPS；仅回环地址可直接使用 HTTP，局域网 HTTP 需要显式确认风险
- XCTest 覆盖服务器地址校验、网络错误解析、偏好请求与会话恢复
- Xcode 16 工程格式（文件夹同步 group，新增文件无需改工程配置）

## 目录结构

```
Workavera/
├── WorkaveraApp.swift        # 入口：会话恢复 → 登录页 / 主界面
├── Models/User.swift         # users 记录模型（含空字段容错解码）
├── Services/
│   ├── PocketBaseClient.swift  # 类型化网络层、用户资料、文件上传与 user_preferences
│   ├── ServerConfiguration.swift # HTTPS / HTTP 安全策略与地址规范化
│   └── Keychain.swift          # 按服务器隔离的 token 安全存储
├── Stores/AuthStore.swift    # 全局认证、会话恢复与用户偏好（@Observable @MainActor）
├── Components/               # AvatarView（真实头像 + 首字母兜底）、StatusBadge
└── Views/
    ├── AppSection.swift      # 十个模块的枚举（菜单、图标、占位文案）
    ├── LoginView.swift       # 真实登录，可配置服务器地址
    ├── RootView.swift        # 侧边栏 + 详情
    ├── DashboardView.swift   # 真实用户问候 + 占位统计卡
    ├── ProfileView.swift     # 资料编辑、头像上传、密码修改与在线状态
    ├── SettingsView.swift    # user_preferences、服务器信息与确认退出
    ├── ServerSettingsSheet.swift # 服务器地址与不安全 HTTP 风险确认
    ├── SessionRecoveryView.swift # 可重试的会话恢复失败页
    └── PlaceholderView.swift # Chat / Board / Docs / Contacts / Calendar / Reading / Notifications 占位
```

## 运行

1. 启动 Workavera 后端（默认 `http://127.0.0.1:8090`）：
   ```bash
   cd ~/Git/Github/workavera && ./workavera serve
   ```
2. 用 Xcode 16+ 打开 `Workavera.xcodeproj`，选 iOS 17+ 模拟器运行。
3. 登录页用你的 Workavera 账号登录（模拟器访问 `127.0.0.1` 即宿主机）。真机调试时优先配置 HTTPS；临时使用 Mac 局域网 HTTP 地址时，需要在「服务器设置」中明确开启不安全 HTTP，并用 `--http=0.0.0.0:8090` 启动后端。

登录成功后：侧边栏头部与 Dashboard、Profile 显示后端真实的头像、姓名、职位、简介与在线状态。Profile 支持编辑资料、上传头像和修改密码；Settings 中的主题与记忆开关由 `user_preferences` 持久化。退出登录前会要求二次确认。

## 测试

在 Xcode 中运行 `Workavera` scheme 的测试，或执行：

```bash
xcodebuild test \
  -project Workavera.xcodeproj \
  -scheme Workavera \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
