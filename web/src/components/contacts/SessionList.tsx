import type { ReactElement } from 'react'
import {
  ChatOffIcon,
  CheckIcon,
  DeleteIcon,
  FileCopyIcon,
  PinFilledIcon,
  PinIcon,
} from 'tdesign-icons-react'
import { Dropdown, MessagePlugin } from 'tdesign-react'
import type { Conversation } from '@/api'
import { conversationTitle, formatMessageTime } from '@/lib/chatFormat'
import { fuzzyIncludes } from '@/lib/fuzzyIncludes'
import { Avatar } from '@/components/Avatar'

type Props = {
  sessions: Conversation[]
  activeId: string | null
  filter: string
  onOpen: (id: string) => void
  onTogglePin: (c: Conversation) => void
  onToggleMute: (c: Conversation) => void
  onMarkRead: (c: Conversation) => void
  onHide: (c: Conversation) => void
}

async function copyText(text: string, okTip: string) {
  const v = text.trim()
  if (!v) {
    MessagePlugin.warning('无可复制内容')
    return
  }
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(v)
    } else {
      const ta = document.createElement('textarea')
      ta.value = v
      ta.setAttribute('readonly', '')
      ta.style.position = 'fixed'
      ta.style.left = '-9999px'
      document.body.appendChild(ta)
      ta.select()
      const ok = document.execCommand('copy')
      document.body.removeChild(ta)
      if (!ok) throw new Error('copy failed')
    }
    MessagePlugin.success(okTip)
  } catch {
    MessagePlugin.error('复制失败')
  }
}

function menuIcon(node: ReactElement) {
  return <span className="im-session-menu__ico">{node}</span>
}

export function SessionList({
  sessions,
  activeId,
  filter,
  onOpen,
  onTogglePin,
  onToggleMute,
  onMarkRead,
  onHide,
}: Props) {
  const q = filter.trim()
  const filtered = sessions.filter(
    (c) =>
      fuzzyIncludes(conversationTitle(c), q) ||
      fuzzyIncludes(c.peerUsername || '', q) ||
      fuzzyIncludes(c.groupNo || '', q) ||
      fuzzyIncludes(c.peerHopeId || '', q),
  )

  if (filtered.length === 0) {
    return <p className="im-empty-hint">暂无消息，点右上角 + 加好友或建群</p>
  }

  return (
    <div className="im-list">
      {filtered.map((c) => {
        const copyOpts =
          c.type === 'group' && c.groupNo
            ? [
                {
                  content: '复制群号',
                  value: 'copy-group',
                  prefixIcon: menuIcon(<FileCopyIcon size="16px" />),
                },
              ]
            : c.type === 'dm' && c.peerHopeId
              ? [
                  {
                    content: '复制 IHope 号',
                    value: 'copy-hope',
                    prefixIcon: menuIcon(<FileCopyIcon size="16px" />),
                  },
                ]
              : []

        const options = c.removed
          ? [
              {
                content: '删除会话',
                value: 'hide',
                theme: 'error' as const,
                prefixIcon: menuIcon(<DeleteIcon size="16px" />),
              },
            ]
          : [
              {
                content: c.pinned ? '取消置顶' : '置顶',
                value: 'pin',
                prefixIcon: menuIcon(
                  c.pinned ? <PinFilledIcon size="16px" /> : <PinIcon size="16px" />,
                ),
              },
              {
                content: '标为已读',
                value: 'read',
                prefixIcon: menuIcon(<CheckIcon size="16px" />),
              },
              ...copyOpts,
              {
                content: c.muted ? '关闭免打扰' : '消息免打扰',
                value: 'mute',
                prefixIcon: menuIcon(<ChatOffIcon size="16px" />),
              },
              {
                content: '从消息列表删除',
                value: 'hide',
                theme: 'error' as const,
                prefixIcon: menuIcon(<DeleteIcon size="16px" />),
              },
            ]

        return (
          <Dropdown
            key={c.id}
            trigger="context-menu"
            placement="bottom-left"
            minColumnWidth={168}
            maxColumnWidth={240}
            options={options}
            onClick={(item) => {
              const v = String(item.value)
              if (v === 'pin') onTogglePin(c)
              else if (v === 'read') onMarkRead(c)
              else if (v === 'mute') onToggleMute(c)
              else if (v === 'hide') onHide(c)
              else if (v === 'copy-group') void copyText(c.groupNo || '', '群号已复制')
              else if (v === 'copy-hope')
                void copyText(c.peerHopeId || '', 'IHope 号已复制')
            }}
          >
            <button
              type="button"
              className={c.id === activeId ? 'im-list-item is-active' : 'im-list-item'}
              onClick={() => onOpen(c.id)}
            >
              <Avatar
                name={conversationTitle(c)}
                src={c.type === 'dm' ? c.avatarUrl || c.peerAvatarUrl : c.avatarUrl}
                faces={c.type === 'group' ? c.memberFaces : undefined}
                group={c.type === 'group'}
              />
              <span className="im-list-item__body">
                <span className="im-list-item__row">
                  <span className="im-list-item__title">
                    {c.pinned ? (
                      <PinFilledIcon className="im-pin-mark" size="14px" />
                    ) : null}
                    <span className="im-list-item__title-text">{conversationTitle(c)}</span>
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
                    {c.removed
                      ? c.removeReason === 'dissolved' || c.dissolved
                        ? '该群聊已解散'
                        : c.removeReason === 'kicked'
                          ? '你已被移出群聊'
                          : c.removeReason === 'unfriended'
                            ? '已删除好友'
                            : c.type === 'dm'
                              ? '已删除好友'
                              : '已退出群聊'
                      : (
                        <>
                          {c.mentionHomeTip ? (
                            <span className="im-mention-home-tip">有人@我 </span>
                          ) : null}
                          {c.lastMessage ||
                            (c.type === 'group'
                              ? `群聊 · ${c.memberCount || 0} 人`
                              : '暂无消息')}
                        </>
                      )}
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
        )
      })}
    </div>
  )
}
