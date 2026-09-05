import { useEffect, useRef, useState } from 'react'
import { Button, Dialog, Drawer, Input, MessagePlugin, Switch } from 'tdesign-react'
import { api, apiErrorMessage, setToken, type QQStatus, type User } from '../api'
import { useIsMobile } from '../hooks/useIsMobile'
import { Avatar } from './Avatar'

export type DrawerView = 'home' | 'hope' | 'notify' | 'quote'

type Props = {
  open: boolean
  user: User
  onClose: () => void
  onUserChange?: (u: User) => void
  onLogout: () => void
  onOpenSettings: () => void
}

export function UserDrawer({
  open,
  user,
  onClose,
  onUserChange,
  onLogout,
  onOpenSettings,
}: Props) {
  const isMobile = useIsMobile()
  const [view, setView] = useState<DrawerView>('home')
  const [qq, setQq] = useState<QQStatus | null>(null)
  const [bindCode, setBindCode] = useState('')
  const [bindHint, setBindHint] = useState('')
  const [quote, setQuote] = useState<{ body: string; author?: string; date: string } | null>(null)
  const [quoteBusy, setQuoteBusy] = useState(false)
  const [quoteError, setQuoteError] = useState('')
  const [renameOpen, setRenameOpen] = useState(false)
  const [renameDraft, setRenameDraft] = useState('')
  const [renameBusy, setRenameBusy] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (!open) return
    setView('home')
    void api
      .qqStatus()
      .then(setQq)
      .catch(() => setQq({ botEnabled: false, bound: false }))
  }, [open])

  const loadQuote = async () => {
    setQuoteBusy(true)
    setQuoteError('')
    try {
      const q = await api.todayQuote()
      setQuote(q)
    } catch (e) {
      setQuote(null)
      setQuoteError(apiErrorMessage(e, '加载金句失败'))
    } finally {
      setQuoteBusy(false)
    }
  }

  const openQuote = () => {
    setView('quote')
    void loadQuote()
  }

  return (
    <Drawer
      header={null}
      visible={open}
      placement="left"
      size={isMobile ? '78%' : '300px'}
      onClose={onClose}
      footer={null}
      closeBtn={false}
      className="im-drawer"
      showOverlay
    >
      <div className="im-drawer__body">
        {view === 'home' && (
          <>
            <header className="im-drawer__hero">
              <Avatar
                name={user.username}
                src={user.avatarUrl}
                size="xl"
                onClick={() => fileRef.current?.click()}
                title="点击更换头像"
              />
              <input
                ref={fileRef}
                type="file"
                accept="image/*"
                hidden
                onChange={async (e) => {
                  const file = e.target.files?.[0]
                  e.target.value = ''
                  if (!file) return
                  try {
                    const u = await api.uploadAvatar(file)
                    onUserChange?.(u)
                    MessagePlugin.success('头像已更新')
                  } catch (err) {
                    MessagePlugin.error(apiErrorMessage(err, '上传失败'))
                  }
                }}
              />
              <div className="im-drawer__hero-meta">
                <div className="im-drawer__name">{user.username}</div>
                <div className="im-drawer__sub">
                  {user.hopeId ? `IHope：${user.hopeId}` : '正在分配 IHope 号…'}
                </div>
              </div>
            </header>

            <section className="im-menu-card">
              <button type="button" className="im-menu-item" onClick={() => setView('hope')}>
                <span className="im-menu-item__icon im-menu-item__icon--user" />
                <span className="im-menu-item__text">账号与 IHope 号</span>
                <span className="im-menu-item__chevron" />
              </button>
              <button type="button" className="im-menu-item" onClick={openQuote}>
                <span className="im-menu-item__icon im-menu-item__icon--quote" />
                <span className="im-menu-item__text">今日金句</span>
                <span className="im-menu-item__chevron" />
              </button>
              <button type="button" className="im-menu-item" onClick={() => setView('notify')}>
                <span className="im-menu-item__icon im-menu-item__icon--bell" />
                <span className="im-menu-item__text">消息提醒</span>
                <span className="im-menu-item__hint">
                  {qq?.bound ? (qq.doorbellEnabled ? '开' : '关') : '未绑'}
                </span>
                <span className="im-menu-item__chevron" />
              </button>
            </section>

            <section className="im-menu-card">
              <button
                type="button"
                className="im-menu-item"
                onClick={() => {
                  onClose()
                  onOpenSettings()
                }}
              >
                <span className="im-menu-item__icon im-menu-item__icon--gear" />
                <span className="im-menu-item__text">设置</span>
                <span className="im-menu-item__chevron" />
              </button>
            </section>

            <section className="im-menu-card">
              <button
                type="button"
                className="im-menu-item im-menu-item--danger"
                onClick={() => {
                  onClose()
                  setToken(null)
                  onLogout()
                }}
              >
                <span className="im-menu-item__text">退出登录</span>
              </button>
            </section>
          </>
        )}

        {view === 'hope' && (
          <div className="im-drawer__panel">
            <button type="button" className="im-link-back" onClick={() => setView('home')}>
              ‹ 返回
            </button>
            <h3 className="im-drawer__title">账号与 IHope 号</h3>
            <p className="im-muted">
              昵称可自行修改；IHope 号由系统分配，用于登录与加好友。
            </p>
            <div className="im-bind-box">
              <p className="im-muted">当前昵称</p>
              <strong className="im-bind-code" style={{ fontSize: '1.1rem' }}>
                {user.username}
              </strong>
            </div>
            <Button
              theme="primary"
              variant="outline"
              block
              onClick={() => {
                setRenameDraft(user.username)
                setRenameOpen(true)
              }}
            >
              修改昵称
            </Button>
            <div className="im-bind-box">
              <p className="im-muted">当前 IHope 号</p>
              <strong className="im-bind-code">{user.hopeId || '—'}</strong>
            </div>
            <Button variant="outline" block onClick={() => fileRef.current?.click()}>
              更换头像
            </Button>
          </div>
        )}

        {view === 'quote' && (
          <div className="im-drawer__panel im-drawer__panel--quote">
            <button type="button" className="im-link-back" onClick={() => setView('home')}>
              ‹ 返回
            </button>
            <h3 className="im-drawer__title">今日金句</h3>
            {quoteBusy ? (
              <p className="im-muted">加载中…</p>
            ) : quoteError ? (
              <>
                <p className="im-muted">{quoteError}</p>
                <Button theme="primary" variant="outline" block onClick={() => void loadQuote()}>
                  重试
                </Button>
              </>
            ) : quote ? (
              <div className="im-quote">
                {quote.date && <div className="im-quote__date">{quote.date}</div>}
                <div className="im-quote__body">{quote.body}</div>
                {quote.author ? (
                  <div className="im-quote__author">—— 来自@{quote.author}</div>
                ) : null}
              </div>
            ) : (
              <p className="im-muted">暂无金句内容</p>
            )}
          </div>
        )}

        {view === 'notify' && (
          <div className="im-drawer__panel">
            <button type="button" className="im-link-back" onClick={() => setView('home')}>
              ‹ 返回
            </button>
            <h3 className="im-drawer__title">消息提醒</h3>
            {!qq?.botEnabled ? (
              <p className="im-muted">服务器未启用 QQ 机器人。</p>
            ) : !qq.bound ? (
              <>
                <p className="im-muted">绑定官方机器人后，离线可收到提醒。</p>
                <Button
                  theme="primary"
                  size="large"
                  block
                  onClick={async () => {
                    try {
                      const res = await api.qqBindCode()
                      setBindCode(res.code)
                      setBindHint(res.botAddHint)
                    } catch (e) {
                      MessagePlugin.error(apiErrorMessage(e, '获取失败'))
                    }
                  }}
                >
                  获取绑定码
                </Button>
                {bindCode && (
                  <div className="im-bind-box">
                    <p>{bindHint}</p>
                    <strong className="im-bind-code">{bindCode}</strong>
                  </div>
                )}
              </>
            ) : (
              <>
                <div className="im-switch-row">
                  <span>离线消息提醒</span>
                  <Switch
                    value={!!qq.doorbellEnabled}
                    onChange={async (v) => {
                      try {
                        await api.qqPatch(Boolean(v))
                        setQq({ ...qq, doorbellEnabled: Boolean(v) })
                      } catch (e) {
                        MessagePlugin.error(apiErrorMessage(e, '更新失败'))
                      }
                    }}
                  />
                </div>
                <Button
                  variant="outline"
                  theme="danger"
                  block
                  onClick={async () => {
                    try {
                      await api.qqUnbind()
                      setQq({ botEnabled: true, bound: false })
                      setBindCode('')
                    } catch (e) {
                      MessagePlugin.error(apiErrorMessage(e, '解绑失败'))
                    }
                  }}
                >
                  解除绑定
                </Button>
              </>
            )}
          </div>
        )}
      </div>

      <Dialog
        visible={renameOpen}
        header="修改昵称"
        onClose={() => setRenameOpen(false)}
        confirmBtn={{ content: '保存', loading: renameBusy }}
        cancelBtn="取消"
        onConfirm={async () => {
          const name = renameDraft.trim()
          if (!name) {
            MessagePlugin.warning('请输入昵称')
            return
          }
          setRenameBusy(true)
          try {
            const u = await api.patchMe({ username: name })
            onUserChange?.(u)
            setRenameOpen(false)
            MessagePlugin.success('昵称已更新')
          } catch (e) {
            MessagePlugin.error(apiErrorMessage(e, '修改失败'))
          } finally {
            setRenameBusy(false)
          }
        }}
      >
        <p className="im-muted" style={{ marginTop: 0 }}>
          1–32 个字符，可用中文、字母、数字、空格等。
        </p>
        <Input
          autofocus
          maxlength={32}
          placeholder="昵称"
          value={renameDraft}
          onChange={(v) => setRenameDraft(String(v))}
        />
      </Dialog>
    </Drawer>
  )
}
