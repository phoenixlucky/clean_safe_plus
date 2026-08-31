#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;
use std::{
    collections::{HashMap, HashSet},
    env,
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
};
use tauri::Manager;

#[derive(Clone)]
enum TargetMode {
    Contents,
    Directory,
    FilesByPrefix(String),
    RecursiveDirectoriesByName(String),
}

struct TargetSpec {
    id: String,
    label: String,
    path: PathBuf,
    mode: TargetMode,
    safe: bool,
}

#[derive(Serialize)]
struct CleanupTarget {
    id: String,
    label: String,
    path: String,
    bytes: u64,
    safe: bool,
    kind: String,
}

#[derive(Serialize)]
struct ScanResponse {
    free_bytes: u64,
    targets: Vec<CleanupTarget>,
}

#[derive(Serialize)]
struct TargetReport {
    id: String,
    label: String,
    freed_bytes: u64,
    remaining_bytes: u64,
    skipped_items: u64,
}

#[derive(Serialize)]
struct CleanupReport {
    free_before: u64,
    free_after: u64,
    freed_bytes: u64,
    processed: Vec<TargetReport>,
    windows_cleanup_ran: bool,
    warnings: Vec<String>,
}

#[derive(Serialize)]
struct ActionResponse {
    success: bool,
    message: String,
    details: Vec<String>,
    warnings: Vec<String>,
}

#[derive(Serialize)]
struct DiskEntry {
    path: String,
    bytes: u64,
    children: Vec<DiskEntry>,
}

#[derive(Serialize)]
struct DiskAnalysis {
    folders: Vec<DiskEntry>,
}

fn env_path(name: &str) -> Option<PathBuf> {
    env::var_os(name).map(PathBuf::from)
}

fn add_contents(specs: &mut Vec<TargetSpec>, id: &str, label: &str, path: PathBuf) {
    specs.push(TargetSpec {
        id: id.to_string(),
        label: label.to_string(),
        path,
        mode: TargetMode::Contents,
        safe: true,
    });
}

fn add_directory(specs: &mut Vec<TargetSpec>, id: &str, label: &str, path: PathBuf) {
    specs.push(TargetSpec {
        id: id.to_string(),
        label: label.to_string(),
        path,
        mode: TargetMode::Directory,
        safe: false,
    });
}

fn add_prefix(specs: &mut Vec<TargetSpec>, id: &str, label: &str, path: PathBuf, prefix: &str) {
    specs.push(TargetSpec {
        id: id.to_string(),
        label: label.to_string(),
        path,
        mode: TargetMode::FilesByPrefix(prefix.to_string()),
        safe: true,
    });
}

fn add_unique_contents(specs: &mut Vec<TargetSpec>, id: &str, label: &str, path: PathBuf) {
    if path.is_dir() && specs.iter().any(|spec| spec.path == path) {
        return;
    }
    add_contents(specs, id, label, path);
}

fn add_browser_cache_specs(
    specs: &mut Vec<TargetSpec>,
    browser_id: &str,
    browser_label: &str,
    root: PathBuf,
    subpaths: &[&str],
) {
    let Ok(entries) = fs::read_dir(root) else { return };
    let mut profiles = entries.flatten().map(|entry| entry.path()).filter(|path| path.is_dir()).collect::<Vec<_>>();
    profiles.sort();
    for (index, profile_path) in profiles.into_iter().enumerate() {
        let profile = profile_path.file_name().unwrap_or_default().to_string_lossy().to_string();
        for (part_index, relative) in subpaths.iter().enumerate() {
            add_unique_contents(
                specs,
                &format!("{browser_id}-{index}-{part_index}"),
                &format!("{browser_label} {profile} {relative}"),
                profile_path.join(relative),
            );
        }
    }
}

