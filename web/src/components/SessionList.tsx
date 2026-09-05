import { ChatOffIcon, PinFilledIcon } from 'tdesign-icons-react'
import { Dropdown } from 'tdesign-react'
import type { Conversation } from '../api'
import { conversationTitle, formatMessageTime } from '../lib/chatFormat'
import { Avatar } from './Avatar'

type Props = {
  sessions: Conversation[]
  activeId: string | null
  filter: string
  onOpen: (id: string) => void
  onTogglePin: (c: Conversation) => void
  onToggleMute: (c: Conversation) => void
  onHide: (c: Conversation) => void
}

export function SessionList({
  sessions,
  activeId,
  filter,
  onOpen,
  onTogglePin,
  onToggleMute,
  onHide,
}: Props) {
  const q = filter.trim().toLowerCase()
  const filtered = sessions.filter((c) => conversationTitle(c).toLowerCase().includes(q))

  if (filtered.length === 0) {
    return <p className="im-empty-hint">暂无消息，点右上角 + 加好友或建群</p>
  }

  return (
    <div className="im-list">
      {filtered.map((c) => (
        <Dropdown
          key={c.id}
          trigger="context-menu"
          placement="bottom-left"
          minColumnWidth={148}
          maxColumnWidth={220}
          options={[
            { content: c.pinned ? '取消置顶' : '置顶', value: 'pin' },
            { content: c.muted ? '关闭免打扰' : '消息免打扰', value: 'mute' },
            { content: '从消息列表删除', value: 'hide', theme: 'error' },
          ]}
          onClick={(item) => {
            const v = String(item.value)
            if (v === 'pin') onTogglePin(c)
            else if (v === 'mute') onToggleMute(c)
            else if (v === 'hide') onHide(c)
          }}
        >
          <button
            type="button"
            className={c.id === activeId ? 'im-list-item is-active' : 'im-list-item'}
            onClick={() => onOpen(c.id)}
          >
            <Avatar
              name={conversationTitle(c)}
              src={c.avatarUrl || c.peerAvatarUrl}
              group={c.type === 'group'}
            />
            <span className="im-list-item__body">
              <span className="im-list-item__row">
                <span className="im-list-item__title">
                  <span className="im-list-item__title-text">
                    {c.pinned ? (
                      <PinFilledIcon className="im-pin-mark" size="14px" />
                    ) : null}
                    {conversationTitle(c)}
                  </span>
                  {c.muted ? (
                    <ChatOffIcon className="im-mute-mark" size="14px" />
                  ) : null}
                </span>
                <span className="im-list-item__time">
                  {formatMessageTime(c.lastMessageAt || c.createdAt)}
                </span>
              </span>
              <span className="im-list-item__row">
                <span className="im-list-item__preview">
                  {c.lastMessage ||
                    (c.type === 'group' ? `群聊 · ${c.memberCount || 0} 人` : '暂无消息')}
                </span>
                {(c.unreadCount || 0) > 0 ? (
                  <span
                    className={c.muted ? 'im-badge im-badge--muted' : 'im-badge'}
                    title={c.muted ? '消息免打扰' : undefined}
                  >
                    {(c.unreadCount || 0) > 99 ? '99+' : c.unreadCount}
                  </span>
                ) : c.muted ? (
                  <span className="im-mute-mark im-mute-mark--trail" title="消息免打扰">
                    <ChatOffIcon size="16px" />
                  </span>
                ) : null}
              </span>
            </span>
          </button>
        </Dropdown>
      ))}
    </div>
  )
}
