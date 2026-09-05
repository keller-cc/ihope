import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  Button,
  Dialog,
  DialogPlugin,
  Input,
  MessagePlugin,
  Table,
  Tabs,
} from 'tdesign-react'
import {
  adminApi,
  apiErrorMessage,
  getAdminToken,
  setAdminToken,
  type AdminConversation,
  type AdminQQBinding,
  type AdminUser,
} from '../api'

export function AdminPage() {
  const [tokenInput, setTokenInput] = useState(getAdminToken() || '')
  const [authed, setAuthed] = useState(!!getAdminToken())
  const [users, setUsers] = useState<AdminUser[]>([])
  const [conversations, setConversations] = useState<AdminConversation[]>([])
  const [qqBindings, setQqBindings] = useState<AdminQQBinding[]>([])
  const [qqBotEnabled, setQqBotEnabled] = useState(false)
  const [qqHint, setQqHint] = useState('')
  const [loading, setLoading] = useState(false)
  const [tab, setTab] = useState('users')
  const [bindDialog, setBindDialog] = useState<{
    username: string
    code: string
    expiresAt: string
    hint: string
  } | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [u, c, qq] = await Promise.all([
        adminApi.listUsers(),
        adminApi.listConversations(),
        adminApi.listQQBindings(),
      ])
      setUsers(u.users)
      setConversations(c.conversations)
      setQqBindings(qq.bindings || [])
      setQqBotEnabled(!!qq.botEnabled)
      setQqHint(qq.botAddHint || '')
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

  if (!authed) {
    return (
      <div className="admin-page">
        <div className="admin-gate">
          <h1>IHope 管理</h1>
          <p className="im-muted">输入服务器配置的 ADMIN_TOKEN 以进入。</p>
          <Input
            type="password"
            size="large"
            placeholder="ADMIN_TOKEN"
            value={tokenInput}
            onChange={(v) => setTokenInput(String(v))}
            onEnter={() => void unlock()}
          />
          <Button theme="primary" size="large" block onClick={() => void unlock()}>
            进入
          </Button>
          <Link to="/" className="admin-back">
            返回聊天
          </Link>
        </div>
      </div>
    )
  }

  return (
    <div className="admin-page">
      <header className="admin-head">
        <div>
          <h1>IHope 管理</h1>
          <p className="im-muted">
            删除用户会清理其私聊、好友关系与群成员身份；可代为生成 QQ 绑定码或解绑。
          </p>
        </div>
        <div className="admin-head-actions">
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
            }}
          >
            退出管理
          </Button>
          <Link to="/">
            <Button variant="text">返回聊天</Button>
          </Link>
        </div>
      </header>

      <Tabs value={tab} onChange={(v) => setTab(String(v))}>
        <Tabs.TabPanel value="users" label={`用户 (${users.length})`}>
          <Table
            rowKey="id"
            data={users}
            loading={loading}
            columns={[
              { colKey: 'username', title: '用户名', width: 120 },
              {
                colKey: 'hopeId',
                title: 'IHope 号',
                width: 110,
                cell: ({ row }) => row.hopeId || '—',
              },
              { colKey: 'email', title: '邮箱', ellipsis: true },
              {
                colKey: 'qqBound',
                title: 'QQ',
                width: 72,
                cell: ({ row }) => (row.qqBound ? '已绑' : '未绑'),
              },
              {
                colKey: 'emailVerified',
                title: '已验证',
                width: 72,
                cell: ({ row }) => (row.emailVerified ? '是' : '否'),
              },
              { colKey: 'createdAt', title: '注册时间', width: 170 },
              {
                colKey: 'op',
                title: '操作',
                width: 220,
                cell: ({ row }) => (
                  <div className="admin-ops">
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
        </Tabs.TabPanel>

        <Tabs.TabPanel value="qq" label={`QQ 绑定 (${qqBindings.length})`}>
          {!qqBotEnabled ? (
            <p className="im-muted" style={{ padding: 16 }}>
              QQ 机器人未启用（检查 QQ_BOT_ENABLED 等配置）。
            </p>
          ) : (
            <Table
              rowKey="userId"
              data={qqBindings}
              loading={loading}
              empty="暂无 QQ 绑定"
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
          )}
        </Tabs.TabPanel>

        <Tabs.TabPanel value="conversations" label={`会话 (${conversations.length})`}>
          <Table
            rowKey="id"
            data={conversations}
            loading={loading}
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
        </Tabs.TabPanel>
      </Tabs>

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
