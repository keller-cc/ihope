import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import {
  Button,
  Dialog,
  DialogPlugin,
  Input,
  MessagePlugin,
  Select,
  Table,
} from 'tdesign-react'
import {
  adminApi,
  apiErrorMessage,
  getAdminToken,
  setAdminToken,
  type AdminConversation,
  type AdminDomain,
  type AdminFellowship,
  type AdminGroupDetail,
  type AdminManilaResult,
  type AdminManilaRoom,
  type AdminQQBinding,
  type AdminUser,
} from '@/api'

type AdminTab = 'users' | 'domains' | 'fellowships' | 'qq' | 'conversations' | 'games'

const TAB_ITEMS: { id: AdminTab; label: (n: number) => string }[] = [
  { id: 'users', label: (n) => `用户 (${n})` },
  { id: 'domains', label: (n) => `自治域 (${n})` },
  { id: 'fellowships', label: (n) => `团契 (${n})` },
  { id: 'qq', label: (n) => `QQ 绑定 (${n})` },
  { id: 'conversations', label: (n) => `会话 (${n})` },
  { id: 'games', label: (n) => `游戏 (${n})` },
]

export function AdminPage() {
  const [tokenInput, setTokenInput] = useState(getAdminToken() || '')
  const [authed, setAuthed] = useState(!!getAdminToken())
  const [users, setUsers] = useState<AdminUser[]>([])
  const [conversations, setConversations] = useState<AdminConversation[]>([])
  const [userFilter, setUserFilter] = useState('')
  const [convFilter, setConvFilter] = useState<'all' | 'group' | 'dm'>('all')
  const [groupDetail, setGroupDetail] = useState<AdminGroupDetail | null>(null)
  const [qqBindings, setQqBindings] = useState<AdminQQBinding[]>([])
  const [domains, setDomains] = useState<AdminDomain[]>([])
  const [fellowships, setFellowships] = useState<AdminFellowship[]>([])
  const [qqBotEnabled, setQqBotEnabled] = useState(false)
  const [qqHint, setQqHint] = useState('')
  const [loading, setLoading] = useState(false)
  const [tab, setTab] = useState<AdminTab>('users')
  const [bindDialog, setBindDialog] = useState<{
    username: string
    code: string
    expiresAt: string
    hint: string
  } | null>(null)
  const [domainDraft, setDomainDraft] = useState('')
  const [fellowshipDraft, setFellowshipDraft] = useState({
    code: '',
    name: '',
    domainId: '',
  })
  const [editFellowship, setEditFellowship] = useState<AdminFellowship | null>(null)
  const [passwordDialog, setPasswordDialog] = useState<{
    id: string
    username: string
    password: string
  } | null>(null)
  const [manilaRooms, setManilaRooms] = useState<AdminManilaRoom[]>([])
  const [manilaResults, setManilaResults] = useState<AdminManilaResult[]>([])
  const [manilaMaxAge, setManilaMaxAge] = useState('1h0m0s')

  const fellowshipOptions = fellowships.map((f) => ({
    label: `${f.name || f.code}（${f.domainName}）`,
    value: f.id,
  }))

  const domainOptions = domains.map((d) => ({ label: d.name, value: d.id }))

  const tabCounts: Record<AdminTab, number> = {
    users: users.length,
    domains: domains.length,
    fellowships: fellowships.length,
    qq: qqBindings.length,
    conversations: conversations.length,
    games: manilaRooms.length,
  }

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [u, c, qq, d, f, manilaLive, manilaHist] = await Promise.all([
        adminApi.listUsers(),
        adminApi.listConversations(),
        adminApi.listQQBindings(),
        adminApi.listDomains(),
        adminApi.listFellowships(),
        adminApi.listManilaRooms(),
        adminApi.listManilaResults(50),
      ])
      setUsers(u.users)
      setConversations(c.conversations)
      setQqBindings(qq.bindings || [])
      setQqBotEnabled(!!qq.botEnabled)
      setQqHint(qq.botAddHint || '')
      setDomains(d.domains || [])
      setFellowships(f.fellowships || [])
      setManilaRooms(manilaLive.rooms || [])
      setManilaMaxAge(manilaLive.maxAge || '1h0m0s')
      setManilaResults(manilaHist.results || [])
      setFellowshipDraft((prev) => ({
        ...prev,
        domainId: prev.domainId || d.domains?.[0]?.id || '',
      }))
      setAuthed(true)
    } catch (e) {
      setAuthed(false)
      MessagePlugin.error(apiErrorMessage(e, '鉴权失败或加载失败'))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (getAdminToken()) void load()
  }, [load])

  const unlock = async () => {
    const t = tokenInput.trim()
    if (!t) {
      MessagePlugin.warning('请输入 ADMIN_TOKEN')
      return
    }
    setAdminToken(t)
    await load()
  }

  const confirmAction = (opts: {
    header: string
    body: string
    confirm?: string
    danger?: boolean
    onOk: () => Promise<void>
    success?: string
  }) => {
    const d = DialogPlugin.confirm({
      header: opts.header,
      body: opts.body,
      theme: opts.danger ? 'danger' : 'default',
      confirmBtn: {
        content: opts.confirm || '确定',
        theme: opts.danger ? 'danger' : 'primary',
      },
      onConfirm: async () => {
        try {
          await opts.onOk()
          MessagePlugin.success(opts.success || '已完成')
          d.destroy()
          await load()
        } catch (e) {
          MessagePlugin.error(apiErrorMessage(e, '操作失败'))
        }
      },
    })
  }

  const createBindCode = async (user: AdminUser) => {
    try {
      const res = await adminApi.createQQBindCode(user.id)
      setBindDialog({
        username: user.username,
        code: res.code,
        expiresAt: res.expiresAt,
        hint: res.botAddHint || qqHint,
      })
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '生成绑定码失败'))
    }
  }

  const unbindQQ = (userId: string, label: string) => {
    confirmAction({
      header: '解绑 QQ',
      body: `确定解除「${label}」的 QQ 绑定？`,
      confirm: '解绑',
      danger: true,
      success: '已解绑',
      onOk: async () => {
        await adminApi.unbindQQ(userId)
      },
    })
  }

  const changeUserFellowship = async (user: AdminUser, fellowshipId: string) => {
    if (!fellowshipId || fellowshipId === user.fellowshipId) return
    try {
      await adminApi.setUserFellowship(user.id, fellowshipId)
      MessagePlugin.success('已更新团契')
      await load()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '更新团契失败'))
    }
  }

  const toggleEmailVerified = async (user: AdminUser) => {
    try {
      await adminApi.setUserEmailVerified(user.id, !user.emailVerified)
      MessagePlugin.success(user.emailVerified ? '已取消验证' : '已标记邮箱已验证')
      await load()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '操作失败'))
    }
  }

  const submitAdminPassword = async () => {
    if (!passwordDialog) return
    const pwd = passwordDialog.password
    if (pwd.length < 6) {
      MessagePlugin.warning('密码至少 6 位')
      return
    }
    try {
      await adminApi.setUserPassword(passwordDialog.id, pwd)
      MessagePlugin.success('密码已更新')
      setPasswordDialog(null)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '设置密码失败'))
    }
  }

  const openGroupDetail = async (id: string) => {
    try {
      const detail = await adminApi.getGroup(id)
      setGroupDetail(detail)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '加载群详情失败'))
    }
  }

  const filteredUsers = users.filter((u) => {
    const q = userFilter.trim().toLowerCase()
    if (!q) return true
    return (
      u.username.toLowerCase().includes(q) ||
      u.email.toLowerCase().includes(q) ||
      (u.hopeId || '').includes(q) ||
      (u.fellowshipCode || '').toLowerCase().includes(q) ||
      (u.domainName || '').toLowerCase().includes(q)
    )
  })

  const filteredConversations = conversations.filter((c) => {
    if (convFilter === 'group') return c.type === 'group'
    if (convFilter === 'dm') return c.type === 'dm'
    return true
  })

  const createDomain = async () => {
    const name = domainDraft.trim()
    if (!name) {
      MessagePlugin.warning('请填写自治域名称')
      return
    }
    try {
      await adminApi.createDomain(name)
      setDomainDraft('')
      MessagePlugin.success('已创建自治域')
      await load()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '创建失败'))
    }
  }

  const createFellowship = async () => {
    const code = fellowshipDraft.code.trim()
    const name = fellowshipDraft.name.trim() || code
    const domainId = fellowshipDraft.domainId
    if (!code) {
      MessagePlugin.warning('请填写团契码')
      return
    }
    if (!domainId) {
      MessagePlugin.warning('请选择自治域')
      return
    }
    try {
      await adminApi.createFellowship({ code, name, domainId })
      setFellowshipDraft((prev) => ({ ...prev, code: '', name: '' }))
      MessagePlugin.success('已创建团契')
      await load()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '创建失败'))
    }
  }

  const saveEditFellowship = async () => {
    if (!editFellowship) return
    const code = editFellowship.code.trim()
    const name = editFellowship.name.trim() || code
    if (!code) {
      MessagePlugin.warning('请填写团契码')
      return
    }
    try {
      await adminApi.updateFellowship(editFellowship.id, {
        code,
        name,
        domainId: editFellowship.domainId,
      })
      setEditFellowship(null)
      MessagePlugin.success('已保存')
      await load()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '保存失败'))
    }
  }

  if (!authed) {
    return (
      <div className="im-auth">
        <div className="im-auth__card">
          <header className="im-auth__brand">
            <img
              className="im-auth__logo"
              src="/mmexport1571484547096.webp"
              alt=""
              width={72}
              height={72}
            />
            <h1 className="im-auth__title">IHope</h1>
          </header>
          <div className="im-auth__panel">
            <h2 className="im-auth__heading">管理入口</h2>
            <p className="im-auth__lead">输入服务器配置的 ADMIN_TOKEN 以进入。</p>
            <div className="im-auth-fields">
              <Input
                type="password"
                size="large"
                placeholder="ADMIN_TOKEN"
                value={tokenInput}
                onChange={(v) => setTokenInput(String(v))}
                onEnter={() => void unlock()}
              />
              <Button theme="primary" size="large" block onClick={() => void unlock()}>
                进入管理
              </Button>
              <Link className="im-auth__link-btn" to="/">
                <Button variant="outline" size="large" block>
                  返回聊天
                </Button>
              </Link>
            </div>
          </div>
        </div>
      </div>
    )
  }

  let panel: ReactNode = null
  if (tab === 'users') {
    panel = (
      <>
        <div className="im-admin__toolbar">
          <Input
            placeholder="搜索用户名 / 邮箱 / IHope 号 / 团契"
            value={userFilter}
            onChange={(v) => setUserFilter(String(v))}
            clearable
            style={{ maxWidth: 320 }}
          />
        </div>
        <Table
          rowKey="id"
          className="im-admin-table"
          data={filteredUsers}
          loading={loading}
          maxHeight={520}
          columns={[
            { colKey: 'username', title: '用户名', width: 96, ellipsis: true },
            {
              colKey: 'hopeId',
              title: 'IHope 号',
              width: 124,
              cell: ({ row }) => (
                <span className="im-admin-mono">{row.hopeId || '—'}</span>
              ),
            },
            { colKey: 'email', title: '邮箱', ellipsis: true, width: 168 },
            {
              colKey: 'fellowshipId',
              title: '团契',
              width: 168,
              cell: ({ row }) => (
                <Select
                  size="small"
                  value={row.fellowshipId || undefined}
                  options={fellowshipOptions}
                  placeholder="选择团契"
                  onChange={(v) => void changeUserFellowship(row, String(v))}
                  style={{ width: '100%' }}
                />
              ),
            },
            {
              colKey: 'domainName',
              title: '自治域',
              width: 96,
              ellipsis: true,
              cell: ({ row }) => row.domainName || '—',
            },
            {
              colKey: 'qqBound',
              title: 'QQ',
              width: 56,
              align: 'center',
              cell: ({ row }) => (row.qqBound ? '已绑' : '未绑'),
            },
            {
              colKey: 'emailVerified',
              title: '已验证',
              width: 64,
              align: 'center',
              cell: ({ row }) => (row.emailVerified ? '是' : '否'),
            },
            {
              colKey: 'lastSeenAt',
              title: '上次在线',
              width: 128,
              cell: ({ row }) => (
                <span className="im-admin-mono">
                  {row.online ? '在线' : formatLastSeen(row.lastSeenAt)}
                </span>
              ),
            },
            {
              colKey: 'createdAt',
              title: '注册',
              width: 128,
              cell: ({ row }) => (
                <span className="im-admin-mono">{formatTime(row.createdAt)}</span>
              ),
            },
            {
              colKey: 'op',
              title: '操作',
              align: 'center',
              fixed: 'right',
              width: 280,
              cell: ({ row }) => (
                <div className="im-admin__ops">
                  <Button
                    size="small"
                    variant="text"
                    theme="primary"
                    onClick={() => void toggleEmailVerified(row)}
                  >
                    {row.emailVerified ? '取消验证' : '验证邮箱'}
                  </Button>
                  <Button
                    size="small"
                    variant="text"
                    theme="primary"
                    onClick={() =>
                      setPasswordDialog({ id: row.id, username: row.username, password: '' })
                    }
                  >
                    设密码
                  </Button>
                  <Button
                    size="small"
                    variant="text"
                    theme="primary"
                    disabled={!qqBotEnabled}
                    onClick={() => void createBindCode(row)}
                  >
                    绑定码
                  </Button>
                  <Button
                    size="small"
                    variant="text"
                    disabled={!qqBotEnabled || !row.qqBound}
                    onClick={() => unbindQQ(row.id, row.username)}
                  >
                    解绑 QQ
                  </Button>
                  <Button
                    size="small"
                    theme="danger"
                    variant="text"
                    onClick={() =>
                      confirmAction({
                        header: '确认删除',
                        body: `确定删除用户「${row.username}」？其私聊与消息将一并删除。`,
                        confirm: '删除',
                        danger: true,
                        success: '已删除',
                        onOk: async () => {
                          await adminApi.deleteUser(row.id)
                        },
                      })
                    }
                  >
                    删除
                  </Button>
                </div>
              ),
            },
          ]}
        />
      </>
    )
  } else if (tab === 'domains') {
    panel = (
      <>
        <div className="im-admin__toolbar">
          <Input
            placeholder="新自治域名称"
            value={domainDraft}
            onChange={(v) => setDomainDraft(String(v))}
            onEnter={() => void createDomain()}
            style={{ maxWidth: 280 }}
          />
          <Button theme="primary" onClick={() => void createDomain()}>
            新建自治域
          </Button>
        </div>
        <Table
          rowKey="id"
          className="im-admin-table"
          data={domains}
          loading={loading}
          maxHeight={520}
          columns={[
            { colKey: 'name', title: '名称', ellipsis: true },
            {
              colKey: 'fellowshipCount',
              title: '团契数',
              width: 90,
              align: 'center',
            },
            {
              colKey: 'createdAt',
              title: '创建',
              width: 136,
              cell: ({ row }) => (
                <span className="im-admin-mono">{formatTime(row.createdAt)}</span>
              ),
            },
            {
              colKey: 'op',
              title: '操作',
              align: 'center',
              fixed: 'right',
              width: 120,
              cell: ({ row }) => (
                <div className="im-admin__ops">
                  <Button
                    size="small"
                    variant="text"
                    theme="primary"
                    onClick={() => {
                      const name = window.prompt('重命名自治域', row.name)
                      if (name == null) return
                      const trimmed = name.trim()
                      if (!trimmed || trimmed === row.name) return
                      void (async () => {
                        try {
                          await adminApi.updateDomain(row.id, trimmed)
                          MessagePlugin.success('已重命名')
                          await load()
                        } catch (e) {
                          MessagePlugin.error(apiErrorMessage(e, '重命名失败'))
                        }
                      })()
                    }}
                  >
                    重命名
                  </Button>
                  <Button
                    size="small"
                    theme="danger"
                    variant="text"
                    disabled={row.fellowshipCount > 0}
                    onClick={() =>
                      confirmAction({
                        header: '删除自治域',
                        body: `确定删除「${row.name}」？需先移走其下团契。`,
                        confirm: '删除',
                        danger: true,
                        success: '已删除',
                        onOk: async () => {
                          await adminApi.deleteDomain(row.id)
                        },
                      })
                    }
                  >
                    删除
                  </Button>
                </div>
              ),
            },
          ]}
        />
      </>
    )
  } else if (tab === 'fellowships') {
    panel = (
      <>
        <div className="im-admin__toolbar">
          <Input
            placeholder="团契码（组织码）"
            value={fellowshipDraft.code}
            onChange={(v) => setFellowshipDraft((p) => ({ ...p, code: String(v) }))}
            style={{ maxWidth: 160 }}
          />
          <Input
            placeholder="显示名称（可选）"
            value={fellowshipDraft.name}
            onChange={(v) => setFellowshipDraft((p) => ({ ...p, name: String(v) }))}
            style={{ maxWidth: 160 }}
          />
          <Select
            placeholder="所属自治域"
            value={fellowshipDraft.domainId || undefined}
            options={domainOptions}
            onChange={(v) => setFellowshipDraft((p) => ({ ...p, domainId: String(v) }))}
            style={{ width: 180 }}
          />
          <Button theme="primary" onClick={() => void createFellowship()}>
            新建团契
          </Button>
        </div>
        <p className="im-muted im-admin__hint">
          把多个团契设为同一自治域后，这些团契的成员可以互相搜索与加好友。
        </p>
        <Table
          rowKey="id"
          className="im-admin-table"
          data={fellowships}
          loading={loading}
          maxHeight={520}
          columns={[
            { colKey: 'code', title: '团契码', width: 140 },
            { colKey: 'name', title: '名称', width: 140, ellipsis: true },
            { colKey: 'domainName', title: '自治域', width: 140, ellipsis: true },
            { colKey: 'userCount', title: '人数', width: 70, align: 'center' },
            {
              colKey: 'createdAt',
              title: '创建',
              width: 136,
              cell: ({ row }) => (
                <span className="im-admin-mono">{formatTime(row.createdAt)}</span>
              ),
            },
            {
              colKey: 'op',
              title: '操作',
              align: 'center',
              fixed: 'right',
              width: 108,
              cell: ({ row }) => (
                <div className="im-admin__ops">
                  <Button
                    size="small"
                    variant="text"
                    theme="primary"
                    onClick={() => setEditFellowship({ ...row })}
                  >
                    编辑
                  </Button>
                  <Button
                    size="small"
                    theme="danger"
                    variant="text"
                    disabled={row.userCount > 0}
                    onClick={() =>
                      confirmAction({
                        header: '删除团契',
                        body: `确定删除团契「${row.code}」？需先将用户改到其他团契。`,
                        confirm: '删除',
                        danger: true,
                        success: '已删除',
                        onOk: async () => {
                          await adminApi.deleteFellowship(row.id)
                        },
                      })
                    }
                  >
                    删除
                  </Button>
                </div>
              ),
            },
          ]}
        />
      </>
    )
  } else if (tab === 'qq') {
    panel = !qqBotEnabled ? (
      <p className="im-muted im-admin__empty">QQ 机器人未启用（检查 QQ_BOT_ENABLED 等配置）。</p>
    ) : (
      <Table
        rowKey="userId"
        className="im-admin-table"
        data={qqBindings}
        loading={loading}
        empty="暂无 QQ 绑定"
        maxHeight={520}
        columns={[
          { colKey: 'username', title: '用户名', width: 120, ellipsis: true },
          {
            colKey: 'hopeId',
            title: 'IHope 号',
            width: 128,
            cell: ({ row }) => (
              <span className="im-admin-mono">{row.hopeId || '—'}</span>
            ),
          },
          {
            colKey: 'qqOpenId',
            title: 'QQ OpenID',
            ellipsis: true,
            cell: ({ row }) => (
              <span className="im-admin-mono">{maskOpenId(row.qqOpenId)}</span>
            ),
          },
          {
            colKey: 'doorbellEnabled',
            title: '消息提醒',
            width: 90,
            align: 'center',
            cell: ({ row }) => (row.doorbellEnabled ? '开' : '关'),
          },
          {
            colKey: 'boundAt',
            title: '绑定时间',
            width: 136,
            cell: ({ row }) => (
              <span className="im-admin-mono">{formatTime(row.boundAt)}</span>
            ),
          },
          {
            colKey: 'op',
            title: '操作',
            align: 'center',
            fixed: 'right',
            width: 72,
            cell: ({ row }) => (
              <Button
                size="small"
                theme="danger"
                variant="text"
                onClick={() => unbindQQ(row.userId, row.username)}
              >
                解绑
              </Button>
            ),
          },
        ]}
      />
    )
  } else if (tab === 'conversations') {
    panel = (
      <>
        <div className="im-admin__toolbar">
          <Select
            value={convFilter}
            options={[
              { label: '全部', value: 'all' },
              { label: '仅群聊', value: 'group' },
              { label: '仅私聊', value: 'dm' },
            ]}
            onChange={(v) => setConvFilter(v as 'all' | 'group' | 'dm')}
            style={{ width: 140 }}
          />
        </div>
        <Table
          rowKey="id"
          className="im-admin-table"
          data={filteredConversations}
          loading={loading}
          maxHeight={520}
          columns={[
            {
              colKey: 'type',
              title: '类型',
              width: 72,
              align: 'center',
              cell: ({ row }) => (row.type === 'group' ? '群聊' : '私聊'),
            },
            { colKey: 'title', title: '标题', width: 160, ellipsis: true },
            {
              colKey: 'groupNo',
              title: '群号',
              width: 120,
              cell: ({ row }) => (
                <span className="im-admin-mono">{row.groupNo || '—'}</span>
              ),
            },
            {
              colKey: 'ownerUsername',
              title: '群主',
              width: 100,
              ellipsis: true,
              cell: ({ row }) => row.ownerUsername || '—',
            },
            { colKey: 'members', title: '成员', ellipsis: true, width: 200 },
            {
              colKey: 'memberCount',
              title: '人数',
              width: 64,
              align: 'center',
            },
            {
              colKey: 'createdAt',
              title: '创建',
              width: 136,
              cell: ({ row }) => (
                <span className="im-admin-mono">{formatTime(row.createdAt)}</span>
              ),
            },
            {
              colKey: 'op',
              title: '操作',
              align: 'center',
              fixed: 'right',
              width: 108,
              cell: ({ row }) => (
                <div className="im-admin__ops">
                  {row.type === 'group' && (
                    <Button
                      size="small"
                      variant="text"
                      theme="primary"
                      onClick={() => void openGroupDetail(row.id)}
                    >
                      详情
                    </Button>
                  )}
                  <Button
                    size="small"
                    theme="danger"
                    variant="text"
                    onClick={() =>
                      confirmAction({
                        header: '确认删除',
                        body: `确定删除${row.type === 'group' ? '群' : '私聊'}「${row.title || row.id}」？消息将一并删除。`,
                        confirm: '删除',
                        danger: true,
                        success: '已删除',
                        onOk: async () => {
                          await adminApi.deleteConversation(row.id)
                        },
                      })
                    }
                  >
                    删除
                  </Button>
                </div>
              ),
            },
          ]}
        />
      </>
    )
  } else if (tab === 'games') {
    panel = (
      <>
        <div className="im-admin__toolbar">
          <p className="im-muted im-admin__hint" style={{ margin: 0 }}>
            马尼拉 · 房间创建后超过 {manilaMaxAge} 会自动结束并释放内存。可强制结束异常对局；玩家可在大厅查看自己的历史战绩。
          </p>
        </div>
        <h3 style={{ margin: '0 0 8px', fontSize: 15 }}>进行中房间</h3>
        <Table
          rowKey="id"
          className="im-admin-table"
          data={manilaRooms}
          loading={loading}
          empty="暂无内存中的马尼拉房间"
          maxHeight={320}
          columns={[
            {
              colKey: 'code',
              title: '房间码',
              width: 88,
              cell: ({ row }) => <span className="im-admin-mono">{row.code}</span>,
            },
            {
              colKey: 'status',
              title: '状态',
              width: 88,
              cell: ({ row }) =>
                row.status === 'playing'
                  ? '游戏中'
                  : row.status === 'open'
                    ? '等待中'
                    : row.status === 'closed'
                      ? '已结束'
                      : row.status,
            },
            {
              colKey: 'hostUsername',
              title: '房主',
              width: 100,
              ellipsis: true,
            },
            {
              colKey: 'members',
              title: '玩家',
              ellipsis: true,
              cell: ({ row }) =>
                `${row.memberCount}/${row.maxPlayers} · ${(row.members || []).join('、') || '—'}`,
            },
            {
              colKey: 'phase',
              title: '阶段',
              width: 120,
              cell: ({ row }) =>
                row.status === 'playing'
                  ? `${row.phase || '—'}${row.voyage ? ` · 第${row.voyage}航` : ''}`
                  : '—',
            },
            {
              colKey: 'isPrivate',
              title: '私密',
              width: 64,
              align: 'center',
              cell: ({ row }) => (row.isPrivate ? '是' : '否'),
            },
            {
              colKey: 'ageSeconds',
              title: '存活',
              width: 88,
              cell: ({ row }) => formatDuration(row.ageSeconds),
            },
            {
              colKey: 'createdAt',
              title: '创建',
              width: 148,
              cell: ({ row }) => (
                <span className="im-admin-mono">{formatTime(row.createdAt)}</span>
              ),
            },
            {
              colKey: 'op',
              title: '操作',
              align: 'center',
              fixed: 'right',
              width: 100,
              cell: ({ row }) => (
                <div className="im-admin__ops">
                  <Button
                    size="small"
                    theme="danger"
                    variant="text"
                    onClick={() =>
                      confirmAction({
                        header: '强制结束',
                        body: `确定强制结束房间「${row.code}」并从内存移除？玩家将无法继续本局。`,
                        confirm: '结束',
                        danger: true,
                        success: '已结束',
                        onOk: async () => {
                          await adminApi.endManilaRoom(row.id)
                        },
                      })
                    }
                  >
                    结束
                  </Button>
                </div>
              ),
            },
          ]}
        />
        <h3 style={{ margin: '20px 0 8px', fontSize: 15 }}>最近战绩</h3>
        <Table
          rowKey="id"
          className="im-admin-table"
          data={manilaResults}
          loading={loading}
          empty="暂无已落库战绩"
          maxHeight={320}
          columns={[
            {
              colKey: 'roomCode',
              title: '房间码',
              width: 88,
              cell: ({ row }) => (
                <span className="im-admin-mono">{row.roomCode || '—'}</span>
              ),
            },
            {
              colKey: 'finishedAt',
              title: '结束时间',
              width: 148,
              cell: ({ row }) => (
                <span className="im-admin-mono">{formatTime(row.finishedAt)}</span>
              ),
            },
            {
              colKey: 'players',
              title: '排名 / 财富',
              ellipsis: true,
              cell: ({ row }) =>
                (row.players || [])
                  .map((p) => `#${p.rank} ${p.username}(${p.fortune})`)
                  .join(' · ') || '—',
            },
          ]}
        />
      </>
    )
  }


  return (
    <div className="im-admin">
      <div className="im-admin__frame">
        <header className="im-admin__head">
          <div className="im-admin__brand">
            <img
              className="im-admin__logo"
              src="/mmexport1571484547096.webp"
              alt=""
              width={44}
              height={44}
            />
            <div>
              <h1>管理</h1>
              <p className="im-muted">
                团契码即组织码；仅同一自治域内可互查。可将多个团契划入同一自治域。
              </p>
            </div>
          </div>
          <div className="im-admin__actions">
            <Button variant="outline" loading={loading} onClick={() => void load()}>
              刷新
            </Button>
            <Button
              variant="outline"
              onClick={() => {
                setAdminToken(null)
                setAuthed(false)
                setUsers([])
                setConversations([])
                setGroupDetail(null)
                setQqBindings([])
                setDomains([])
                setFellowships([])
                setManilaRooms([])
                setManilaResults([])
              }}
            >
              退出管理
            </Button>
            <Link to="/">
              <Button theme="primary" variant="outline">
                返回聊天
              </Button>
            </Link>
          </div>
        </header>

        <nav className="im-admin__tabs" aria-label="管理分区">
          {TAB_ITEMS.map((item) => (
            <button
              key={item.id}
              type="button"
              className={`im-admin__tab${tab === item.id ? ' is-active' : ''}`}
              onClick={() => setTab(item.id)}
            >
              {item.label(tabCounts[item.id])}
            </button>
          ))}
        </nav>

        <div className="im-admin__body">
          <div className="im-card im-admin__panel">{panel}</div>
        </div>
      </div>

      <Dialog
        visible={!!groupDetail}
        header={
          groupDetail
            ? `群详情 · ${groupDetail.conversation.title}${
                groupDetail.conversation.groupNo
                  ? `（${groupDetail.conversation.groupNo}）`
                  : ''
              }`
            : '群详情'
        }
        width={640}
        onClose={() => setGroupDetail(null)}
        footer={
          <Button theme="default" onClick={() => setGroupDetail(null)}>
            关闭
          </Button>
        }
      >
        {groupDetail && (
          <div className="im-admin-group">
            <div className="im-admin-group__row">
              <span>群主</span>
              <strong>{groupDetail.conversation.ownerUsername || '—'}</strong>
            </div>
            <div className="im-admin-group__row">
              <span>加群方式</span>
              <Select
                style={{ width: 220 }}
                value={groupDetail.conversation.joinMode || 'verify'}
                options={[
                  { label: '允许任何人加入', value: 'anyone' },
                  { label: '需要验证信息', value: 'verify' },
                  { label: '不允许任何人加入', value: 'deny' },
                ]}
                onChange={async (v) => {
                  const mode = String(v) as 'anyone' | 'verify' | 'deny'
                  try {
                    const c = await adminApi.patchGroup(groupDetail.conversation.id, {
                      joinMode: mode,
                    })
                    setGroupDetail({
                      ...groupDetail,
                      conversation: { ...groupDetail.conversation, ...c },
                    })
                    MessagePlugin.success('已更新')
                    await load()
                  } catch (e) {
                    MessagePlugin.error(apiErrorMessage(e, '设置失败'))
                  }
                }}
              />
            </div>

            {groupDetail.joinRequests.length > 0 && (
              <div className="im-admin-group__block">
                <div className="im-admin-group__label">
                  入群申请（{groupDetail.joinRequests.length}）
                </div>
                {groupDetail.joinRequests.map((r) => (
                  <div key={r.id} className="im-admin-group__join">
                    <div>
                      <strong>{r.fromUsername}</strong>
                      <div className="im-muted">{r.message || '申请入群'}</div>
                    </div>
                    <div className="im-admin__ops">
                      <Button
                        size="small"
                        theme="primary"
                        variant="text"
                        onClick={async () => {
                          try {
                            await adminApi.acceptGroupJoin(r.conversationId, r.id)
                            MessagePlugin.success('已同意')
                            await openGroupDetail(groupDetail.conversation.id)
                            await load()
                          } catch (e) {
                            MessagePlugin.error(apiErrorMessage(e, '操作失败'))
                          }
                        }}
                      >
                        同意
                      </Button>
                      <Button
                        size="small"
                        theme="danger"
                        variant="text"
                        onClick={async () => {
                          try {
                            await adminApi.rejectGroupJoin(r.conversationId, r.id)
                            MessagePlugin.success('已拒绝')
                            await openGroupDetail(groupDetail.conversation.id)
                            await load()
                          } catch (e) {
                            MessagePlugin.error(apiErrorMessage(e, '操作失败'))
                          }
                        }}
                      >
                        拒绝
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            )}

            <div className="im-admin-group__block">
              <div className="im-admin-group__label">
                成员（
                {groupDetail.members.filter((m) => !m.removed).length}）
              </div>
              {groupDetail.members
                .filter((m) => !m.removed)
                .map((m) => (
                  <div key={m.id} className="im-admin-group__join">
                    <div>
                      <strong>
                        {m.username}
                        {m.isOwner
                          ? ' · 群主'
                          : m.role === 'admin'
                            ? ' · 管理员'
                            : ''}
                      </strong>
                      {m.hopeId && (
                        <div className="im-muted">IHope 号：{m.hopeId}</div>
                      )}
                    </div>
                    {!m.isOwner && (
                      <div className="im-admin__ops">
                        <Button
                          size="small"
                          variant="text"
                          theme="primary"
                          onClick={() =>
                            confirmAction({
                              header: m.role === 'admin' ? '取消管理员' : '设为管理员',
                              body:
                                m.role === 'admin'
                                  ? `取消「${m.username}」的管理员身份？`
                                  : `将「${m.username}」设为管理员？`,
                              confirm: '确认',
                              success: m.role === 'admin' ? '已取消管理员' : '已设为管理员',
                              onOk: async () => {
                                await adminApi.setGroupMemberRole(
                                  groupDetail.conversation.id,
                                  m.id,
                                  m.role === 'admin' ? 'member' : 'admin',
                                )
                                await openGroupDetail(groupDetail.conversation.id)
                              },
                            })
                          }
                        >
                          {m.role === 'admin' ? '取消管理员' : '设管理员'}
                        </Button>
                        <Button
                          size="small"
                          variant="text"
                          theme="primary"
                          onClick={() =>
                            confirmAction({
                              header: '转让群主',
                              body: `将群主转让给「${m.username}」？原群主将变为管理员。`,
                              confirm: '转让',
                              success: '已转让群主',
                              onOk: async () => {
                                await adminApi.transferGroupOwner(
                                  groupDetail.conversation.id,
                                  m.id,
                                )
                                await openGroupDetail(groupDetail.conversation.id)
                                await load()
                              },
                            })
                          }
                        >
                          转让群主
                        </Button>
                        <Button
                          size="small"
                          theme="danger"
                          variant="text"
                          onClick={() =>
                            confirmAction({
                              header: '移出成员',
                              body: `将「${m.username}」移出本群？`,
                              confirm: '移出',
                              danger: true,
                              success: '已移出',
                              onOk: async () => {
                                await adminApi.kickGroupMember(
                                  groupDetail.conversation.id,
                                  m.id,
                                )
                                await openGroupDetail(groupDetail.conversation.id)
                              },
                            })
                          }
                        >
                          移出
                        </Button>
                      </div>
                    )}
                  </div>
                ))}
            </div>
          </div>
        )}
      </Dialog>

      <Dialog
        visible={!!bindDialog}
        header={bindDialog ? `「${bindDialog.username}」的 QQ 绑定码` : '绑定码'}
        onClose={() => setBindDialog(null)}
        confirmBtn="关闭"
        cancelBtn={null}
        onConfirm={() => setBindDialog(null)}
      >
        {bindDialog && (
          <div>
            <p className="im-muted" style={{ marginTop: 0 }}>
              {bindDialog.hint || '请让用户将绑定码发送给 QQ 机器人完成绑定。'}
            </p>
            <div className="im-bind-box">
              <strong className="im-bind-code">{bindDialog.code}</strong>
            </div>
            <p className="im-muted" style={{ marginBottom: 0 }}>
              有效期至 {formatTime(bindDialog.expiresAt)}（约 10 分钟）
            </p>
            <Button
              theme="primary"
              variant="outline"
              style={{ marginTop: 12 }}
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(bindDialog.code)
                  MessagePlugin.success('已复制绑定码')
                } catch {
                  MessagePlugin.error('复制失败')
                }
              }}
            >
              复制绑定码
            </Button>
          </div>
        )}
      </Dialog>

      <Dialog
        visible={!!passwordDialog}
        header={passwordDialog ? `设置「${passwordDialog.username}」的密码` : '设置密码'}
        onClose={() => setPasswordDialog(null)}
        confirmBtn="保存"
        cancelBtn="取消"
        onConfirm={() => void submitAdminPassword()}
      >
        {passwordDialog && (
          <div className="im-admin__form">
            <label>
              新密码（至少 6 位）
              <Input
                type="password"
                clearable
                value={passwordDialog.password}
                onChange={(v) =>
                  setPasswordDialog((p) => (p ? { ...p, password: String(v) } : p))
                }
                onEnter={() => void submitAdminPassword()}
              />
            </label>
          </div>
        )}
      </Dialog>

      <Dialog
        visible={!!editFellowship}
        header="编辑团契"
        onClose={() => setEditFellowship(null)}
        onConfirm={() => void saveEditFellowship()}
        confirmBtn="保存"
        cancelBtn="取消"
      >
        {editFellowship && (
          <div className="im-admin__form">
            <label>
              团契码
              <Input
                value={editFellowship.code}
                onChange={(v) =>
                  setEditFellowship((p) => (p ? { ...p, code: String(v) } : p))
                }
              />
            </label>
            <label>
              名称
              <Input
                value={editFellowship.name}
                onChange={(v) =>
                  setEditFellowship((p) => (p ? { ...p, name: String(v) } : p))
                }
              />
            </label>
            <label>
              自治域
              <Select
                value={editFellowship.domainId}
                options={domainOptions}
                onChange={(v) =>
                  setEditFellowship((p) => (p ? { ...p, domainId: String(v) } : p))
                }
              />
            </label>
          </div>
        )}
      </Dialog>
    </div>
  )
}

function maskOpenId(id: string): string {
  const t = id.trim()
  if (t.length <= 10) return t
  return `${t.slice(0, 6)}…${t.slice(-4)}`
}

function formatTime(iso?: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return String(iso)
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
}

function formatLastSeen(iso?: string | null): string {
  if (!iso) return '从未'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return String(iso)
  const diffMs = Date.now() - d.getTime()
  if (diffMs < 60_000) return '刚刚'
  if (diffMs < 3_600_000) return `${Math.floor(diffMs / 60_000)} 分钟前`
  if (diffMs < 86_400_000) return `${Math.floor(diffMs / 3_600_000)} 小时前`
  return formatTime(iso)
}

function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return '—'
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  if (h > 0) return `${h}h${m}m`
  if (m > 0) return `${m}m`
  return `${seconds}s`
}
