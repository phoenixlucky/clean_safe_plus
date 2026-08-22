# C盘清理工具

![版本](https://img.shields.io/badge/version-1.5.0-blue) ![平台](https://img.shields.io/badge/platform-Windows-lightgrey) ![许可](https://img.shields.io/badge/license-MIT-green)

Windows C 盘安全清理工具 — 传统批处理命令行脚本。

---

## 📁 项目结构

```
clean_safe_plus/
├── clean_safe_plus.bat   # 命令行版主程序（批处理）
├── README.md             # 本文档
├── CHANGELOG.md          # 版本历史
└── reasonix.toml         # Reasonix agent 配置（与本工具无关）
```

---

## 📟 命令行版

`clean_safe_plus.bat` — 传统批处理脚本。

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
5. **板块三：应用缓存（可选）** — 浏览器 / 微信 / VSCode / NVIDIA
6. **板块四：开发工具缓存（可选）** — pip / npm / conda / \_\_pycache\_\_ / Docker
7. **板块五：系统优化（可选）** — 休眠、服务、网络设置（会改变系统配置，请谨慎选择）
8. **显示清理后空间** — 前后对比

## 🛠️ 排错小节

| 现象 | 可能原因 | 解决 |
|---|---|---|
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
- 如果 C 盘仍然很满，优先检查：
  - `C:\Users\<用户名>\AppData`
  - `C:\ProgramData`
  - `C:\Windows`
  - `System Volume Information`