# C盘清理工具

![版本](https://img.shields.io/badge/version-1.5.0-blue) ![平台](https://img.shields.io/badge/platform-Windows-lightgrey) ![许可](https://img.shields.io/badge/license-MIT-green)

Windows C 盘安全清理工具，提供两种使用方式：

- 🖥️ **图形界面版** — 双击即用，勾选项目、点按钮即可
- 📟 **命令行版** — 传统批处理，适合无 GUI 环境

---

## 📁 项目结构

```
clean_safe_plus/
├── clean_safe_gui.ps1    # 图形界面主程序（PowerShell + WinForms）
├── clean_safe_plus.bat   # 命令行版主程序（批处理）
├── launch_gui.bat        # GUI 启动器（自动提权）
├── README.md             # 本文档
├── CHANGELOG.md          # 版本历史
└── reasonix.toml         # Reasonix agent 配置（与本工具无关）
```

## 🖥️ 图形界面版（推荐）

基于 Windows Forms 的图形界面，无需记忆命令，勾选 + 点击即可。

### 文件

| 文件 | 说明 |
|---|---|
| `clean_safe_gui.ps1` | 图形界面主程序 |
| `launch_gui.bat` | 双击启动器 |

### 使用方式

**双击 `launch_gui.bat`** 即可运行。会自动：

1. 检测管理员权限 → 不是则弹窗提权
2. 加载界面，显示 C 盘空间
3. 勾选需要的清理项 → 点击「开始清理」

### 界面功能

```
┌──────────────────────────────────────────────────────┐
│  C盘清理工具 · 安全版                                │
├──────────────────────────────────────────────────────┤
│  C:  总容量 237.5 GB | 已用 195.2 GB | 剩余 42.3 GB │
│  ████████████████████████████████░░░░░  (进度条)     │
├──────────────────────────────────────────────────────┤
│  ▸ 系统清理（安全）                                  │
│  ☑ 临时文件         ☑ Prefetch                       │
│  ☑ 更新缓存         ☑ 日志文件                       │
│  ☑ 缩略图缓存       ☑ 回收站                         │
│  ▸ 浏览器缓存                                        │
│  ☐ Chrome            ☐ Edge                          │
│  ☐ Firefox                                           │
│  ▸ 应用缓存                                          │
│  ☐ 微信              ☐ VSCode                        │
│  ☐ NVIDIA                                            │
│  ▸ 开发缓存                                          │
│  ☐ pip               ☐ npm                           │
│  ☐ conda             ☐ __pycache__                    │
│  ☐ Docker                                            │
│  ▸ 其他                                              │
│  ☐ 关闭休眠          ☐ 分析 C 盘大目录               │
├──────────────────────────────────────────────────────┤
│  [▶ 开始清理] [⏹ 取消] [☑ 全选] [☐ 取消全选]       │
│  ████████████████████░░░░░░  60%  Docker OK           │
├──────────────────────────────────────────────────────┤
│  [14:32:05] ▶ 开始清理临时文件...                    │
│  [14:32:06] ✓ 用户 Temp 清理完成                     │
│  [14:32:10] ✅ 清理完成！释放 24.25 GB               │
│  ━━━━━ 清理前后对比 ━━━━━                            │
│  清理前剩余: 20.87 GB                                │
│  清理后剩余: 45.12 GB                                │
│  释放空间:   24.25 GB                                │
└──────────────────────────────────────────────────────┘
```

### 清理项详解

| 项目 | 默认 | 说明 |
|---|---|---|
| **▸ 系统清理（安全）** | | |
| 临时文件 | ✅ 开启 | Temp / AppData Temp / Windows Temp，安全可删 |
| Prefetch | ✅ 开启 | 清理后自动重建，安全 |
| Windows 更新缓存 | ✅ 开启 | 需重启 Windows Update 服务 |
| 日志文件 | ✅ 开启 | Windows Logs + WER 错误报告 |
| 缩略图缓存 | ✅ 开启 | `thumbcache_*.db` 安全可删 |
| 回收站 | ✅ 开启 | `C:\$Recycle.Bin` |
| **▸ 浏览器缓存** | | |
| Chrome | ❌ 关闭 | `Chrome\User Data\Default\Cache` |
| Edge | ❌ 关闭 | `Edge\User Data\Default\Cache` |
| Firefox | ❌ 关闭 | `Mozilla\Firefox\Profiles\*\cache2` |
| **▸ 应用缓存** | | |
| 微信缓存 | ❌ 关闭 | 聊天图片/视频（可能超 10GB） |
| VSCode 缓存 | ❌ 关闭 | Code\Cache + Code\CachedData |
| NVIDIA 缓存 | ❌ 关闭 | Downloader + Installer2 目录 |
| **▸ 开发缓存** | | |
| pip | ❌ 关闭 | `pip cache purge` |
| npm | ❌ 关闭 | `npm-cache` 目录 |
| conda | ❌ 关闭 | `conda clean --all -y` |
| `__pycache__` | ❌ 关闭 | Python 字节码缓存 |
| Docker | ❌ 关闭 | `docker system prune -a` |
| **▸ 其他** | | |
| 关闭休眠 | ❌ 关闭 | 删除 hiberfil.sys，释放数 GB |
| 分析 C:\ 大目录 | ❌ 关闭 | 扫描 C 盘最大的 12 个目录（较慢） |

> 清理完成后，日志中会自动显示 **清理前后对比** 和释放的空间大小。

---

## 📟 命令行版（原批处理）

`clean_safe_plus.bat` — 传统批处理脚本，适合无 GUI 环境或远程会话。

### 使用方式

双击运行 `clean_safe_plus.bat`，自动请求管理员权限。

或从管理员命令提示符运行：

```bat
clean_safe_plus.bat
```

### 执行流程

1. **管理员权限检查** — 自动提权
2. **显示 C 盘空间** — PowerShell 查询容量 / 剩余
3. **板块一：分析 C 盘大目录（可选）** — 递归统计最大 12 个目录
4. **板块二：安全清理（自动）** — 临时文件 / Prefetch / 日志 / 缩略图 / 更新缓存 / 回收站
5. **板块三：系统优化（可选）**
   - 3.1 关闭休眠 — 删除 hiberfil.sys
   - 3.2 系统服务与性能优化 — 禁用 Xbox 等非必需服务、关闭透明效果、禁用 OneDrive 自启
   - 3.3 网络优化 — 关闭后台网络服务(DoSvc/DiagTrack/推送)、刷新 DNS、重置协议、TCP 参数调优、网卡省电关闭、MTU 优化
6. **板块四：应用缓存清理（可选）** — 浏览器 / 微信 / VSCode / NVIDIA
7. **板块五：开发工具缓存（可选）** — pip / npm / conda / \_\_pycache\_\_ / Docker
8. **显示清理后空间** — 前后对比

## 🛠️ 排错小节

| 现象 | 可能原因 | 解决 |
|---|---|---|
| GUI 启动后白屏/不显示 | PowerShell 5.1 缺少 Windows Forms 组件 | 用 `winrm quickconfig` 或重装 .NET Framework 4.8+ |
| 启动时报"无法加载文件…未数字签名" | 执行策略限制 | 在管理员 PowerShell 执行 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| 清理 Temp 时部分文件占用 | 文件被其他程序持有 | 关闭浏览器/微信/VSCode 等再重试 |
| Windows Update 清理后服务未启动 | 某些场景下 wuauserv 不会自动起 | 手动 `net start wuauserv` |
| `docker system prune` 删除正在用的容器 | 容器仍在运行 | 先 `docker stop $(docker ps -aq)` 再清理 |
| 清理后 C 盘空间没明显变化 | 占用来自 `C:\Users\<用户>\AppData` / `C:\Windows\WinSxS` 等深层 | 勾选"分析 C 盘大目录"定位 |

更详细的问题排查与历史变更见 [CHANGELOG.md](./CHANGELOG.md)。

---

## ⚠️ 重要提示

- 建议在 **中文 Windows** 上运行
- 需要 **管理员权限**（清理系统目录、回收站等必须）
- 批处理文件（`.bat`）保持 **GBK/ANSI** 编码，不要改成 UTF-8
- 图形界面版本（`.ps1`）自动处理编码，双击启动器即可
- 如果 C 盘仍然很满，优先检查：
  - `C:\Users\<用户名>\AppData`
  - `C:\ProgramData`
  - `C:\Windows`
  - `System Volume Information`
