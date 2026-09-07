import { useState } from 'react'
import { Button, Dialog, Input, MessagePlugin, Tabs } from 'tdesign-react'
import { api, apiErrorMessage, type PublicGroup, type PublicUser } from '@/api'
import { Avatar } from '@/components/Avatar'

type Props = {
  visible: boolean
  onClose: () => void
  onRequestSent: () => void
  onMessage: (username: string) => void
  onJoined: (conversationId: string) => void
  onEnterGroup: (conversationId: string) => void
}

export function AddContactDialog({
  visible,
  onClose,
  onRequestSent,
  onMessage,
  onJoined,
  onEnterGroup,
}: Props) {
  const [tab, setTab] = useState<string | number>('user')
  const [q, setQ] = useState('')
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)
  const [user, setUser] = useState<PublicUser | null>(null)
  const [group, setGroup] = useState<PublicGroup | null>(null)
  const [notFound, setNotFound] = useState(false)

  const reset = () => {
    setQ('')
    setMsg('')
    setUser(null)
    setGroup(null)
    setNotFound(false)
    setBusy(false)
  }

  const close = () => {
    reset()
    setTab('user')
    onClose()
  }

  const searchUser = async () => {
    if (!q.trim()) {
      MessagePlugin.warning('请输入用户名或 IHope 号')
      return
    }
    setBusy(true)
    setNotFound(false)
    setUser(null)
    try {
      setUser(await api.searchUser(q.trim()))
    } catch (e) {
      setNotFound(true)
      MessagePlugin.error(apiErrorMessage(e, '没有找到用户'))
    } finally {
      setBusy(false)
    }
  }

  const searchGroup = async () => {
    if (!q.trim()) {
      MessagePlugin.warning('请输入群号')
      return
    }
    setBusy(true)
    setNotFound(false)
    setGroup(null)
    try {
      setGroup(await api.searchGroup(q.trim()))
    } catch (e) {
      setNotFound(true)
      MessagePlugin.error(apiErrorMessage(e, '没有找到群'))
    } finally {
      setBusy(false)
    }
  }

  const search = () => {
    if (tab === 'group') void searchGroup()
    else void searchUser()
  }

  return (
    <Dialog visible={visible} header="加好友/群" onClose={close} footer={false} width={420}>
      <Tabs
        value={tab}
        onChange={(v) => {
          setTab(v)
          setQ('')
          setMsg('')
          setUser(null)
          setGroup(null)
          setNotFound(false)
        }}
        list={[
          { label: '找人', value: 'user' },
          { label: '找群', value: 'group' },
        ]}
      />

      <div className="im-auth-fields" style={{ marginTop: 12 }}>
        <div className="im-find-row">
          <Input
            placeholder={tab === 'group' ? '输入群号' : '用户名或 IHope 号'}
            value={q}
            onChange={(v) => {
              const s = String(v)
              setQ(tab === 'group' ? s.replace(/\D/g, '') : s)
            }}
            onEnter={search}
          />
          <Button theme="primary" loading={busy} onClick={search}>
            查找
          </Button>
        </div>

        {notFound && (
          <p className="im-muted">
            {tab === 'group' ? '没有找到该群，请检查群号' : '没有找到该用户，请检查输入'}
          </p>
        )}

        {tab === 'user' && user && (
          <div className="im-find-card">
            <Avatar name={user.username} src={user.avatarUrl} size="lg" />
            <div>
              <strong>{user.username}</strong>
              <div className="im-muted">
                {user.hopeId ? `IHope 号：${user.hopeId}` : '暂无 IHope 号'}
              </div>
            </div>
            {user.isSelf ? (
              <p className="im-muted">这是你自己</p>
            ) : user.isFriend ? (
              <Button
                theme="primary"
                onClick={() => {
                  onMessage(user.username)
                  close()
                }}
              >
                发消息
              </Button>
            ) : (
              <>
                <Input
                  placeholder="验证信息（可选）"
                  value={msg}
                  onChange={(v) => setMsg(String(v))}
                />
                <Button
                  theme="primary"
                  loading={busy}
                  onClick={async () => {
                    setBusy(true)
                    try {
                      await api.addFriend(user.username, msg.trim())
                      MessagePlugin.success('好友申请已发送')
                      reset()
                      onClose()
                      onRequestSent()
                    } catch (e) {
                      MessagePlugin.error(apiErrorMessage(e, '添加失败'))
                    } finally {
                      setBusy(false)
                    }
                  }}
                >
                  加好友
                </Button>
              </>
            )}
          </div>
        )}

        {tab === 'group' && group && (
          <div className="im-find-card">
            <Avatar name={group.title} src={group.avatarUrl} size="lg" group />
            <div>
              <strong>{group.title}</strong>
              <div className="im-muted">
                群号 {group.groupNo} · {group.memberCount} 人
              </div>
            </div>
            {group.joined ? (
              <Button
                theme="primary"
                onClick={() => {
                  onEnterGroup(group.id)
                  close()
                }}
              >
                进入群聊
              </Button>
            ) : group.joinPending ? (
              <p className="im-muted">入群申请已发送，等待管理员同意</p>
            ) : group.joinMode === 'deny' ? (
              <p className="im-muted">该群不允许加入</p>
            ) : group.joinMode === 'anyone' ? (
              <Button
                theme="primary"
                loading={busy}
                onClick={async () => {
                  setBusy(true)
                  try {
                    const res = await api.joinGroup(String(group.groupNo || q), '')
                    if (res.status === 'joined' && res.conversation) {
                      MessagePlugin.success('已加入群聊')
                      reset()
                      onClose()
                      onJoined(res.conversation.id)
                    } else {
                      MessagePlugin.success('入群申请已发送，等待管理员同意')
                      setGroup({ ...group, joinPending: true })
                      onRequestSent()
                    }
                  } catch (e) {
                    MessagePlugin.error(apiErrorMessage(e, '加入失败'))
                  } finally {
                    setBusy(false)
                  }
                }}
              >
                加入群聊
              </Button>
            ) : (
              <>
                <Input
                  placeholder="验证信息（可选）"
                  value={msg}
                  onChange={(v) => setMsg(String(v))}
                />
                <Button
                  theme="primary"
                  loading={busy}
                  onClick={async () => {
                    setBusy(true)
                    try {
                      const res = await api.joinGroup(String(group.groupNo || q), msg.trim())
                      if (res.status === 'joined' && res.conversation) {
                        MessagePlugin.success('已加入群聊')
                        reset()
                        onClose()
                        onJoined(res.conversation.id)
                      } else {
                        MessagePlugin.success('入群申请已发送，等待管理员同意')
                        setGroup({ ...group, joinPending: true })
                        setMsg('')
                        onRequestSent()
                      }
                    } catch (e) {
                      MessagePlugin.error(apiErrorMessage(e, '加入失败'))
                    } finally {
                      setBusy(false)
                    }
                  }}
                >
                  申请加入
                </Button>
              </>
            )}
          </div>
        )}
      </div>
    </Dialog>
  )
}