fn target_specs() -> Vec<TargetSpec> {
    let mut specs = Vec::new();
    let local = env_path("LOCALAPPDATA");
    let app = env_path("APPDATA");
    let user = env_path("USERPROFILE");
    let system_root = env_path("SystemRoot").unwrap_or_else(|| PathBuf::from(r"C:\Windows"));
    let temp = env_path("TEMP").or_else(|| local.clone().map(|path| path.join("Temp")));

    if let Some(path) = temp {
        add_unique_contents(&mut specs, "user-temp", "用户临时文件", path);
    }
    if let Some(local) = &local {
        add_unique_contents(&mut specs, "local-temp", "应用临时文件", local.join("Temp"));
        add_contents(&mut specs, "uv-cache", "uv 缓存", local.join("uv/cache"));
        add_contents(&mut specs, "electron-cache", "Electron 缓存", local.join("electron/Cache"));
        add_contents(&mut specs, "electron-builder-cache", "Electron Builder 缓存", local.join("electron-builder/Cache"));
        add_contents(&mut specs, "d3d-cache", "DirectX 着色器缓存", local.join("D3DSCache"));
        add_contents(&mut specs, "nvidia-dx-cache", "NVIDIA DX 缓存", local.join("NVIDIA/DXCache"));
        add_contents(&mut specs, "nvidia-gl-cache", "NVIDIA GL 缓存", local.join("NVIDIA/GLCache"));
        add_contents(&mut specs, "amd-dx-cache", "AMD DX 缓存", local.join("AMD/DxCache"));
        add_contents(&mut specs, "amd-gl-cache", "AMD GL 缓存", local.join("AMD/GLCache"));
        add_contents(&mut specs, "npm-local-cache", "npm 本地缓存", local.join("npm-cache"));
        add_contents(&mut specs, "pip-local-cache", "pip 缓存", local.join("pip/Cache"));
        add_contents(&mut specs, "evaluationspiders-cache", "EvaluationSpiders 浏览器缓存", local.join("EvaluationSpiders/Chrome9222/Default/Cache"));
        add_contents(&mut specs, "evaluationspiders-code-cache", "EvaluationSpiders 代码缓存", local.join("EvaluationSpiders/Chrome9222/Default/Code Cache"));
        add_contents(&mut specs, "huorong-appstore-cache", "火绒应用商店缓存", local.join("Huorong/AppStore/storecache/Cache"));
        add_contents(&mut specs, "mcp-chrome-logs", "Chrome MCP 日志", local.join("mcp-chrome-bridge/logs"));
        add_contents(&mut specs, "node-gyp-cache", "node-gyp 缓存", local.join("node-gyp/Cache"));
        add_browser_cache_specs(&mut specs, "chrome", "Chrome", local.join("Google/Chrome/User Data"), &["Cache", "Code Cache", "GPUCache", "ShaderCache", "GrShaderCache", "Service Worker/CacheStorage"]);
        add_browser_cache_specs(&mut specs, "edge", "Edge", local.join("Microsoft/Edge/User Data"), &["Cache", "Code Cache", "GPUCache", "ShaderCache", "GrShaderCache", "Service Worker/CacheStorage"]);
        add_directory(&mut specs, "hermes", "Hermes 本地数据（整目录）", local.join("hermes"));
    }
    if let Some(app) = &app {
        add_contents(&mut specs, "npm-roaming-cache", "npm 漫游缓存", app.join("npm-cache"));
        add_contents(&mut specs, "deepseek-cache", "DeepSeek 桌面缓存", app.join("@deepseek-ai/dsh-desktop/Cache"));
        add_contents(&mut specs, "vscode-cache", "VSCode 缓存", app.join("Code/Cache"));
        add_contents(&mut specs, "vscode-cached-data", "VSCode 已缓存数据", app.join("Code/CachedData"));
        add_contents(&mut specs, "vscode-code-cache", "VSCode 代码缓存", app.join("Code/Code Cache"));
        add_contents(&mut specs, "vscode-gpu-cache", "VSCode GPU 缓存", app.join("Code/GPUCache"));
        add_contents(&mut specs, "vscode-logs", "VSCode 日志", app.join("Code/logs"));
        add_contents(&mut specs, "vscode-extension-cache", "VSCode 扩展安装缓存", app.join("Code/CachedExtensionVSIXs"));
        add_contents(&mut specs, "pip-roaming-cache", "pip 漫游缓存", app.join("pip/Cache"));
        let state_root = app.join("reasonix/mcp-state");
        if let Ok(entries) = fs::read_dir(state_root) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    let state_name = entry.file_name().to_string_lossy().to_string();
                    add_contents(&mut specs, &format!("reasonix-playwright-{state_name}"), &format!("Reasonix Playwright 缓存（{state_name}）"), path.join("playwright-mcp/cache"));
                }
            }
        }
        add_browser_cache_specs(&mut specs, "firefox", "Firefox", app.join("Mozilla/Firefox/Profiles"), &["cache2", "startupCache"]);
    }
    if let Some(user) = &user {
        add_contents(&mut specs, "conda-user-cache", "Conda 包缓存", user.join(".conda/pkgs"));
    }
    if let Some(conda_dirs) = env::var_os("CONDA_PKGS_DIRS") {
        for (index, path) in env::split_paths(&conda_dirs).enumerate() {
            add_contents(&mut specs, &format!("conda-env-{index}"), "Conda 包缓存", path);
        }
    }
    add_contents(&mut specs, "nvidia-downloader", "NVIDIA 下载器缓存", PathBuf::from(r"C:\ProgramData\NVIDIA Corporation\Downloader"));
    add_contents(&mut specs, "nvidia-installer", "NVIDIA 安装缓存", env_path("ProgramFiles").unwrap_or_else(|| PathBuf::from(r"C:\Program Files")).join("NVIDIA Corporation/Installer2"));
    add_prefix(&mut specs, "thumbcache", "Windows 缩略图缓存", local.clone().unwrap_or_default().join("Microsoft/Windows/Explorer"), "thumbcache_");
    add_contents(&mut specs, "windows-recycle-bin", "回收站", PathBuf::from(r"C:\$Recycle.Bin"));
    add_contents(&mut specs, "windows-temp", "Windows 临时文件", system_root.join("Temp"));
    add_contents(&mut specs, "windows-logs", "Windows 日志", system_root.join("Logs"));
    add_contents(&mut specs, "wer-system", "Windows 错误报告", PathBuf::from(r"C:\ProgramData\Microsoft\Windows\WER"));
    if let Some(local) = &local {
        add_contents(&mut specs, "wer-user", "用户错误报告", local.join("Microsoft/Windows/WER"));
    }
    add_contents(&mut specs, "prefetch", "预读取缓存", system_root.join("Prefetch"));
    add_contents(&mut specs, "windows-update-cache", "Windows 更新下载缓存", system_root.join("SoftwareDistribution/Download"));
    add_contents(&mut specs, "delivery-optimization-cache", "Delivery Optimization cache", system_root.join("ServiceProfiles/NetworkService/AppData/Local/Microsoft/Windows/DeliveryOptimization/Cache"));
    specs
}

