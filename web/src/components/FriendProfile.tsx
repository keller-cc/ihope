import { useEffect, useState } from 'react'
import { ChevronRightIcon } from 'tdesign-icons-react'
import { Button, Dialog, Input, Switch } from 'tdesign-react'
import type { Contact, Conversation } from '../api'
import { Avatar } from './Avatar'

type Props = {
  profile: Contact
  conversation?: Conversation
  onBack: () => void
  onMessage: () => void
  onSaveRemark: (remark: string) => Promise<void>
  onTogglePin?: () => void
  onToggleMute?: () => void
  onFindHistory?: () => void
  showBack: boolean
}

export function FriendProfile({
  profile,
  conversation,
  onBack,
  onMessage,
  onSaveRemark,
  onTogglePin,
  onToggleMute,
  onFindHistory,
  showBack,
}: Props) {
  const [remark, setRemark] = useState(profile.remark || '')
  const [remarkOpen, setRemarkOpen] = useState(false)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    setRemark(profile.remark || '')
  }, [profile.id, profile.remark])

  const displayName = profile.remark?.trim() || profile.username
  const showOriginalName =
    !!profile.username && profile.remark?.trim() !== '' && profile.remark.trim() !== profile.username

  return (
    <section className="im-pane im-pane--settings">
      <header className="im-chat-head">
        {showBack && (
          <button type="button" className="im-back" style={{ display: 'grid' }} onClick={onBack}>
            ‹
          </button>
        )}
        <h2 className="im-chat-head__title">资料设置</h2>
      </header>

      <div className="im-settings-scroll">
        <div className="im-set-hero">
          <Avatar name={displayName} src={profile.avatarUrl} size="xl" />
          <div className="im-set-hero__meta">
            <strong>{displayName}</strong>
            {showOriginalName && <span>昵称：{profile.username}</span>}
            {profile.hopeId && <span>IHope 号：{profile.hopeId}</span>}
            {profile.email && <span>{profile.email}</span>}
          </div>
        </div>

        <div className="im-set-group">
          <button type="button" className="im-set-cell" onClick={() => setRemarkOpen(true)}>
            <span className="im-set-cell__label">设置备注</span>
            <span className="im-set-cell__value">{profile.remark?.trim() || '未设置'}</span>
            <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
          </button>
          {onFindHistory && (
            <button type="button" className="im-set-cell" onClick={onFindHistory}>
              <span className="im-set-cell__label">查找聊天记录</span>
              <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
            </button>
          )}
        </div>

        {conversation && (onTogglePin || onToggleMute) && (
          <div className="im-set-group">
            {onTogglePin && (
              <div className="im-set-cell im-set-cell--switch">
                <span className="im-set-cell__label">置顶聊天</span>
                <Switch value={!!conversation.pinned} onChange={() => onTogglePin()} />
              </div>
            )}
            {onToggleMute && (
              <div className="im-set-cell im-set-cell--switch">
                <span className="im-set-cell__label">消息免打扰</span>
                <Switch value={!!conversation.muted} onChange={() => onToggleMute()} />
              </div>
            )}
          </div>
        )}

        <div className="im-set-actions">
          <Button theme="primary" block onClick={onMessage}>
            发消息
          </Button>
        </div>
      </div>

      <Dialog
        visible={remarkOpen}
        header="设置备注"
        onClose={() => {
          setRemark(profile.remark || '')
          setRemarkOpen(false)
        }}
        onConfirm={async () => {
          setBusy(true)
          try {
            await onSaveRemark(remark.trim())
            setRemarkOpen(false)
          } finally {
            setBusy(false)
          }
        }}
        confirmBtn={{ content: '保存', loading: busy }}
        cancelBtn="取消"
      >
        <Input
          autofocus
          placeholder="备注名"
          value={remark}
          onChange={(v) => setRemark(String(v))}
        />
      </Dialog>
    </section>
  )
}
