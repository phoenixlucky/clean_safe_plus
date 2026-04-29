# C盘清理工具

`clean_safe_plus.bat` 是一个 Windows 批处理脚本，用于分析 C 盘一级目录占用，并在确认后执行相对安全的清理操作。

## 使用方式

推荐直接双击运行 `clean_safe_plus.bat`。脚本会自动请求管理员权限，请在弹出的 UAC 窗口中点击“是”。

也可以从管理员命令提示符手动运行：

```bat
cd /d D:\home\clean_safe_plus
clean_safe_plus.bat
```

## 脚本会做什么

脚本分为几个步骤：

1. 检查管理员权限。
2. 显示当前 C 盘空间。
3. 分析 `C:\` 下一级目录的大小。
4. 询问是否继续执行安全清理。
5. 清理用户临时目录、Windows 临时目录、Windows 更新下载缓存、回收站。
6. 询问是否关闭休眠以释放 `hiberfil.sys` 占用。
7. 如果检测到 `pip`、`conda`、`docker`，会分别询问是否清理对应缓存。
8. 显示清理后的 C 盘空间。

## 重要提示

- 脚本需要管理员权限，否则部分系统目录无法清理。
- Docker 清理项会删除未使用的镜像、容器、网络和构建缓存；运行中的容器不会被删除。
- 关闭休眠后不能再使用 Windows 的“休眠”功能，但普通关机和睡眠通常不受影响。
- 如果 C 盘仍然很满，优先检查：
  - `C:\Users\<用户名>\AppData`
  - `C:\ProgramData`
  - `C:\Windows`
  - `System Volume Information`