fn directory_size(path: &Path) -> u64 {
    let Ok(entries) = fs::read_dir(path) else { return 0 };
    let mut total = 0u64;
    for entry in entries.flatten() {
        let Ok(file_type) = entry.file_type() else { continue };
        if file_type.is_symlink() { continue; }
        if file_type.is_file() {
            if let Ok(metadata) = entry.metadata() { total = total.saturating_add(metadata.len()); }
        } else if file_type.is_dir() {
            total = total.saturating_add(directory_size(&entry.path()));
        }
    }
    total
}

fn directory_size_cached(path: &Path, cache: &mut HashMap<PathBuf, u64>) -> u64 {
    let key = path.to_path_buf();
    if let Some(size) = cache.get(&key) { return *size; }
    let Ok(entries) = fs::read_dir(path) else {
        cache.insert(key, 0);
        return 0;
    };
    let mut total = 0u64;
    for entry in entries.flatten() {
        let Ok(file_type) = entry.file_type() else { continue; };
        if file_type.is_symlink() { continue; }
        if file_type.is_file() {
            if let Ok(metadata) = entry.metadata() { total = total.saturating_add(metadata.len()); }
        } else if file_type.is_dir() {
            total = total.saturating_add(directory_size_cached(&entry.path(), cache));
        }
    }
    cache.insert(key, total);
    total
}

fn matching_files(path: &Path, prefix: &str, output: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(path) else { return };
    for entry in entries.flatten() {
        let entry_path = entry.path();
        let Ok(file_type) = entry.file_type() else { continue };
        if file_type.is_symlink() { continue; }
        if file_type.is_file() && entry.file_name().to_string_lossy().starts_with(prefix) {
            output.push(entry_path);
        } else if file_type.is_dir() {
            matching_files(&entry_path, prefix, output);
        }
    }
}

fn matching_directories(path: &Path, name: &str, output: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(path) else { return };
    for entry in entries.flatten() {
        let entry_path = entry.path();
        let Ok(file_type) = entry.file_type() else { continue };
        if file_type.is_symlink() { continue; }
        if file_type.is_dir() {
            if entry.file_name().to_string_lossy().eq_ignore_ascii_case(name) {
                output.push(entry_path.clone());
            } else {
                matching_directories(&entry_path, name, output);
            }
        }
    }
}

fn remove_entry(path: &Path) -> Result<(), std::io::Error> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_dir() && !metadata.file_type().is_symlink() { fs::remove_dir_all(path) } else { fs::remove_file(path) }
}

fn spec_size(spec: &TargetSpec) -> u64 {
    match &spec.mode {
        TargetMode::Contents | TargetMode::Directory => directory_size(&spec.path),
        TargetMode::FilesByPrefix(prefix) => {
            let mut files = Vec::new();
            matching_files(&spec.path, prefix, &mut files);
            files.iter().filter_map(|path| fs::metadata(path).ok()).map(|metadata| metadata.len()).sum()
        }
        TargetMode::RecursiveDirectoriesByName(name) => {
            let mut directories = Vec::new();
            matching_directories(&spec.path, name, &mut directories);
            directories.iter().map(|path| directory_size(path)).sum()
        }
    }
}

