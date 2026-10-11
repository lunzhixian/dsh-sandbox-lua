# dsh-sandbox-lua

[DeepSeek Harness](https://www.deepseek.com/harness/)（`dsh`）的
[Android-DIY-Sandbox](https://github.com/zz6zz666/Android-DIY-Sandbox) 沙盒 Lua 包。

在沙盒容器内一键安装 / 启动 DSH 后端，并在沙盒 App 的内嵌 WebView 中打开界面。

## 背景

DeepSeek Harness 官方桌面端（Windows/macOS）本质上是把 `dsh web`（一个带 token 鉴权的
本地 HTTP 服务）套进 Electron。本包把同一个 `dsh web` 常驻运行在 Android-DIY-Sandbox 的
容器里，再用沙盒 App 的内嵌 WebView 打开它——从而在**无 root**的安卓设备上跑起 DSH。

```
┌───────────────── Android-DIY-Sandbox 宿主 App ─────────────────┐
│                                                                │
│   Lua UI / 按钮               内嵌 WebView                     │
│        │                          ▲                            │
│        ▼                          │ http://127.0.0.1:<port>/    │
│   dsh.lua (host.spawn/exec)       │                            │
│        │                          │                            │
│        ▼                          │                            │
│  ┌─────────────── 容器 (proot) ───┴──────────────┐             │
│  │   dsh web  (agent 后端, 带 token)             │             │
│  │   token bridge (把当前认证 URL 交给 WebView)  │             │
│  └───────────────────────────────────────────────┘             │
└────────────────────────────────────────────────────────────────┘
```

## 目录

```
dsh-sandbox-lua/
├── dsh.lua                  # 核心模块 require("dsh")：install/launch/stop
├── apps/dsh.lua             # 整屏应用（放到 scripts/apps/ 下）
└── DSH_CARD_SNIPPET.lua     # 主页卡片代码片段
```

## 安装

### 方式 A：整屏应用（推荐）

1. 把 `dsh.lua` 放到沙盒**脚本根目录** `scripts/` 下；
2. 把 `apps/dsh.lua` 放到 `scripts/apps/` 下；
3. 在 `main.lua` 的 `DYN_APPS` 列表加一行：
   ```lua
   { label = "DSH", icon = "smart_toy_outlined", path = SCRIPTS .. "/apps/dsh.lua" },
   ```
4. 重载脚本（主页顶栏刷新键，或 `bash agent/sandbox reload`），从「动态」页打开 **DSH**。

### 方式 B：主页卡片

参照 `DSH_CARD_SNIPPET.lua`，把 `local dsh = require("dsh")` 和 `dsh_card` 加进 `main.lua`，
并在 `app.page("home", ...)` 的返回列表里加入 `dsh_card(ctx)`。

## 使用

1. 进 DSH 页，点 **安装后端**（首次需要，终端标签看进度，联网下载 Node24 + dsh，数分钟）；
2. 点 **启动后端**，就绪后自动在内嵌 WebView 打开 DSH 界面；
3. 之后点 **打开界面** 可直接打开。

## 模块 API

| 函数 | 说明 |
| --- | --- |
| `dsh.installed()` | 后端是否已就绪（Node24 + dsh 已装） |
| `dsh.install(reinstall)` | 安装 / 重装后端 |
| `dsh.launch()` | 启动后端 + 打开界面（未装则引导安装） |
| `dsh.stop()` | 停止后端与 token bridge |
| `dsh.running()` | 后端是否在跑 |

## 实现要点（踩坑记录）

- **必须 Node ≥ 24**：`dsh` 用了 `import.meta.main`（Node 24+）与 `util.parseEnv`
  （Node 20.12+）；Ubuntu 自带的 Node 18 会**静默无输出**。
- **用 pnpm 而非 npm**：在 Android 的 f2fs 分区上，Ubuntu 打包的 npm 会 cacache 报错 / 堆损坏。
- **原生插件需手动链接**：`node-addon-require-builtin-linux-arm64-gnu` 不会被 pnpm 自动链接进
  依赖树，安装脚本里做了 symlink。
- **token 轮换**：`dsh web` 的启动 token 每次重启都变（但 cookie 有效 30 天），故用一个本地
  token bridge 把当前认证 URL 交给 WebView，避免写死 token。
- `dsh` 可执行文件依赖 `$PNPM_HOME` 在 PATH 中，启动脚本已处理。

## License

MIT
