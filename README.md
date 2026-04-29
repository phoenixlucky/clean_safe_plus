# C盘清理工具

`clean_safe_plus.bat` 是一个 Windows C 盘清理脚本，适合在清理前先查看磁盘空间，再按提示选择是否执行各类缓存清理。

脚本提示为中文，批处理文件使用 GBK/ANSI 编码，并在开头切换到 `chcp 936`，用于兼容中文 Windows 的 CMD 显示。

## 使用方式

推荐直接双击运行 `clean_safe_plus.bat`。脚本会自动请求管理员权限，请在弹出的 UAC 窗口中点击“是”。

也可以从管理员命令提示符手动运行：

```bat
cd /d D:\home\clean_safe_plus
clean_safe_plus.bat
```

## 执行流程

### 1. 管理员权限检查

脚本会先检查是否拥有管理员权限。没有管理员权限时，会自动重新请求管理员权限启动。

需要管理员权限的原因：

- 清理 `C:\Windows\Temp`
- 清理 Windows 更新缓存
- 清理回收站
- 关闭休眠
- 访问部分系统目录

### 2. 显示当前 C 盘空间

脚本会使用 PowerShell 查询 C 盘容量和剩余空间，输出类似：

```text
DeviceID SizeGB FreeGB
-------- ------ ------
C:       237.5  42.3
```

这一项只读取磁盘信息，不会删除文件。

### 3. 可选：分析 C 盘大目录

脚本会询问：

```text
是否现在分析 C 盘大目录？(Y/N):
```

输入 `Y` 后，会递归统计 `C:\` 下一级目录的大小，并显示最大的 12 个目录。

这一步可能很慢，因为它需要遍历大量文件。比如：

- `C:\Users`
- `C:\Windows`
- `C:\ProgramData`
- `C:\Program Files`
- Docker、conda、node_modules、微信、浏览器缓存目录

如果只是想快速清理，可以输入 `N` 跳过。

### 4. 安全清理

脚本会询问：

```text
是否继续执行安全清理？(Y/N):
```

输入 `Y` 后，会执行以下 5 项清理：

1. 清理当前用户临时目录：`%temp%`
2. 清理用户 `AppData\Local\Temp`
3. 清理 Windows 更新下载缓存：`C:\Windows\SoftwareDistribution\Download`
4. 清理回收站：`C:\$Recycle.Bin`
5. 清理 Windows 临时目录：`C:\Windows\Temp`

这些项目通常属于缓存或临时文件，不会主动删除用户文档、桌面文件、下载文件或已安装软件。

### 5. 可选：关闭休眠

脚本会询问：

```text
是否关闭休眠？(Y/N):
```

输入 `Y` 后会执行：

```bat
powercfg -h off
```

作用：

- 删除 `hiberfil.sys`
- 通常可释放数 GB 到几十 GB 空间

影响：

- Windows 的“休眠”功能会被关闭
- 普通关机和睡眠通常不受影响

### 6. 可选：清理 pip 缓存

脚本会自动检测可用的 pip 命令，优先级如下：

1. `python -m pip`
2. `py -m pip`
3. `pip`

这样可以避开某些机器上 `pip.exe` 启动器损坏的问题，例如仍然指向旧的 `C:\Python312\python.exe`。

如果检测到可用 pip，会先显示 pip 缓存目录，然后询问是否清理：

```text
是否清理 pip 缓存？(Y/N):
```

输入 `Y` 后会执行：

```bat
pip cache purge
```

或等价的：

```bat
python -m pip cache purge
```

### 7. 可选：清理 conda 缓存

如果检测到 conda，脚本会询问：

```text
是否继续清理 conda 缓存？(Y/N):
```

输入 `Y` 后会执行：

```bat
call conda clean --all -y 2>nul
```

这里使用 `call` 是必须的。Windows 上的 conda 通常是 `.bat/.cmd` 包装脚本，如果在当前批处理里直接执行 `conda clean`，执行完后可能不会回到原脚本，表现为后续步骤不再执行或窗口直接关闭。

`2>nul` 用于隐藏 conda 插件环境告警，例如 `conda-anaconda-tos` 或 pydantic 版本不兼容提示。这类告警来自本机 conda 环境，不是清理脚本本身的问题。

`conda clean --all -y` 会清理：

- 包缓存
- 索引缓存
- 临时文件
- 未使用的压缩包

它不会删除已有 conda 环境。

### 8. 可选：清理 Docker

如果检测到 Docker，脚本会先显示：

- Docker 当前磁盘占用：`docker system df`
- 容器列表：`docker ps -a`
- 镜像列表：`docker images`

然后询问：

```text
是否执行 docker system prune -a -f？(Y/N):
```

输入 `Y` 后会执行：

```bat
docker system prune -a -f
```

注意：

- 会删除未使用的容器、网络、镜像和构建缓存
- 正在运行的容器不会被删除
- 被删除的镜像以后可能需要重新下载

### 9. 显示清理后的 C 盘空间

脚本最后会再次显示 C 盘容量和剩余空间，用来对比清理前后的变化。

## 重要提示

- 建议在中文 Windows 上运行。
- 批处理文件应保持 GBK/ANSI 编码，不要改成 UTF-8，否则 CMD 可能显示乱码。
- 如果目录分析很慢，下一次运行时可以直接输入 `N` 跳过。
- 如果 C 盘仍然很满，优先检查：
  - `C:\Users\<用户名>\AppData`
  - `C:\ProgramData`
  - `C:\Windows`
  - `System Volume Information`