fn clear_spec(spec: &TargetSpec) -> (u64, u64, u64) {
    let before = spec_size(spec);
    let mut skipped = 0u64;
    match &spec.mode {
        TargetMode::Directory => {
            if spec.path.exists() && remove_entry(&spec.path).is_err() { skipped = 1; }
        }
        TargetMode::Contents => match fs::read_dir(&spec.path) {
            Ok(entries) => for entry in entries.flatten() { if remove_entry(&entry.path()).is_err() { skipped += 1; } },
            Err(_) => if spec.path.exists() { skipped = 1; },
        },
        TargetMode::FilesByPrefix(prefix) => {
            let mut files = Vec::new();
            matching_files(&spec.path, prefix, &mut files);
            for file in files { if remove_entry(&file).is_err() { skipped += 1; } }
        }
        TargetMode::RecursiveDirectoriesByName(name) => {
            let mut directories = Vec::new();
            matching_directories(&spec.path, name, &mut directories);
            directories.sort_by_key(|path| std::cmp::Reverse(path.components().count()));
            for directory in directories { if remove_entry(&directory).is_err() { skipped += 1; } }
        }
    }
    let remaining = spec_size(spec);
    (before.saturating_sub(remaining), remaining, skipped)
}

#[cfg(windows)]
fn hidden_command(program: &str) -> Command {
    use std::os::windows::process::CommandExt;
    let mut command = Command::new(program);
    command.creation_flags(0x08000000);
    command
}

#[cfg(not(windows))]
fn hidden_command(program: &str) -> Command { Command::new(program) }

fn run_command(program: &str, args: &[&str]) -> Result<Output, String> {
    hidden_command(program).args(args).output().map_err(|error| format!("{program}: {error}"))
}

fn run_powershell(script: &str) -> Result<Output, String> {
    run_command("powershell.exe", &["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script])
}

fn ps_quote(value: &str) -> String { format!("'{}'", value.replace('\'', "''")) }

#[cfg(windows)]
fn run_elevated(program: &str, args: &[&str]) -> Result<Output, String> {
    let arguments = args.iter().map(|arg| ps_quote(arg)).collect::<Vec<_>>().join(",");
    let script = format!("$p=Start-Process -FilePath {} -ArgumentList @({}) -Verb RunAs -Wait -PassThru; exit $p.ExitCode", ps_quote(program), arguments);
    run_powershell(&script)
}

#[cfg(not(windows))]
fn run_elevated(_program: &str, _args: &[&str]) -> Result<Output, String> { Err("This action is only available on Windows".to_string()) }

#[cfg(windows)]
fn run_elevated_powershell(script: &str) -> Result<Output, String> {
    let encoded = powershell_base64(script);
    let wrapper = format!("$p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',{}) -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode", ps_quote(&encoded));
    run_powershell(&wrapper)
}

#[cfg(not(windows))]
fn run_elevated_powershell(_script: &str) -> Result<Output, String> { Err("This action is only available on Windows".to_string()) }

fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut encoded = String::new();
    let mut index = 0;
    while index < bytes.len() {
        let first = bytes[index] as u32;
        let second = bytes.get(index + 1).copied().unwrap_or(0) as u32;
        let third = bytes.get(index + 2).copied().unwrap_or(0) as u32;
        let chunk = (first << 16) | (second << 8) | third;
        encoded.push(TABLE[((chunk >> 18) & 0x3f) as usize] as char);
        encoded.push(TABLE[((chunk >> 12) & 0x3f) as usize] as char);
        if index + 1 < bytes.len() { encoded.push(TABLE[((chunk >> 6) & 0x3f) as usize] as char); } else { encoded.push('='); }
        if index + 2 < bytes.len() { encoded.push(TABLE[(chunk & 0x3f) as usize] as char); } else { encoded.push('='); }
        index += 3;
    }
    encoded
}

fn powershell_base64(script: &str) -> String {
    let bytes = script.encode_utf16().flat_map(|unit| unit.to_le_bytes()).collect::<Vec<_>>();
    base64_encode(&bytes)
}

fn output_text(output: &Output) -> String {
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if !stderr.is_empty() { stderr } else { stdout }
}

fn command_action(label: &str, output: Result<Output, String>) -> ActionResponse {
    match output {
        Ok(output) if output.status.success() => ActionResponse {
            success: true,
            message: format!("{label}已完成"),
            details: Vec::new(),
            warnings: Vec::new(),
        },
        Ok(output) => ActionResponse {
            success: false,
            message: format!("{label}未完成"),
            details: Vec::new(),
            warnings: vec![format!("{}", if output_text(&output).is_empty() { format!("{label}返回了非零状态，可能是管理员权限被取消或系统拒绝了操作") } else { format!("{label}：{}", output_text(&output)) })],
        },
        Err(error) => ActionResponse { success: false, message: format!("{label}无法启动"), details: Vec::new(), warnings: vec![error] },
    }
}

fn format_bytes(bytes: u64) -> String {
    if bytes < 1024 { return format!("{bytes} B"); }
    let units = ["KB", "MB", "GB", "TB"];
    let mut value = bytes as f64;
    let mut index = 0;
    while value >= 1024.0 && index < units.len() - 1 { value /= 1024.0; index += 1; }
    format!("{value:.2} {}", units[index])
}

fn clear_matching_targets<F>(matcher: F, group: &str) -> ActionResponse
where
    F: Fn(&TargetSpec) -> bool,
{
    let mut details = Vec::new();
    let mut warnings = Vec::new();
    let mut freed = 0u64;
    for spec in target_specs().into_iter().filter(matcher) {
        if !spec.path.exists() { continue; }
        let (bytes, _, skipped) = clear_spec(&spec);
        freed = freed.saturating_add(bytes);
        if bytes > 0 { details.push(format!("{}：{}", spec.label, format_bytes(bytes))); }
        if skipped > 0 { warnings.push(format!("{}：有 {skipped} 个文件被占用或受保护，已跳过", spec.label)); }
    }
    details.insert(0, format!("释放约 {}", format_bytes(freed)));
    ActionResponse { success: true, message: format!("{group}清理完成"), details, warnings }
}

fn close_processes(processes: &[&str]) {
    for process in processes {
        let _ = run_command("taskkill.exe", &["/F", "/IM", process]);
    }
}

fn configured_wechat_path() -> Option<PathBuf> {
    let output = run_powershell("try { (Get-ItemProperty -Path 'HKCU:\\Software\\Tencent\\WeChat' -ErrorAction Stop).FileSavePath } catch { }").ok()?;
    String::from_utf8_lossy(&output.stdout).lines().map(str::trim).find(|line| !line.is_empty() && !line.eq_ignore_ascii_case("MyDocument:")).map(PathBuf::from)
}

fn wechat_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Some(user) = env_path("USERPROFILE") {
        roots.extend([user.join("Documents/WeChat Files"), user.join("Documents/Weixin Files"), user.join("Documents/xwechat_files"), user.join("WeChat Files")]);
    }
    if let Some(app) = env_path("APPDATA") { roots.extend([app.join("Tencent/WeChat Files"), app.join("Tencent/Weixin Files")]); }
    if let Some(local) = env_path("LOCALAPPDATA") { roots.extend([local.join("Tencent/WeChat Files"), local.join("Tencent/Weixin Files")]); }
    if let Some(custom) = configured_wechat_path() { roots.extend([custom.clone(), custom.join("WeChat Files"), custom.join("Weixin Files"), custom.join("xwechat_files")]); }
    roots.sort_by(|left, right| left.to_string_lossy().cmp(&right.to_string_lossy()));
    roots.dedup();
    roots
}

