const $ = (id) => document.getElementById(id);

const storage = {
  get apiBase() {
    return localStorage.getItem('ihope_admin_api') || window.location.origin;
  },
  set apiBase(v) {
    localStorage.setItem('ihope_admin_api', v.replace(/\/+$/, ''));
  },
  get token() {
    return sessionStorage.getItem('ihope_admin_token') || '';
  },
  set token(v) {
    if (v) sessionStorage.setItem('ihope_admin_token', v);
    else sessionStorage.removeItem('ihope_admin_token');
  },
};

function show(el, visible) {
  el.classList.toggle('hidden', !visible);
}

async function api(path, options = {}) {
  const headers = { 'Content-Type': 'application/json', ...(options.headers || {}) };
  if (storage.token) headers.Authorization = `Bearer ${storage.token}`;
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
  const email = $('email').value.trim();
  const password = $('password').value;
  const base = $('api-base').value.trim();
  if (base) storage.apiBase = base;
  $('login-btn').disabled = true;
  show($('login-error'), false);
  try {
    const deviceId = localStorage.getItem('ihope_admin_device') || crypto.randomUUID();
    localStorage.setItem('ihope_admin_device', deviceId);
    const data = await api('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        email,
        password,
        device_id: deviceId,
        device_name: 'Admin Web',
      }),
    });
    storage.token = data.access_token;
    await loadDashboard();
  } catch (e) {
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

async function loadDashboard() {
  show($('login-panel'), false);
  show($('dashboard'), true);
  show($('list-error'), false);
  try {
    const stats = await api('/api/admin/stats');
    $('stats').innerHTML = `
      <div class="stat"><span>用户总数</span><strong>${stats.users_total}</strong></div>
      <div class="stat"><span>已禁用</span><strong>${stats.users_disabled}</strong></div>`;
    const list = await api('/api/admin/users?limit=100');
    const tbody = $('users-body');
    tbody.innerHTML = '';
    for (const u of list.users || []) {
      const tr = document.createElement('tr');
      const disabled = !!u.disabled_at;
      tr.innerHTML = `
        <td>${escapeHtml(u.username)}${u.is_admin ? ' <span class="badge admin">管理员</span>' : ''}</td>
        <td>${escapeHtml(u.email)}</td>
        <td>${fmtTime(u.created_at)}</td>
        <td><span class="badge ${disabled ? 'off' : 'ok'}">${disabled ? '已禁用' : '正常'}</span></td>
        <td></td>`;
      const actionCell = tr.lastElementChild;
      const btn = document.createElement('button');
      btn.className = disabled ? 'secondary' : '';
      btn.textContent = disabled ? '启用' : '禁用';
      btn.onclick = () => toggleUser(u.id, disabled);
      actionCell.appendChild(btn);
      tbody.appendChild(tr);
    }
  } catch (e) {
    $('list-error').textContent = e.message;
    show($('list-error'), true);
    if (e.message.includes('admin') || e.message.includes('403')) {
      logout();
    }
  }
}

async function toggleUser(id, disabled) {
  if (!disabled && !confirm('确定禁用该用户？其所有会话将立即失效。')) return;
  await api(`/api/admin/users/${id}/${disabled ? 'enable' : 'disable'}`, { method: 'POST' });
  await loadDashboard();
}

function logout() {
  storage.token = '';
  show($('dashboard'), false);
  show($('login-panel'), true);
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

$('api-base').value = storage.apiBase;
$('login-btn').onclick = login;
$('logout-btn').onclick = logout;

if (storage.token) {
  loadDashboard().catch(() => logout());
}
