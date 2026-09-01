# Clean Safe Plus

一个面向 Windows 的 C 盘安全清理桌面客户端，使用 Tauri 2.11+、Vue 3.5.x 和 Rust 构建。

## 功能

- 扫描 C 盘可用空间和明确可重建的缓存、临时文件、日志
- 默认全选安全项目，保留桌面、下载、文档、浏览器登录信息和书签
- 预览待清理空间，再由用户确认执行
- 支持 Chrome、Edge、Firefox、微信、VSCode、NVIDIA/AMD 和开发工具缓存
- 支持 pip、npm、conda、Python `__pycache__` 与 Docker 未使用资源清理
- 支持 Claude、Cursor、Windsurf、Trae、Kiro、ChatGPT、LM Studio 等 AI 客户端的可重建缓存和日志清理
- 支持关闭休眠、服务优化、网络/VPN/TUN 修复、页面文件设置
- 支持 C 盘大目录分析、DISM 组件清理和卷影副本空间限制
- 可选删除 Hermes 整个本地数据目录（需要单独勾选）
- 可选调用 Windows 自带磁盘清理
- 正在使用或受保护的文件自动跳过，不强制结束进程

## 开发

环境要求：Node.js、Rust、Windows WebView2，以及 Tauri 所需的 Windows C++ 构建工具。

```powershell
npm install
npm run dev
```

启动 Tauri 开发窗口：

```powershell
npm run tauri dev
```

构建前端：

```powershell
npm run build
```

构建 Windows 可执行文件：

```powershell
node_modules\.bin\tauri.cmd build --no-bundle
```

也可以直接双击根目录的 `build.bat` 一键安装依赖并构建便携式 EXE。最终文件为 `releases\CleanSafePlus.exe`，无需安装即可运行（目标电脑仍需 WebView2 运行环境）。

系统服务、网络、休眠、页面文件、DISM 和卷影副本等高级操作会在执行时请求管理员权限并显示确认提示。发布版 EXE 使用 Windows GUI 子系统，不会额外弹出黑色命令窗口。

## 清理后端

清理逻辑位于 `src-tauri/src/main.rs`，前端通过 Tauri command 调用：

- `scan_cleanup`：返回可用空间和白名单清理项目
- `clean_targets`：仅按白名单 ID 执行清理
- `run_maintenance`：执行应用缓存、系统维护和网络修复操作
- `set_pagefile`：设置系统自动、自定义或关闭页面文件
- `analyze_disk`：递归列出 C 盘中达到 1GB 的文件夹，子文件夹低于 1GB 时停止展开

独立的 `cleanup_c_drive.ps1` 仍保留作为无界面备用工具。它默认只预览：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\cleanup_c_drive.ps1
```

确认执行缓存清理：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\cleanup_c_drive.ps1 -Apply
```

删除 Hermes 整个本地数据目录时，显式追加 `-RemoveHermes`。运行 Windows 自带清理时，追加 `-RunWindowsCleanup`。

## 项目结构

```text
clean_safe_plus/
├── src/                         # Vue 3 界面
├── src-tauri/                   # Tauri 配置和 Rust 清理后端
├── cleanup_c_drive.ps1          # 独立 PowerShell 备用工具
├── package.json                 # 前端和 Tauri CLI 依赖
└── vite.config.js               # Vite 配置
```

## 安全边界

客户端不接受前端传入的任意路径，只能清理 Rust 后端内置白名单中的目录。AI 清理只包含可重建的缓存、扩展下载缓存和日志，不删除对话记录、配置、模型文件或项目文件。Fincept 虚拟环境、Visual Studio 安装缓存、Codex 运行组件等应用数据也不会被默认清理，避免误伤开发环境或已安装程序。