fn wechat_specs() -> Vec<TargetSpec> {
    let mut storage_dirs = Vec::new();
    let mut message_dirs = Vec::new();
    for root in wechat_roots().into_iter().filter(|path| path.is_dir()) {
        matching_directories(&root, "FileStorage", &mut storage_dirs);
        matching_directories(&root, "msg", &mut message_dirs);
    }
    storage_dirs.sort();
    storage_dirs.dedup();
    message_dirs.sort();
    message_dirs.dedup();
    let mut specs = Vec::new();
    for (index, path) in storage_dirs.into_iter().enumerate() { add_contents(&mut specs, &format!("wechat-storage-{index}"), "WeChat FileStorage cache", path); }
    let mut index = 0;
    for message in message_dirs {
        let lower = message.to_string_lossy().to_ascii_lowercase();
        if !lower.contains("wechat") && !lower.contains("weixin") && !lower.contains("xwechat") { continue; }
        for name in ["attach", "file", "image", "video"] {
            let path = message.join(name);
            if path.is_dir() { add_contents(&mut specs, &format!("wechat-message-{index}"), &format!("WeChat msg/{name}"), path); index += 1; }
        }
    }
    specs
}

fn developer_cache_action() -> ActionResponse {
    let mut response = clear_matching_targets(|spec| spec.id.starts_with("npm-") || spec.id.starts_with("pip-") || spec.id.starts_with("conda-"), "开发工具缓存");
    let mut commands = Vec::new();
    if run_command("python", &["-m", "pip", "cache", "purge"]).map(|output| output.status.success()).unwrap_or(false) { commands.push("python -m pip cache purge"); }
    else if run_command("py", &["-m", "pip", "cache", "purge"]).map(|output| output.status.success()).unwrap_or(false) { commands.push("py -m pip cache purge"); }
    else if run_command("pip", &["cache", "purge"]).map(|output| output.status.success()).unwrap_or(false) { commands.push("pip cache purge"); }
    if run_command("npm", &["cache", "clean", "--force"]).map(|output| output.status.success()).unwrap_or(false) { commands.push("npm cache clean --force"); }
    if run_command("conda", &["clean", "--all", "-y"]).map(|output| output.status.success()).unwrap_or(false) { commands.push("conda clean --all -y"); }
    if commands.is_empty() { response.warnings.push("pip、npm、conda 命令不可用，或执行时返回了错误".to_string()); }
    else { response.details.push(format!("已执行：{}", commands.join("、"))); }
    response
}

