# 更新日志

本项目的所有重要变更都会记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 新增
- 命令行版新增「设置虚拟内存（页面文件）」子项：支持系统自动管理 / 自定义大小（可选盘符）/ 无分页文件，修改后需重启生效
- 重构为两级菜单：先选择「清理类 / 设置类 / 分析类」，再选择具体子项，执行后返回菜单可继续操作
- 新增「AI 工作缓存」清理：覆盖 Claude、Cursor、Windsurf、Trae、Kiro、ChatGPT、LM Studio 等客户端的可重建缓存、扩展下载缓存和日志；不处理对话、配置、模型或项目文件
- 新增「打包构建垃圾」清理：清理 `build.bat` 生成的 `dist`、Vite 缓存和 Tauri 中间产物，保留 `releases\CleanSafePlus.exe`
- 磁盘分析新增两次扫描对比及 JSON 导入/导出，可按文件夹查看空间增减

### 修复
- 修复 `__pycache__` 清理空间统计异常：现在只删除 `.pyc/.pyo`，并仅按成功删除的文件大小计入释放空间，避免显示不可信的超大数值
- 虚拟内存自定义大小：创建分页文件时 `InitialSize`/`MaximumSize` 必须以 `uint32` 类型写入（`Win32_PageFileSetting` 的 CIM 类型为 UInt32），否则 `New-CimInstance` 报「属性"InitialSize"的类型不匹配」且仍误报成功；设置失败时改为提示失败而非「已设置」
- 微信缓存清理「未找到缓存目录」：新增读取微信 3.x 注册表自定义保存路径（`HKCU\Software\Tencent\WeChat\FileSavePath`），并支持微信 4.x 新目录结构（`xwechat_files\<wxid>_*\msg\attach|file|image|video`，无 `FileStorage`）；命令行版找不到缓存时可直接输入缓存目录路径

### 移除
- 移除图形界面版（`clean_safe_gui.ps1`、`launch_gui.bat`），只保留命令行版 `clean_safe_plus.bat`

### 计划
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
