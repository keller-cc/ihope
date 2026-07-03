const $ = (id) => document.getElementById(id);

const PAGE_SIZE = 20;

const SORTABLE_COLUMNS = [
  { key: 'username', label: '用户名' },
  { key: 'email', label: '邮箱' },
  { key: 'device_count', label: '设备' },
  { key: 'created_at', label: '注册时间' },
];

const SORT_LABELS = Object.fromEntries(SORTABLE_COLUMNS.map((c) => [c.key, c.label]));

const state = {
  q: '',
  offset: 0,
  total: 0,
  detailUserId: '',
  sort: '',
  order: '',
};

const storage = {
  get apiBase() {
    return localStorage.getItem('ihope_admin_api') || window.location.origin;
  },
  set apiBase(v) {
    localStorage.setItem('ihope_admin_api', v.replace(/\/+$/, ''));
  },
  get secret() {
    return sessionStorage.getItem('ihope_admin_secret') || '';
  },
  set secret(v) {
    if (v) sessionStorage.setItem('ihope_admin_secret', v);
    else sessionStorage.removeItem('ihope_admin_secret');
  },
};

function show(el, visible) {
  el.classList.toggle('hidden', !visible);
}

async function api(path, options = {}) {
  const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
  if (storage.secret) headers.Authorization = `Bearer ${storage.secret}`;
  const res = await fetch(`${storage.apiBase}${path}`, { ...options, headers });
  if (!res.ok) {
    let msg = res.statusText;
    try {
      const body = await res.json();
      msg = body.message || body.error || msg;
    } catch (_) {}
    throw new Error(msg);
  }
  if (res.status === 204) return null;
  return res.json();
}

async function login() {
  const secret = $('admin-secret').value;
  const base = $('api-base').value.trim();
  if (base) storage.apiBase = base;
  if (!secret) {
    $('login-error').textContent = '请输入管理密钥';
    show($('login-error'), true);
    return;
  }
  storage.secret = secret;
  $('login-btn').disabled = true;
  show($('login-error'), false);
  try {
    state.q = '';
    state.offset = 0;
    state.sort = '';
    state.order = '';
    $('search-input').value = '';
    await loadDashboard();
  } catch (e) {
    storage.secret = '';
    $('login-error').textContent = e.message;
    show($('login-error'), true);
  } finally {
    $('login-btn').disabled = false;
  }
}

function fmtTime(iso) {
  try {
    return new Date(iso).toLocaleString('zh-CN');
  } catch (_) {
    return iso;
  }
}

function fmtUptime(sec) {
  if (sec < 60) return `${sec} 秒`;
  if (sec < 3600) return `${Math.floor(sec / 60)} 分钟`;
  return `${Math.floor(sec / 3600)} 小时 ${Math.floor((sec % 3600) / 60)} 分`;
}

function sessionCell(d) {
  switch (d.session_state) {
    case 'online':
      return '<span class="badge ok">在线</span>';
    case 'logged_in':
      return '<span class="badge idle">已登录</span>';
    case 'idle':
      return '<span class="badge warn">闲置</span>';
    default:
      return '—';
  }
}

function renderService(stats) {
  const svc = stats.service || {};
  const db = svc.database || {};
  const pushLines = Object.entries(stats.push_by_platform || {})
    .map(([p, n]) => `${p}: ${n}`)
    .join(' · ') || '无';
  $('service-panel').innerHTML = `
    <h2>服务状态</h2>
    <div class="service-grid">
      <div class="stat"><span>API</span><strong class="${svc.ok ? 'ok-text' : 'bad-text'}">${svc.ok ? '正常' : '异常'}</strong></div>
      <div class="stat"><span>数据库</span><strong class="${db.ok ? 'ok-text' : 'bad-text'}">${db.ok ? '已连接' : '不可用'}</strong></div>
      <div class="stat"><span>运行时间</span><strong>${fmtUptime(svc.uptime_s || 0)}</strong></div>
      <div class="stat"><span>版本</span><strong>${escapeHtml(svc.version || '—')}</strong></div>
      <div class="stat wide"><span>推送 token</span><strong>${stats.push_tokens || 0}</strong><small>${escapeHtml(pushLines)}</small></div>
      <div class="stat"><span>Refresh 闲置</span><strong>${stats.refresh_token_ttl_days ? stats.refresh_token_ttl_days + ' 天' : '不限'}</strong></div>
    </div>`;
}