fn pycache_action() -> ActionResponse {
    let mut specs = Vec::new();
    if let Some(user) = env_path("USERPROFILE") {
        specs.push(TargetSpec { id: "pycache-user".to_string(), label: "__pycache__ under user profile".to_string(), path: user, mode: TargetMode::RecursiveDirectoriesByName("__pycache__".to_string()), safe: true });
    }
    if let Some(local) = env_path("LOCALAPPDATA") {
        specs.push(TargetSpec { id: "pycache-local".to_string(), label: "__pycache__ under LocalAppData".to_string(), path: local, mode: TargetMode::RecursiveDirectoriesByName("__pycache__".to_string()), safe: true });
    }
    let mut freed = 0u64;
    let mut skipped = 0u64;
    for spec in specs { let (bytes, _, count) = clear_spec(&spec); freed = freed.saturating_add(bytes); skipped = skipped.saturating_add(count); }
    ActionResponse { success: true, message: "__pycache__ 清理完成".to_string(), details: vec![format!("释放约 {}", format_bytes(freed))], warnings: if skipped > 0 { vec![format!("有 {skipped} 个目录被占用或受保护，已跳过")] } else { Vec::new() } }
}

fn service_and_registry_optimization() -> ActionResponse {
    let script = r#"
$ErrorActionPreference = 'Continue'
$services = @('SysMain','XblAuthManager','XblGameSave','XboxNetApiSvc')
foreach ($name in $services) {
  Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
  Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
}
Stop-Service -Name WSearch -Force -ErrorAction SilentlyContinue
Set-Service -Name WSearch -StartupType Manual -ErrorAction SilentlyContinue
New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name EnableTransparency -Type DWord -Value 0
New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -Type DWord -Value 2
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OneDrive -ErrorAction SilentlyContinue
"#;
    command_action("系统服务优化", run_elevated_powershell(script))
}

fn network_optimization() -> ActionResponse {
    let script = r#"
$ErrorActionPreference = 'Continue'
foreach ($name in @('DoSvc','DiagTrack','dmwappushservice')) {
  Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
  Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
}
ipconfig /flushdns | Out-Null
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
ipconfig /release | Out-Null
ipconfig /renew | Out-Null
netsh interface ip delete arpcache | Out-Null
netsh interface tcp set global autotuninglevel=normal | Out-Null
netsh interface tcp set global rss=enabled | Out-Null
netsh interface tcp set global ecncapability=enabled | Out-Null
powercfg -setacvalueindex scheme_current sub_wireless 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 0 | Out-Null
powercfg -setdcvalueindex scheme_current sub_wireless 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 0 | Out-Null
powercfg -setacvalueindex scheme_current sub_pcie 0ce3997e-6a54-4a3f-b1e8-4f8b9b7d8b6f 0 | Out-Null
powercfg -setdcvalueindex scheme_current sub_pcie 0ce3997e-6a54-4a3f-b1e8-4f8b9b7d8b6f 0 | Out-Null
foreach ($item in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -match 'Wi-Fi|Ethernet|以太网' })) {
  netsh interface ipv4 set subinterface "$($item.InterfaceAlias)" mtu=1500 store=persistent | Out-Null
}
"#;
    command_action("网络优化", run_elevated_powershell(script))
}

fn vpn_fix() -> ActionResponse {
    let script = r#"
$ErrorActionPreference = 'Continue'
ipconfig /flushdns | Out-Null
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
netsh winhttp reset proxy | Out-Null
foreach ($name in @('Dnscache','iphlpsvc')) {
  Set-Service -Name $name -StartupType Automatic -ErrorAction SilentlyContinue
  Start-Service -Name $name -ErrorAction SilentlyContinue
}
foreach ($adapter in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')) {
  Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue | Set-NetIPInterface -AutomaticMetric Enabled -ErrorAction SilentlyContinue
}
"#;
    command_action("VPN/TUN 修复", run_elevated_powershell(script))
}

fn cleanmgr_action() -> ActionResponse {
    command_action("Windows 磁盘清理", run_elevated("cleanmgr.exe", &["/verylowdisk", "/d", "C:"]))
}

