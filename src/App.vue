<script setup>
import { computed, onMounted, ref } from 'vue'
import { invoke } from '@tauri-apps/api/core'

const targets = ref([])
const selected = ref(new Set())
const freeBytes = ref(0)
const loading = ref(false)
const cleaning = ref(false)
const actionBusy = ref('')
const runWindowsCleanup = ref(false)
const error = ref('')
const notice = ref('')
const lastReport = ref(null)
const lastAction = ref(null)
const analysis = ref(null)
const activeView = ref('home')
const analysisCopyStatus = ref('')
const analysisOpenPath = ref('')

const navItems = [
  { id: 'home', label: '电脑', hint: '概览', icon: 'computer' },
  { id: 'tools', label: '系统工具', hint: '维护', icon: 'tools' },
  { id: 'analysis', label: '磁盘分析', hint: '空间', icon: 'disk' },
]

const pagefileMode = ref('auto')
const pagefileDrive = ref('D')
const pagefileInitial = ref(8192)
const pagefileMaximum = ref(16384)

const cleanupTools = [
  { id: 'browser-cache', label: '浏览器缓存', description: 'Chrome、Edge、Firefox 缓存与启动缓存', confirm: '将关闭浏览器后清理缓存文件，是否继续？' },
  { id: 'wechat-cache', label: '微信缓存', description: 'FileStorage 与消息附件/图片/视频缓存', confirm: '微信目录可能包含本地媒体文件。请先退出微信，确认继续清理？' },
  { id: 'vscode-cache', label: 'VSCode 缓存', description: 'Cache、GPUCache、日志和扩展安装缓存', confirm: '建议先退出 VSCode。确认清理 VSCode 缓存？' },
  { id: 'nvidia-cache', label: 'GPU 缓存', description: 'NVIDIA 与 AMD 着色器和安装缓存', confirm: '确认清理 NVIDIA/AMD 图形缓存？' },
  { id: 'developer-cache', label: '开发工具缓存', description: 'pip、npm、conda 包缓存', confirm: '确认清理 pip、npm、conda 缓存？' },
  { id: 'pycache', label: '__pycache__', description: '用户目录和 LocalAppData 下的 Python 字节码缓存', confirm: '确认递归清理用户目录中的 __pycache__？' },
  { id: 'docker-prune', label: 'Docker 未使用资源', description: '删除未使用的镜像、容器和网络', confirm: 'Docker prune -a 会删除所有未使用的镜像、容器和网络，确认继续？' },
]

const systemTools = [
  { id: 'hibernate-off', label: '关闭休眠', description: '删除 hiberfil.sys，释放磁盘空间', confirm: '关闭休眠会删除 hiberfil.sys，并禁用休眠功能。确认？' },
  { id: 'services-optimize', label: '系统服务优化', description: '调整 SysMain、搜索和 Xbox 后台服务', confirm: '此操作会修改服务启动方式、透明效果和 OneDrive 启动项，确认？' },
  { id: 'network-optimize', label: '网络优化', description: '刷新 DNS、重置协议、恢复 TCP 默认优化', confirm: '网络会短暂中断，并修改部分网络服务设置。确认？' },
  { id: 'vpn-fix', label: 'VPN/TUN 修复', description: '重置代理、Winsock/IP 并恢复网络服务', confirm: '此操作会重置网络协议，VPN/TUN 可能需要重新连接。确认？' },
  { id: 'windows-cleanup', label: 'Windows 磁盘清理', description: '调用系统自带 cleanmgr 清理默认项目', confirm: '确认运行 Windows 磁盘清理？' },
  { id: 'dism-cleanup', label: 'DISM 组件清理', description: '清理 Windows 组件存储中的可替换组件', confirm: 'DISM 可能运行数分钟。确认执行组件清理？' },
  { id: 'shadow-resize', label: '限制卷影副本', description: '将 C 盘系统还原/卷影副本上限设为 5GB', confirm: '这会改变 C 盘系统还原空间上限为 5GB，确认？' },
]

const selectedTargets = computed(() => targets.value.filter((target) => selected.value.has(target.id)))
const selectedBytes = computed(() => selectedTargets.value.reduce((total, target) => total + target.bytes, 0))
const selectedHermes = computed(() => selected.value.has('hermes'))
const safeTargetCount = computed(() => targets.value.filter((target) => target.safe).length)
const busy = computed(() => loading.value || cleaning.value || Boolean(actionBusy.value))
const analysisRows = computed(() => {
  const rows = []
  const visit = (nodes, depth) => {
    for (const node of nodes ?? []) {
      rows.push({ path: node.path, bytes: node.bytes, depth })
      visit(node.children, depth + 1)
    }
  }
  visit(analysis.value?.folders, 0)
  return rows
})

