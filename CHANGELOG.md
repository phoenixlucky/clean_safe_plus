# 更新日志

本项目的所有重要变更都会记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 计划
- GUI：抽取重复的清理逻辑为 `Invoke-CleanupDirectory` 函数
- GUI：补齐 `Get-DiskInfo` 空值保护
- GUI：增加"刷新磁盘"按钮，避免依赖轮询
- bat：抽取重复的 `del + rd` 清理模式为子程序
- bat：补充休眠恢复说明（`powercfg /h on`）
- README：补充排错小节与版本号

## [1.5.0] - 2026-06-06

### 变更
- 扩展命令行版为 5 大板块：分析 C 盘 / 安全清理 / 系统优化（关闭休眠、关闭非必要服务、刷新 DNS、TCP 调优等）/ 应用缓存 / 开发工具缓存
- 增加网络优化子项（DoSvc / DiagTrack / 推送、刷新 DNS、重置协议、MTU 优化等）

## [1.4.0] - 2026-05-26

### 新增
- 推出基于 Windows Forms 的图形界面（`clean_safe_gui.ps1`）
- 后台 `Start-Job` + 文件轮询的实时日志/进度方案
- 勾选式清理项 + 全选/取消全选

### 变更
- README 增加 GUI 版说明与界面示意
- 添加 `launch_gui.bat` 启动器（自动提权）

## [1.3.0] - 2026-05-26

### 变更
- 重构 `clean_safe_plus.bat`：补齐 pip/npm/conda/__pycache__/Docker 等开发工具缓存清理
- 统一板块标题与用户提示文案
- 加固工具检测（pip 兼容 `python -m` / `py -m` / `pip` 三种入口）

## [1.2.0] - 2026-04-29

### 变更
- 文档细化清理流程与默认勾选说明

## [1.1.0] - 2026-04-29

### 修复
- 本地化清理提示文案（避免英文乱码）
- 加固工具检测（`where` / `cmd` 调用前的健壮性）

## [1.0.0] - 2026-04-29

### 新增
- 命令行版首版（`clean_safe_plus.bat`）
- 安全清理：临时文件 / Prefetch / 日志 / 缩略图 / Windows 更新缓存 / 回收站
- 板块四：浏览器（Chrome/Edge/Firefox）、应用（微信/VSCode/NVIDIA）缓存
- 板块五：pip / npm / conda / `__pycache__` / Docker

[Unreleased]: https://example.com/compare/v1.5.0...HEAD
[1.5.0]: https://example.com/compare/v1.4.0...v1.5.0
[1.4.0]: https://example.com/compare/v1.3.0...v1.4.0
[1.3.0]: https://example.com/compare/v1.2.0...v1.3.0
[1.2.0]: https://example.com/compare/v1.1.0...v1.2.0
[1.1.0]: https://example.com/compare/v1.0.0...v1.1.0