#[tauri::command]
fn run_maintenance(action: String) -> Result<ActionResponse, String> {
    let result = match action.as_str() {
        "browser-cache" => {
            close_processes(&["chrome.exe", "msedge.exe", "firefox.exe"]);
            clear_matching_targets(|spec| spec.id.starts_with("chrome-") || spec.id.starts_with("edge-") || spec.id.starts_with("firefox-"), "浏览器缓存")
        }
        "wechat-cache" => {
            close_processes(&["WeChat.exe", "Weixin.exe"]);
            let mut details = Vec::new();
            let mut warnings = Vec::new();
            let mut freed = 0u64;
            for spec in wechat_specs() {
                let (bytes, _, skipped) = clear_spec(&spec);
                freed = freed.saturating_add(bytes);
                if skipped > 0 { warnings.push(format!("{}：有 {skipped} 个文件被占用或受保护，已跳过", spec.label)); }
            }
            details.push(format!("释放约 {}", format_bytes(freed)));
            ActionResponse { success: true, message: "微信缓存清理完成".to_string(), details, warnings }
        }
        "vscode-cache" => clear_matching_targets(|spec| spec.id.starts_with("vscode-"), "VSCode 缓存"),
        "nvidia-cache" => clear_matching_targets(|spec| spec.id.starts_with("nvidia-") || spec.id.starts_with("amd-"), "GPU 缓存"),
        "developer-cache" => developer_cache_action(),
        "pycache" => pycache_action(),
        "docker-prune" => command_action("Docker 清理", run_command("docker", &["system", "prune", "-a", "-f"])),
        "hibernate-off" => command_action("关闭休眠", run_elevated("powercfg.exe", &["-h", "off"])),
        "services-optimize" => service_and_registry_optimization(),
        "network-optimize" => network_optimization(),
        "vpn-fix" => vpn_fix(),
        "windows-cleanup" => cleanmgr_action(),
        "dism-cleanup" => command_action("DISM 组件清理", run_elevated("Dism.exe", &["/Online", "/Cleanup-Image", "/StartComponentCleanup"])),
        "shadow-resize" => command_action("卷影副本空间限制", run_elevated("vssadmin.exe", &["Resize", "ShadowStorage", "/For=C:", "/On=C:", "/MaxSize=5GB"])),
        _ => return Err(format!("Unknown maintenance action: {action}")),
    };
    Ok(result)
}

