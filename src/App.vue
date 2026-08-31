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
  actionBusy.value = 'disk-analysis'
  clearMessages()
  analysis.value = null
  try {
    analysis.value = await invoke('analyze_disk')
    notice.value = '磁盘分析完成。'
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
        <div>
          <div class="brand-name">Clean Safe Plus</div>
          <div class="brand-caption">Windows 空间管理</div>
        </div>
      </div>
      <div class="topbar-meta">
        <span class="status-dot"></span>
        <span>本机 · C 盘</span>
        <button class="icon-button" title="重新扫描" :disabled="busy" @click="scan">↻</button>
      </div>
    </header>

    <main class="page-content">
      <section class="hero-row">
        <div>
          <div class="eyebrow">安全清理控制台</div>
          <h1>让 C 盘保持轻盈。</h1>
          <p class="hero-copy">先扫描，再选择。清理缓存，也可以处理系统维护和网络修复。</p>
        </div>
        <div class="free-space-card">
          <div class="free-space-label">当前可用空间</div>
          <div class="free-space-value">{{ formatBytes(freeBytes) }}</div>
          <div class="free-space-bar"><span :style="{ width: `${Math.min(Math.max(freeBytes / (128 * 1024 ** 3) * 100, 4), 100)}%` }"></span></div>
          <div class="free-space-foot">扫描自本机 C 盘</div>
        </div>
      </section>

      <div v-if="error" class="banner banner-error">{{ error }}</div>
      <div v-if="notice" class="banner banner-success">{{ notice }}</div>

      <section class="stats-row">
        <div class="stat-card"><span class="stat-icon violet">◎</span><div><span class="stat-label">可清理项目</span><strong>{{ safeTargetCount }}</strong></div></div>
        <div class="stat-card"><span class="stat-icon blue">↘</span><div><span class="stat-label">已选择空间</span><strong>{{ formatBytes(selectedBytes) }}</strong></div></div>
        <div class="stat-card"><span class="stat-icon green">✓</span><div><span class="stat-label">默认策略</span><strong>保留个人文件</strong></div></div>
      </section>

      <section class="workspace-grid">
        <div class="panel targets-panel">
          <div class="panel-heading">
            <div><div class="section-kicker">CLEANUP TARGETS</div><h2>清理项目</h2></div>
            <span class="selection-count">{{ selected.size }} 已选</span>
          </div>

          <div v-if="loading" class="empty-state"><div class="loader"></div><span>正在扫描 C 盘…</span></div>
          <div v-else-if="!targets.length" class="empty-state"><span class="empty-icon">◌</span><span>没有发现可清理项目</span></div>
          <div v-else class="target-list">
            <label v-for="target in targets" :key="target.id" class="target-row" :class="{ selected: selected.has(target.id), danger: !target.safe }">
              <input type="checkbox" :checked="selected.has(target.id)" @change="toggleTarget(target.id)" />
              <span class="checkmark">✓</span>
              <span class="target-icon" :class="target.safe ? 'safe-icon' : 'danger-icon'">{{ target.safe ? '✦' : '!' }}</span>
              <span class="target-main"><span class="target-label">{{ target.label }}</span><span class="target-path">{{ formatPath(target.path) }}</span><span v-if="!target.safe" class="danger-note">整目录删除 · 配置和登录信息会丢失</span></span>
              <span class="target-size">{{ formatBytes(target.bytes) }}</span>
            </label>
          </div>
          <div class="panel-footnote"><span class="shield">⌾</span> 正在使用的文件会自动跳过，不会强制结束进程。</div>
        </div>

        <aside class="panel action-panel">
          <div class="section-kicker">READY TO CLEAN</div>
          <h2>准备开始</h2>
          <p class="action-copy">已选择 {{ selectedTargets.length }} 个项目，共 {{ formatBytes(selectedBytes) }}。</p>
          <label class="option-row"><input v-model="runWindowsCleanup" type="checkbox" /><span class="option-check">✓</span><span><strong>运行 Windows 磁盘清理</strong><small>清理系统认可的临时项目和缩略图</small></span></label>
          <div v-if="selectedHermes" class="warning-box"><span class="warning-icon">!</span><span>Hermes 会被整目录删除。它的本地配置、登录信息和缓存都会清除。</span></div>
          <button class="primary-button" :disabled="busy || !selected.size" @click="clean"><span v-if="cleaning" class="button-loader"></span><span v-else>立即清理</span><span v-if="!cleaning" class="button-arrow">→</span></button>
          <button class="secondary-button" :disabled="busy" @click="scan">重新扫描</button>
          <p class="safe-caption"><span>◈</span> 安全模式 · 不触碰桌面、下载和文档</p>
        </aside>
      </section>

      <section class="panel tools-panel">
        <div class="panel-heading"><div><div class="section-kicker">ADVANCED MAINTENANCE</div><h2>更多工具</h2><p class="panel-subtitle">按用途分组的高级操作；执行前会先确认，结果显示在下方。</p></div><span class="selection-count">需谨慎操作</span></div>
        <div class="tool-section"><div class="tool-section-title">应用与开发缓存</div><div class="tool-grid"><button v-for="tool in cleanupTools" :key="tool.id" class="tool-button" :disabled="busy" @click="runTool(tool)"><span class="tool-button-main"><strong>{{ tool.label }}</strong><small>{{ tool.description }}</small></span><span class="tool-arrow">{{ actionBusy === tool.id ? '…' : '→' }}</span></button></div></div>
        <div class="tool-section"><div class="tool-section-title">系统与网络</div><div class="tool-grid"><button v-for="tool in systemTools" :key="tool.id" class="tool-button tool-button-warning" :disabled="busy" @click="runTool(tool)"><span class="tool-button-main"><strong>{{ tool.label }}</strong><small>{{ tool.description }}</small></span><span class="tool-arrow">{{ actionBusy === tool.id ? '…' : '→' }}</span></button></div></div>

        <div class="tool-section pagefile-section">
          <div class="tool-section-title">虚拟内存（页面文件）</div>
          <div class="pagefile-controls">
            <label><span>模式</span><select v-model="pagefileMode" :disabled="busy"><option value="auto">系统自动管理</option><option value="custom">自定义大小</option><option value="none">不使用页面文件</option></select></label>
            <label v-if="pagefileMode === 'custom'"><span>磁盘</span><input v-model="pagefileDrive" maxlength="2" /></label>
            <label v-if="pagefileMode === 'custom'"><span>初始 MB</span><input v-model.number="pagefileInitial" type="number" min="1" /></label>
            <label v-if="pagefileMode === 'custom'"><span>最大 MB</span><input v-model.number="pagefileMaximum" type="number" min="1" /></label>
            <button class="compact-button" :disabled="busy" @click="setPagefile">{{ actionBusy === 'pagefile' ? '处理中…' : '应用设置' }}</button>
          </div>
        </div>

        <div class="tool-section analysis-section">
          <div class="tool-section-title">磁盘分析</div>
          <button class="secondary-button analysis-button" :disabled="busy" @click="analyzeDisk">{{ actionBusy === 'disk-analysis' ? '正在分析…' : '分析 C 盘大目录' }}</button>
          <div v-if="analysis" class="analysis-grid">
            <div><strong>重点目录</strong><div v-for="entry in analysis.focus" :key="entry.path" class="analysis-row"><span>{{ entry.path }}</span><b>{{ formatBytes(entry.bytes) }}</b></div></div>
            <div><strong>C 盘 Top 12</strong><div v-for="entry in analysis.top" :key="entry.path" class="analysis-row"><span>{{ entry.path }}</span><b>{{ formatBytes(entry.bytes) }}</b></div></div>
          </div>
        </div>
        <section v-if="lastAction" class="action-result" :class="lastAction.success ? 'action-result-success' : 'action-result-failure'">
          <div class="action-result-heading"><span class="action-status-icon">{{ lastAction.success ? '✓' : '!' }}</span><div><strong>{{ lastAction.message }}</strong><small>最近一次高级操作</small></div></div>
          <div v-if="lastAction.details?.length" class="action-result-list"><span v-for="detail in lastAction.details" :key="detail">{{ detail }}</span></div>
          <div v-if="lastAction.warnings?.length" class="action-result-list action-result-warning"><span v-for="warning in lastAction.warnings" :key="warning">{{ warning }}</span></div>
        </section>
      </section>

      <section v-if="lastReport" class="result-strip"><span class="result-icon">✓</span><div><strong>上次清理已完成</strong><span>释放约 {{ formatBytes(lastReport.freed_bytes) }}，C 盘可用空间已刷新。</span></div></section>
    </main>
    <footer class="footer">Clean Safe Plus <span>·</span> Tauri 2.11+ / Vue 3.5</footer>
  </div>
</template>