async function loadStats() {
  const stats = await api('/api/admin/stats');
  $('stats').innerHTML = `
    <div class="stat"><span>用户总数</span><strong>${stats.users_total}</strong></div>
    <div class="stat"><span>已禁用</span><strong>${stats.users_disabled}</strong></div>`;
  renderService(stats);
}

async function loadDashboard() {
  show($('login-panel'), false);
  show($('dashboard'), true);
  show($('list-error'), false);
  try {
    await loadStats();
    await loadUsers();
  } catch (e) {
    $('list-error').textContent = e.message;
    show($('list-error'), true);
    if (String(e.message).match(/unauthorized|403|admin/i)) logout();
  }
}

function sortArrow(key) {
  if (state.sort !== key) return '';
  if (state.order === 'asc') return ' ↑';
  if (state.order === 'desc') return ' ↓';
  return '';
}

function sortMetaText() {
  if (!state.sort) return '默认（用户名升序）';
  const dir = state.order === 'desc' ? '降序' : '升序';
  return `${SORT_LABELS[state.sort] || state.sort} ${dir}`;
}

function renderSortHeaders() {
  const row = $('users-thead').querySelector('tr');
  const cols = SORTABLE_COLUMNS.map(
    (c) =>
      `<th><button type="button" class="sort-btn${state.sort === c.key ? ' active' : ''}" data-sort="${c.key}" title="升序 → 降序 → 取消">${c.label}${sortArrow(c.key)}</button></th>`,
  ).join('');
  row.innerHTML = `${cols}<th>状态</th><th></th>`;
  row.querySelectorAll('.sort-btn').forEach((btn) => {
    btn.onclick = () => setSort(btn.dataset.sort);
  });
}

function setSort(key) {
  if (state.sort !== key) {
    state.sort = key;
    state.order = 'asc';
  } else if (state.order === 'asc') {
    state.order = 'desc';
  } else if (state.order === 'desc') {
    state.sort = '';
    state.order = '';
  } else {
    state.sort = key;
    state.order = 'asc';
  }
  state.offset = 0;
  loadUsers().catch((e) => {
    $('list-error').textContent = e.message;
    show($('list-error'), true);
  });
}