#[tauri::command(rename_all = "camelCase")]
fn set_pagefile(mode: String, drive: Option<String>, initial_mb: Option<u32>, max_mb: Option<u32>) -> Result<ActionResponse, String> {
    let script = match mode.as_str() {
        "auto" => r#"$cs=Get-CimInstance Win32_ComputerSystem; Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$true}"#.to_string(),
        "none" => r#"$cs=Get-CimInstance Win32_ComputerSystem; Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false}; Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Remove-CimInstance"#.to_string(),
        "custom" => {
            let letter = drive.unwrap_or_else(|| "D".to_string()).trim().trim_end_matches(':').to_ascii_uppercase();
            let initial = initial_mb.ok_or("Initial pagefile size is required")?;
            let maximum = max_mb.ok_or("Maximum pagefile size is required")?;
            if letter.len() != 1 || !letter.as_bytes()[0].is_ascii_alphabetic() { return Err("Drive must be a single letter such as D".to_string()); }
            if initial == 0 || maximum < initial { return Err("Pagefile sizes are invalid".to_string()); }
            format!(r#"$letter={}; $cs=Get-CimInstance Win32_ComputerSystem; Set-CimInstance -InputObject $cs -Property @{{AutomaticManagedPagefile=$false}}; $pf=Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object {{ $_.Name -imatch ('^'+[regex]::Escape($letter+':')) }} | Select-Object -First 1; if ($pf) {{ Set-CimInstance -InputObject $pf -Property @{{InitialSize=[uint32]{}; MaximumSize=[uint32]{}}} }} else {{ New-CimInstance -ClassName Win32_PageFileSetting -Property @{{Name=($letter+':\pagefile.sys'); InitialSize=[uint32]{}; MaximumSize=[uint32]{}}} | Out-Null }}"#, ps_quote(&letter), initial, maximum, initial, maximum)
        }
        _ => return Err("Unknown pagefile mode".to_string()),
    };
    Ok(command_action("页面文件配置", run_elevated_powershell(&script)))
}

#[cfg(windows)]
fn free_space_bytes() -> Result<u64, String> {
    use std::{ffi::OsStr, os::windows::ffi::OsStrExt};
    #[link(name = "kernel32")]
    extern "system" { fn GetDiskFreeSpaceExW(directory_name: *const u16, free_bytes_available: *mut u64, total_number_of_bytes: *mut u64, total_number_of_free_bytes: *mut u64) -> i32; }
    let path: Vec<u16> = OsStr::new("C:\\").encode_wide().chain(std::iter::once(0)).collect();
    let mut available = 0u64;
    let mut total = 0u64;
    let mut total_free = 0u64;
    let ok = unsafe { GetDiskFreeSpaceExW(path.as_ptr(), &mut available, &mut total, &mut total_free) };
    if ok == 0 { Err(std::io::Error::last_os_error().to_string()) } else { Ok(available) }
}

#[cfg(not(windows))]
fn free_space_bytes() -> Result<u64, String> { Err("This client currently supports Windows only".to_string()) }

#[tauri::command]
fn scan_cleanup() -> Result<ScanResponse, String> {
    let targets = target_specs().into_iter().filter(|spec| spec.path.is_dir()).map(|spec| {
        let bytes = spec_size(&spec);
        let kind = match &spec.mode { TargetMode::Contents => "contents", TargetMode::Directory => "directory", TargetMode::FilesByPrefix(_) => "file pattern", TargetMode::RecursiveDirectoriesByName(_) => "recursive directory pattern" };
        CleanupTarget { id: spec.id, label: spec.label, path: spec.path.display().to_string(), bytes, safe: spec.safe, kind: kind.to_string() }
    }).collect();
    Ok(ScanResponse { free_bytes: free_space_bytes()?, targets })
}

#[tauri::command(rename_all = "camelCase")]
fn clean_targets(target_ids: Vec<String>, run_windows_cleanup: bool) -> Result<CleanupReport, String> {
    let free_before = free_space_bytes()?;
    let requested = target_ids.into_iter().collect::<HashSet<_>>();
    let mut processed = Vec::new();
    let mut warnings = Vec::new();
    for spec in target_specs() {
        if !requested.contains(&spec.id) { continue; }
        let (freed_bytes, remaining_bytes, skipped_items) = clear_spec(&spec);
        if skipped_items > 0 { warnings.push(format!("{}：有 {skipped_items} 个文件被占用或受保护，已跳过", spec.label)); }
        processed.push(TargetReport { id: spec.id, label: spec.label, freed_bytes, remaining_bytes, skipped_items });
    }
    let windows_cleanup_ran = if run_windows_cleanup {
        let result = cleanmgr_action();
        warnings.extend(result.warnings);
        result.success
    } else { false };
    let free_after = free_space_bytes()?;
    Ok(CleanupReport { free_before, free_after, freed_bytes: free_after.saturating_sub(free_before), processed, windows_cleanup_ran, warnings })
}

fn disk_root_paths() -> Vec<PathBuf> {
    fs::read_dir(r"C:\")
        .into_iter()
        .flatten()
        .flatten()
        .filter(|entry| entry.path().is_dir())
        .map(|entry| entry.path())
        .collect()
}

const LARGE_FOLDER_THRESHOLD: u64 = 1024 * 1024 * 1024;

fn large_folder_node(path: &Path, bytes: u64, cache: &mut HashMap<PathBuf, u64>) -> DiskEntry {
    let mut children = fs::read_dir(path)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let child_path = entry.path();
            let file_type = entry.file_type().ok()?;
            if !file_type.is_dir() || file_type.is_symlink() { return None; }
            let child_bytes = directory_size_cached(&child_path, cache);
            (child_bytes >= LARGE_FOLDER_THRESHOLD).then(|| large_folder_node(&child_path, child_bytes, cache))
        })
        .collect::<Vec<_>>();
    children.sort_by(|left, right| right.bytes.cmp(&left.bytes));
    DiskEntry { path: path.display().to_string(), bytes, children }
}

#[tauri::command]
fn analyze_disk() -> Result<DiskAnalysis, String> {
    let root_paths = disk_root_paths();
    let mut cache = HashMap::new();
    let mut folders = root_paths.into_iter().filter_map(|path| {
        let bytes = directory_size_cached(&path, &mut cache);
        (bytes >= LARGE_FOLDER_THRESHOLD).then(|| large_folder_node(&path, bytes, &mut cache))
    }).collect::<Vec<_>>();
    folders.sort_by(|left, right| right.bytes.cmp(&left.bytes));
    Ok(DiskAnalysis { folders })
}

#[cfg(windows)]
#[tauri::command]
fn open_path(path: String) -> Result<(), String> {
    let target = PathBuf::from(&path);
    if !target.is_dir() {
        return Err(format!("文件夹不存在：{path}"));
    }

    Command::new("explorer.exe")
        .arg(&target)
        .spawn()
        .map(|_| ())
        .map_err(|error| format!("启动资源管理器失败：{error}"))
}

#[cfg(not(windows))]
#[tauri::command]
fn open_path(_path: String) -> Result<(), String> {
    Err("打开文件夹目前仅支持 Windows".to_string())
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/icon.png"))?;
            let window = app.get_webview_window("main").ok_or("main window not found")?;
            window.set_icon(icon)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![scan_cleanup, clean_targets, run_maintenance, set_pagefile, analyze_disk, open_path])
        .run(tauri::generate_context!())
        .expect("error while running Clean Safe Plus");
}