function formatBytes(bytes) {
  if (!bytes || bytes < 1024) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const exponent = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / 1024 ** exponent).toFixed(exponent >= 3 ? 2 : 1)} ${units[exponent]}`
}

function formatPath(path) {
  if (!path) return ''
  return path.replace(/^C:\\Users\\[^\\]+/i, '~')
}

async function copyAnalysis() {
  if (!analysisRows.value.length) return

  const lines = analysisRows.value.map(({ path, bytes, depth }) => {
    return `${'  '.repeat(depth)}${path}\t${formatBytes(bytes)}`
  })
  const text = ['C 盘 1GB 以上文件夹分析结果', '阈值：1 GB', '', ...lines].join('\n')

  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
    } else {
      const textarea = document.createElement('textarea')
      textarea.value = text
      textarea.style.position = 'fixed'
      textarea.style.opacity = '0'
      document.body.appendChild(textarea)
      textarea.focus()
      textarea.select()
      const copied = document.execCommand('copy')
      textarea.remove()
      if (!copied) throw new Error('clipboard unavailable')
    }
    analysisCopyStatus.value = `已复制 ${analysisRows.value.length} 项`
    window.setTimeout(() => {
      analysisCopyStatus.value = ''
    }, 2400)
  } catch {
    analysisCopyStatus.value = '复制失败，请重试'
  }
}

async function openAnalysisFolder(path) {
  if (!path || analysisOpenPath.value) return

  analysisOpenPath.value = path
  clearMessages()
  try {
    await invoke('open_path', { path })
    notice.value = `已打开：${path}`
  } catch (err) {
    error.value = `无法打开文件夹：${String(err)}`
  } finally {
    analysisOpenPath.value = ''
  }
}

function setDefaultSelection() {
  selected.value = new Set(targets.value.filter((target) => target.safe).map((target) => target.id))
}

function toggleTarget(id) {
  const next = new Set(selected.value)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  selected.value = next
}

function clearMessages() {
  error.value = ''
  notice.value = ''
}

function openView(view) {
  activeView.value = view
  clearMessages()
}

async function scan() {
  loading.value = true
  clearMessages()
  try {
    const result = await invoke('scan_cleanup')
    targets.value = result.targets ?? []
    freeBytes.value = result.free_bytes ?? 0
    setDefaultSelection()
  } catch (err) {
    error.value = `无法扫描 C 盘：${String(err)}`
  } finally {
    loading.value = false
  }
}

async function clean() {
  if (!selected.value.size || cleaning.value) return
  if (selectedHermes.value && !window.confirm('Hermes 整个本地数据目录将被删除，包含配置和登录信息。确定继续吗？')) return

  cleaning.value = true
  activeView.value = 'home'
  clearMessages()
  lastAction.value = null
  try {
    lastReport.value = await invoke('clean_targets', {
      targetIds: [...selected.value],
      runWindowsCleanup: runWindowsCleanup.value,
    })
    await scan()
    notice.value = '清理完成，扫描结果已刷新。'
  } catch (err) {
    error.value = `清理失败：${String(err)}`
  } finally {
    cleaning.value = false
  }
}

async function runTool(tool) {
  if (tool.confirm && !window.confirm(tool.confirm)) return
  activeView.value = 'tools'
  actionBusy.value = tool.id
  clearMessages()
  lastAction.value = null
  try {
    const result = await invoke('run_maintenance', { action: tool.id })
    lastAction.value = result
    if (result.success) {
      if (['browser-cache', 'vscode-cache', 'nvidia-cache', 'developer-cache', 'pycache', 'windows-cleanup'].includes(tool.id)) await scan()
    }
  } catch (err) {
    error.value = `${tool.label}失败：${String(err)}`
  } finally {
    actionBusy.value = ''
  }
}

async function setPagefile() {
  const warning = pagefileMode.value === 'none'
    ? '这会关闭虚拟内存，可能导致内存不足或程序崩溃。确认继续？'
    : pagefileMode.value === 'custom'
      ? `将把 ${pagefileDrive.value}: 页面文件设置为 ${pagefileInitial.value}–${pagefileMaximum.value} MB，确认？`
      : '将页面文件恢复为系统自动管理，确认？'
  if (!window.confirm(warning)) return
  activeView.value = 'tools'
  actionBusy.value = 'pagefile'
  clearMessages()
  try {
    lastAction.value = await invoke('set_pagefile', {
      mode: pagefileMode.value,
      drive: pagefileDrive.value,
      initialMb: Number(pagefileInitial.value),
      maxMb: Number(pagefileMaximum.value),
    })
  } catch (err) {
    error.value = `虚拟内存设置失败：${String(err)}`
  } finally {
    actionBusy.value = ''
  }
}

async function analyzeDisk() {
  activeView.value = 'analysis'
  actionBusy.value = 'disk-analysis'
  clearMessages()
  analysis.value = null
  analysisCopyStatus.value = ''
  analysisOpenPath.value = ''
  try {
    analysis.value = await invoke('analyze_disk')
    notice.value = '1GB 以上文件夹分析完成。'
  } catch (err) {
    error.value = `磁盘分析失败：${String(err)}`
  } finally {
    actionBusy.value = ''
  }
}

onMounted(scan)
</script>

<template>
  <div class="app-shell">
    <header class="topbar">
      <div class="brand-lockup">
        <div class="brand-mark">CS</div>
        <div><div class="brand-name">Clean Safe Plus</div><div class="brand-caption">Windows 空间管理</div></div>
      </div>
      <div class="search-box"><img class="search-mark" src="/icons/search.webp" alt="" /><span>搜索管家功能，例如：快速清理、磁盘分析</span></div>
      <div class="topbar-meta"><span class="status-dot"></span><span>本机 · C 盘</span><button class="icon-button" title="重新扫描" :disabled="busy" @click="scan"><img src="/icons/refresh.webp" alt="" /></button></div>
    </header>

    <div class="app-body">
      <aside class="sidebar">
        <nav class="side-nav" aria-label="主导航">
          <button v-for="item in navItems" :key="item.id" class="side-item" :class="{ active: activeView === item.id }" @click="openView(item.id)">
            <span class="side-mark" aria-hidden="true"><img :src="`/icons/${item.icon}.webp`" alt="" /></span><span class="side-label">{{ item.label }}</span><small>{{ item.hint }}</small>
          </button>
        </nav>
        <div class="sidebar-foot"><span class="side-status-dot"></span><span>安全模式</span></div>
      </aside>

      <main class="dashboard-main">
        <div v-if="error" class="message-bar message-error">{{ error }}</div>
        <div v-if="notice" class="message-bar message-success">{{ notice }}</div>

        <template v-if="activeView === 'home'">
          <div class="home-view">
            <section class="home-top">
              <div class="hero-block">
                <div class="eyebrow">电脑 · C 盘空间</div>
                <h1>让 C 盘保持轻盈。</h1>
                <p class="hero-copy">先扫描，再选择。安全清理缓存，同时保留桌面、下载和个人文档。</p>
                <div class="hero-points"><span>✓ 保留个人文件</span><span>✓ 占用文件自动跳过</span></div>
                <div class="hero-buttons"><button class="primary-button" :disabled="busy || !selected.size" @click="clean"><span v-if="cleaning" class="button-loader"></span><span v-else>清理加速</span><span v-if="!cleaning" class="button-arrow">→</span></button><button class="hero-secondary" @click="openView('tools')">更多工具</button></div>
              </div>

              <div class="summary-stack">
                <section class="dashboard-card device-card">
                  <div class="card-heading"><span>设备状态</span><span class="card-chevron">›</span></div>
                  <div class="device-metrics"><div><span class="metric-label">当前可用空间</span><strong class="metric-primary">{{ formatBytes(freeBytes) }}</strong><small>C 盘</small></div><div><span class="metric-label">可清理项目</span><strong>{{ safeTargetCount }}</strong><small>项</small></div><div><span class="metric-label">已选择空间</span><strong>{{ formatBytes(selectedBytes) }}</strong><small>待处理</small></div></div>
                </section>
                <div class="summary-row"><section class="dashboard-card mini-card"><div class="card-heading"><span>扫描状态</span><span class="card-chevron">›</span></div><strong>{{ loading ? '扫描中' : '已就绪' }}</strong><small>{{ loading ? '正在读取 C 盘' : '可以开始清理' }}</small></section><section class="dashboard-card mini-card"><div class="card-heading"><span>清理策略</span><span class="card-chevron">›</span></div><strong>安全模式</strong><small>保留个人文件</small></section></div>
                <section class="dashboard-card cleanup-card"><div class="card-heading"><span>本次清理</span><span class="card-chevron">›</span></div><div class="cleanup-line"><span>已选择项目</span><strong>{{ selectedTargets.length }} 项</strong></div><div class="cleanup-line"><span>预计释放空间</span><strong class="accent-value">{{ formatBytes(selectedBytes) }}</strong></div></section>
              </div>
            </section>

            <section class="home-bottom">
              <section class="panel target-card">
                <div class="panel-heading"><div><div class="section-kicker">CLEANUP TARGETS</div><h2>清理项目</h2></div><span class="selection-count">{{ selected.size }} 已选</span></div>
                <div v-if="loading" class="empty-state"><div class="loader"></div><span>正在扫描 C 盘…</span></div>
                <div v-else-if="!targets.length" class="empty-state"><span class="empty-icon" aria-hidden="true"><img src="/icons/empty.webp" alt="" /></span><span>没有发现可清理项目</span></div>
                <div v-else class="target-list"><label v-for="target in targets" :key="target.id" class="target-row" :class="{ selected: selected.has(target.id), danger: !target.safe }"><input type="checkbox" :checked="selected.has(target.id)" @change="toggleTarget(target.id)" /><span class="checkmark">✓</span><span class="target-icon" :class="target.safe ? 'safe-icon' : 'danger-icon'" aria-hidden="true"><img :src="`/icons/${target.safe ? 'cleanup' : 'warning'}.webp`" alt="" /></span><span class="target-main"><span class="target-label">{{ target.label }}</span><span class="target-path">{{ formatPath(target.path) }}</span><span v-if="!target.safe" class="danger-note">整目录删除 · 配置和登录信息会丢失</span></span><span class="target-size">{{ formatBytes(target.bytes) }}</span></label></div>
                <div class="panel-footnote"><span class="shield">⌾</span> 正在使用的文件会自动跳过，不会强制结束进程。</div>
              </section>

              <section class="panel shortcuts-card"><div class="panel-heading"><div><div class="section-kicker">QUICK ACCESS</div><h2>常用入口</h2></div><span class="selection-count">按需使用</span></div><button class="shortcut-row" @click="openView('tools')"><span class="shortcut-mark" aria-hidden="true"><img src="/icons/tools.webp" alt="" /></span><span><strong>系统工具</strong><small>服务、网络、休眠和页面文件</small></span><span class="shortcut-arrow">→</span></button><button class="shortcut-row" @click="openView('analysis')"><span class="shortcut-mark" aria-hidden="true"><img src="/icons/disk.webp" alt="" /></span><span><strong>磁盘分析</strong><small>定位 1GB 以上的大文件夹</small></span><span class="shortcut-arrow">→</span></button><button class="shortcut-row" :disabled="busy" @click="scan"><span class="shortcut-mark" aria-hidden="true"><img src="/icons/refresh.webp" alt="" /></span><span><strong>重新扫描</strong><small>刷新可清理项目和可用空间</small></span><span class="shortcut-arrow">↻</span></button><p class="safe-caption"><span aria-hidden="true">◈</span> 只处理选中的缓存和临时文件</p></section>
            </section>
            <section v-if="lastReport" class="result-strip"><span class="result-icon">✓</span><div><strong>上次清理已完成</strong><span>释放约 {{ formatBytes(lastReport.freed_bytes) }}，C 盘可用空间已刷新。</span></div></section>
          </div>
        </template>

        <template v-else-if="activeView === 'tools'">
          <section class="panel workspace-view">
            <div class="workspace-heading"><div><div class="section-kicker">SYSTEM TOOLS</div><h2>系统工具</h2><p class="panel-subtitle">高级清理、系统维护和页面文件配置。</p></div><button class="back-button" @click="openView('home')">返回概览</button></div>
            <div class="tools-body">
              <section v-if="lastAction" class="action-result" :class="lastAction.success ? 'action-result-success' : 'action-result-failure'"><div class="action-result-heading"><span class="action-status-icon">{{ lastAction.success ? '✓' : '!' }}</span><div><strong>{{ lastAction.message }}</strong><small>最近一次高级操作</small></div></div><div v-if="lastAction.details?.length" class="action-result-list"><span v-for="detail in lastAction.details" :key="detail">{{ detail }}</span></div><div v-if="lastAction.warnings?.length" class="action-result-list action-result-warning"><span v-for="warning in lastAction.warnings" :key="warning">{{ warning }}</span></div></section>
              <div class="tool-section"><div class="tool-section-title">应用与开发缓存</div><div class="tool-grid"><button v-for="tool in cleanupTools" :key="tool.id" class="tool-button" :disabled="busy" @click="runTool(tool)"><span class="tool-button-main"><strong>{{ tool.label }}</strong><small>{{ tool.description }}</small></span><span class="tool-arrow">{{ actionBusy === tool.id ? '…' : '→' }}</span></button></div></div>
              <div class="tool-section"><div class="tool-section-title">系统与网络</div><div class="tool-grid"><button v-for="tool in systemTools" :key="tool.id" class="tool-button tool-button-warning" :disabled="busy" @click="runTool(tool)"><span class="tool-button-main"><strong>{{ tool.label }}</strong><small>{{ tool.description }}</small></span><span class="tool-arrow">{{ actionBusy === tool.id ? '…' : '→' }}</span></button></div></div>
              <div class="tool-section"><div class="tool-section-title">虚拟内存（页面文件）</div><div class="pagefile-controls"><label><span>模式</span><select v-model="pagefileMode" :disabled="busy"><option value="auto">系统自动管理</option><option value="custom">自定义大小</option><option value="none">不使用页面文件</option></select></label><label v-if="pagefileMode === 'custom'"><span>磁盘</span><input v-model="pagefileDrive" maxlength="2" /></label><label v-if="pagefileMode === 'custom'"><span>初始 MB</span><input v-model.number="pagefileInitial" type="number" min="1" /></label><label v-if="pagefileMode === 'custom'"><span>最大 MB</span><input v-model.number="pagefileMaximum" type="number" min="1" /></label><button class="compact-button" :disabled="busy" @click="setPagefile">{{ actionBusy === 'pagefile' ? '处理中…' : '应用设置' }}</button></div></div>
            </div>
          </section>
        </template>

        <template v-else>
          <section class="panel workspace-view analysis-view">
            <div class="workspace-heading"><div><div class="section-kicker">DISK ANALYSIS</div><h2>磁盘分析</h2><p class="panel-subtitle">从 C 盘根目录开始，逐层展开 1GB 以上的文件夹。</p></div><button class="back-button" @click="openView('home')">返回概览</button></div>
            <div class="analysis-toolbar"><div class="analysis-actions"><button class="primary-button analysis-button" :disabled="busy" @click="analyzeDisk">{{ actionBusy === 'disk-analysis' ? '正在分析…' : '分析 1GB+ 文件夹' }}</button><button class="hero-secondary analysis-copy-button" :disabled="busy || !analysisRows.length" @click="copyAnalysis">一键复制结果</button></div><span class="analysis-threshold">阈值：1 GB</span><span v-if="analysisCopyStatus" class="analysis-copy-status" aria-live="polite">{{ analysisCopyStatus }}</span></div>
            <p class="analysis-note">只显示 ≥1GB 的文件夹；每个分支会继续递归，直到下一层全部小于 1GB。每个目录只扫描一次。</p>
            <div v-if="analysisRows.length" class="analysis-tree"><div v-for="entry in analysisRows" :key="entry.path" class="analysis-tree-row"><span class="analysis-tree-path" :style="{ paddingLeft: `${entry.depth * 22}px` }"><span class="analysis-branch" :class="{ 'analysis-branch-root': entry.depth === 0 }"></span>{{ entry.path }}</span><b>{{ formatBytes(entry.bytes) }}</b><button class="analysis-open-button" :disabled="busy || Boolean(analysisOpenPath)" title="在 Windows 资源管理器中打开" @click="openAnalysisFolder(entry.path)">{{ analysisOpenPath === entry.path ? '打开中…' : '打开' }}</button></div></div><div v-else class="analysis-empty">点击“分析 1GB+ 文件夹”开始定位占用空间。</div>
          </section>
        </template>
      </main>
    </div>
    <footer class="footer">Clean Safe Plus <span>·</span> Tauri 2.11+ / Vue 3.5</footer>
  </div>
</template>
