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
  type AdminQQBinding,
  type AdminUser,
} from '@/api'

type AdminTab = 'users' | 'domains' | 'fellowships' | 'qq' | 'conversations'

const TAB_ITEMS: { id: AdminTab; label: (n: number) => string }[] = [
  { id: 'users', label: (n) => `用户 (${n})` },
  { id: 'domains', label: (n) => `自治域 (${n})` },
  { id: 'fellowships', label: (n) => `团契 (${n})` },
  { id: 'qq', label: (n) => `QQ 绑定 (${n})` },
  { id: 'conversations', label: (n) => `会话 (${n})` },
]

export function AdminPage() {
  const [tokenInput, setTokenInput] = useState(getAdminToken() || '')
  const [authed, setAuthed] = useState(!!getAdminToken())
  const [users, setUsers] = useState<AdminUser[]>([])
  const [conversations, setConversations] = useState<AdminConversation[]>([])
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
  }

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [u, c, qq, d, f] = await Promise.all([
        adminApi.listUsers(),
        adminApi.listConversations(),
        adminApi.listQQBindings(),
        adminApi.listDomains(),
        adminApi.listFellowships(),
      ])
      setUsers(u.users)
      setConversations(c.conversations)
      setQqBindings(qq.bindings || [])
      setQqBotEnabled(!!qq.botEnabled)
      setQqHint(qq.botAddHint || '')
      setDomains(d.domains || [])
      setFellowships(f.fellowships || [])
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
      <Table
        rowKey="id"
        data={users}
        loading={loading}
        maxHeight={520}
        columns={[
          { colKey: 'username', title: '用户名', width: 110 },
          {
            colKey: 'hopeId',
            title: 'IHope 号',
            width: 100,
            cell: ({ row }) => row.hopeId || '—',
          },
          { colKey: 'email', title: '邮箱', ellipsis: true, width: 160 },
          {
            colKey: 'fellowshipId',
            title: '团契',
            width: 200,
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
            width: 120,
            cell: ({ row }) => row.domainName || '—',
          },
          {
            colKey: 'qqBound',
            title: 'QQ',
            width: 64,
            cell: ({ row }) => (row.qqBound ? '已绑' : '未绑'),
          },
          {
            colKey: 'emailVerified',
            title: '已验证',
            width: 64,
            cell: ({ row }) => (row.emailVerified ? '是' : '否'),
          },
          { colKey: 'createdAt', title: '注册时间', width: 160 },
          {
            colKey: 'op',
            title: '操作',
            fixed: 'right',
            width: 200,
            cell: ({ row }) => (
              <div className="im-admin__ops">
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
          data={domains}
          loading={loading}
          maxHeight={520}
          columns={[
            { colKey: 'name', title: '名称' },
            { colKey: 'fellowshipCount', title: '团契数', width: 90 },
            { colKey: 'createdAt', title: '创建时间', width: 180 },
            {
              colKey: 'op',
              title: '操作',
              fixed: 'right',
              width: 160,
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
          data={fellowships}
          loading={loading}
          maxHeight={520}
          columns={[
            { colKey: 'code', title: '团契码', width: 140 },
            { colKey: 'name', title: '名称', width: 140 },
            { colKey: 'domainName', title: '自治域', width: 140 },
            { colKey: 'userCount', title: '人数', width: 70 },
            { colKey: 'createdAt', title: '创建时间', width: 180 },
            {
              colKey: 'op',
              title: '操作',
              fixed: 'right',
              width: 140,
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
        data={qqBindings}
        loading={loading}
        empty="暂无 QQ 绑定"
        maxHeight={520}
        columns={[
          { colKey: 'username', title: '用户名', width: 120 },
          {
            colKey: 'hopeId',
            title: 'IHope 号',
            width: 110,
            cell: ({ row }) => row.hopeId || '—',
          },
          {
            colKey: 'qqOpenId',
            title: 'QQ OpenID',
            ellipsis: true,
            cell: ({ row }) => maskOpenId(row.qqOpenId),
          },
          {
            colKey: 'doorbellEnabled',
            title: '消息提醒',
            width: 90,
            cell: ({ row }) => (row.doorbellEnabled ? '开' : '关'),
          },
          {
            colKey: 'boundAt',
            title: '绑定时间',
            width: 180,
            cell: ({ row }) => formatTime(row.boundAt),
          },
          {
            colKey: 'op',
            title: '操作',
            fixed: 'right',
            width: 100,
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
  } else {
    panel = (
      <Table
        rowKey="id"
        data={conversations}
        loading={loading}
        maxHeight={520}
        columns={[
          {
            colKey: 'type',
            title: '类型',
            width: 80,
            cell: ({ row }) => (row.type === 'group' ? '群聊' : '私聊'),
          },
          { colKey: 'title', title: '标题', width: 160 },
          { colKey: 'members', title: '成员', ellipsis: true },
          { colKey: 'memberCount', title: '人数', width: 70 },
          { colKey: 'createdAt', title: '创建时间', width: 180 },
          {
            colKey: 'op',
            title: '操作',
            fixed: 'right',
            width: 100,
            cell: ({ row }) => (
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
            ),
          },
        ]}
      />
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
                setQqBindings([])
                setDomains([])
                setFellowships([])
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

function formatTime(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleString()
}