async function loadUsers() {
  const params = new URLSearchParams({
    limit: String(PAGE_SIZE),
    offset: String(state.offset),
  });
  if (state.q) params.set('q', state.q);
  if (state.sort) {
    params.set('sort', state.sort);
    params.set('order', state.order || 'asc');
  }
  const list = await api(`/api/admin/users?${params}`);
  state.total = list.total || 0;
  state.sort = list.sort || '';
  state.order = list.order || '';
  renderSortHeaders();
  const from = state.total === 0 ? 0 : state.offset + 1;
  const to = Math.min(state.offset + PAGE_SIZE, state.total);
  const sortText = sortMetaText();
  $('list-meta').textContent = state.q
    ? `搜索「${state.q}」共 ${state.total} 人 · ${sortText}`
    : `共 ${state.total} 人 · ${sortText}`;
  $('page-info').textContent = state.total ? `${from}–${to} / ${state.total}` : '无数据';
  $('prev-page').disabled = state.offset <= 0;
  $('next-page').disabled = state.offset + PAGE_SIZE >= state.total;

  const tbody = $('users-body');
  tbody.innerHTML = '';
  for (const u of list.users || []) {
    const disabled = !!u.disabled_at;
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><button type="button" class="link-btn" data-user-id="${escapeHtml(u.id)}">${escapeHtml(u.username)}</button></td>
      <td>${escapeHtml(u.email)}</td>
      <td>${u.device_count ?? 0}</td>
      <td>${fmtTime(u.created_at)}</td>
      <td><span class="badge ${disabled ? 'off' : 'ok'}">${disabled ? '已禁用' : '正常'}</span></td>
      <td class="actions"></td>`;
    const actions = tr.querySelector('.actions');
    const detailBtn = document.createElement('button');
    detailBtn.type = 'button';
    detailBtn.className = 'secondary';
    detailBtn.textContent = '详情';
    detailBtn.onclick = () => openUserDetail(u.id);
    actions.appendChild(detailBtn);
    const toggleBtn = document.createElement('button');
    toggleBtn.type = 'button';
    toggleBtn.className = disabled ? 'secondary' : '';
    toggleBtn.textContent = disabled ? '启用' : '禁用';
    toggleBtn.onclick = () => toggleUser(u.id, disabled);
    actions.appendChild(toggleBtn);
    tbody.appendChild(tr);
  }
  tbody.querySelectorAll('.link-btn').forEach((btn) => {
    btn.onclick = () => openUserDetail(btn.dataset.userId);
  });
}

async function openUserDetail(userId) {
  state.detailUserId = userId;
  const u = await api(`/api/admin/users/${encodeURIComponent(userId)}`);
  const disabled = !!u.disabled_at;
  let devicesHtml = '<p class="hint">暂无设备记录</p>';
  if (u.devices?.length) {
    devicesHtml = `<table class="detail-table"><thead><tr>
      <th>设备名</th><th>平台</th><th>最后活跃</th><th>连接</th><th>推送</th><th></th>
    </tr></thead><tbody>${
      u.devices.map((d) => `<tr>
        <td>${escapeHtml(d.device_name || d.device_id.slice(0, 8) + '…')}</td>
        <td>${escapeHtml(d.platform || '—')}</td>
        <td>${fmtTime(d.last_active_at)}</td>
        <td>${sessionCell(d)}</td>
        <td>${d.has_push ? '已注册' : '—'}</td>
        <td>${d.has_session ? `<button type="button" class="secondary kick-btn" data-device="${escapeHtml(d.device_id)}">踢下线</button>` : ''}</td>
      </tr>`).join('')
    }</tbody></table>
    <p class="hint">「在线」= WebSocket 连接；「已登录」= refresh 有效且近期活跃；「闲置」= 库中仍有 token 但超过有效期未活跃。退出 App 会清除服务端 token。</p>`;
  }
  $('detail-title').textContent = u.username;
  $('detail-body').innerHTML = `
    <dl class="detail-dl">
      <dt>邮箱</dt><dd>${escapeHtml(u.email)}</dd>
      <dt>用户 ID</dt><dd><code>${escapeHtml(u.id)}</code></dd>
      <dt>注册时间</dt><dd>${fmtTime(u.created_at)}</dd>
      <dt>状态</dt><dd><span class="badge ${disabled ? 'off' : 'ok'}">${disabled ? '已禁用' : '正常'}</span></dd>
      <dt>设备数</dt><dd>${u.device_count ?? 0}</dd>
    </dl>
    <h3>设备</h3>
    ${devicesHtml}`;
  $('detail-body').querySelectorAll('.kick-btn').forEach((btn) => {
    btn.onclick = async () => {
      if (!confirm('踢该设备下线？')) return;
      await api(`/api/admin/users/${encodeURIComponent(userId)}/devices/${encodeURIComponent(btn.dataset.device)}/kick`, { method: 'POST' });
      await openUserDetail(userId);
      await loadUsers();
    };
  });
  if (!$('user-dialog').open) $('user-dialog').showModal();
}

async function refreshDetail() {
  if (!state.detailUserId) return;
  await openUserDetail(state.detailUserId);
}

async function toggleUser(id, disabled) {
  if (!disabled && !confirm('确定禁用该用户？其所有会话将立即失效。')) return;
  await api(`/api/admin/users/${id}/${disabled ? 'enable' : 'disable'}`, { method: 'POST' });
  await loadDashboard();
}

function logout() {
  storage.secret = '';
  state.detailUserId = '';
  $('admin-secret').value = '';
  show($('dashboard'), false);
  show($('login-panel'), true);
  $('user-dialog').close();
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function runSearch() {
  state.q = $('search-input').value.trim();
  state.offset = 0;
  loadUsers().catch((e) => {
    $('list-error').textContent = e.message;
    show($('list-error'), true);
  });
}

function clearSearch() {
  state.q = '';
  state.offset = 0;
  $('search-input').value = '';
  loadUsers();
}

$('api-base').value = storage.apiBase;
$('login-btn').onclick = login;
$('logout-btn').onclick = logout;
$('refresh-all-btn').onclick = () => loadDashboard();
$('refresh-detail-btn').onclick = () => refreshDetail().catch((e) => alert(e.message));
$('search-btn').onclick = runSearch;
$('clear-search-btn').onclick = clearSearch;
$('search-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') runSearch();
});
$('prev-page').onclick = () => {
  state.offset = Math.max(0, state.offset - PAGE_SIZE);
  loadUsers();
};
$('next-page').onclick = () => {
  if (state.offset + PAGE_SIZE < state.total) {
    state.offset += PAGE_SIZE;
    loadUsers();
  }
};
$('close-detail').onclick = () => {
  state.detailUserId = '';
  $('user-dialog').close();
};

if (storage.secret) {
  loadDashboard().catch(() => logout());
}
