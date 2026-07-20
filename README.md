# Workavera iOS

Workavera（自托管 AI 工作台）的 iOS 客户端，参考 Web 版的模块与交互结构搭建。

## 技术栈

- **SwiftUI** + **Observation 框架**（`@Observable` / `@Environment`，iOS 17+）
- **async/await** + `URLSession` 直连 PocketBase HTTP API
- **NavigationSplitView**：iPad 显示侧边栏，iPhone 自动折叠为列表导航
- **ContentUnavailableView** 占位页、`AsyncImage` 头像加载
- Token 存 **Keychain**，服务器地址存 UserDefaults
- Xcode 16 工程格式（文件夹同步 group，新增文件无需改工程配置）

## 目录结构

```
Workavera/
├── WorkaveraApp.swift        # 入口：会话恢复 → 登录页 / 主界面
├── Models/User.swift         # users 记录模型（含空字段容错解码）
├── Services/
│   ├── PocketBaseClient.swift  # auth-with-password / auth-refresh / 更新记录 / 文件 URL
│   └── Keychain.swift          # token 安全存储
├── Stores/AuthStore.swift    # 全局认证状态（@Observable @MainActor）
├── Components/               # AvatarView（真实头像 + 首字母兜底）、StatusBadge
└── Views/
    ├── AppSection.swift      # 十个模块的枚举（菜单、图标、占位文案）
    ├── LoginView.swift       # 真实登录，可配置服务器地址
    ├── RootView.swift        # 侧边栏 + 详情
    ├── DashboardView.swift   # 真实用户问候 + 占位统计卡
    ├── ProfileView.swift     # 真实资料展示，在线状态可切换并写回后端
    ├── SettingsView.swift    # 服务器信息 / 退出登录
    └── PlaceholderView.swift # Chat / Board / Docs / Contacts / Calendar / Reading / Notifications 占位
```

## 运行

1. 启动 Workavera 后端（默认 `http://127.0.0.1:8090`）：
   ```bash
   cd ~/Git/Github/workavera && ./workavera serve
   ```
2. 用 Xcode 16+ 打开 `Workavera.xcodeproj`，选 iOS 17+ 模拟器运行。
3. 登录页用你的 Workavera 账号登录（模拟器访问 `127.0.0.1` 即宿主机）。真机调试时在登录页「服务器设置」里改成 Mac 的局域网地址，并用 `--http=0.0.0.0:8090` 启动后端。

登录成功后：侧边栏头部与 Dashboard、Profile 显示后端真实的头像、姓名、职位、简介与在线状态；在 Profile 切换状态会实时 PATCH 回 PocketBase。
