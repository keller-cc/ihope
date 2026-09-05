import { useEffect, useRef, useState } from 'react'
import {
  ChatSettingIcon,
  FolderOpenIcon,
  ImageIcon,
  SearchIcon,
  SmileIcon,
  SoundMute1Icon,
} from 'tdesign-icons-react'
import { Button, Dialog, MessagePlugin, Popup, Textarea } from 'tdesign-react'
import type { Conversation, Message, User } from '../api'
import {
  conversationTitle,
  formatFileSize,
  formatMessageTimeDivider,
  messageCopyText,
  parseFileBody,
  parseForwardBody,
  parseImageBody,
  shouldShowMessageTimeDivider,
} from '../lib/chatFormat'
import { CHAT_EMOJIS } from '../lib/emojis'
import { chatBgStyle } from '../lib/chatBg'
import { Avatar } from './Avatar'
import { ImageViewer } from './ImageViewer'

type Props = {
  user: User
  conversation: Conversation | undefined
  messages: Message[]
  draft: string
  onDraft: (v: string) => void
  onSend: () => void
  onSendImage: (file: File) => void
  onSendFile: (file: File) => void
  onRecall: (messageId: string) => void
  onForward?: (messageIds: string[]) => void
  onOpenHistory?: () => void
  sendingMedia?: boolean
  hasMore?: boolean
  loadingMore?: boolean
  onLoadMore?: () => void
  onBack: () => void
  onOpenProfile?: () => void
  listRef: React.RefObject<HTMLDivElement | null>
  showBack: boolean
  focusMessageId?: string | null
  selectMode?: boolean
  selectedIds?: string[]
  onSelectModeChange?: (on: boolean) => void
  onToggleSelect?: (messageId: string) => void
}

type MsgMenu = {
  messageId: string
  x: number
  y: number
  canRecall: boolean
  canCopy: boolean
  canForward: boolean
  copyText: string
  recallLabel: string
}

function canForwardMessage(m: Message): boolean {
  if (m.recalled) return false
  return m.type === 'text' || m.type === 'image' || m.type === 'file'
}

function canRecallMessage(
  m: Message,
  user: User,
  conversation: Conversation | undefined,
): boolean {
  if (m.recalled) return false
  const ageMs = Date.now() - new Date(m.createdAt).getTime()
  if (m.senderId === user.id && ageMs <= 2 * 60 * 1000) return true
  if (conversation?.type === 'group' && (conversation.isOwner || conversation.isAdmin)) {
    return true
  }
  return false
}

function recallMenuLabel(
  m: Message,
  user: User,
  conversation: Conversation | undefined,
): string {
  if (m.senderId === user.id) return '撤回'
  if (conversation?.type === 'group' && (conversation.isOwner || conversation.isAdmin)) {
    return '撤回（管理员）'
  }
  return '撤回'
}

function recalledHint(m: Message, user: User): string {
  const by = m.recalledBy
  if (!by) return '消息已撤回'
  const ownRecall = by === m.senderId
  if (ownRecall) {
    return by === user.id ? '你撤回了一条消息' : `${m.senderUsername || '对方'}撤回了一条消息`
  }
  return by === user.id ? '你撤回了一条成员消息' : '管理员撤回了一条成员消息'
}

const LONG_PRESS_MS = 480

async function copyToClipboard(text: string): Promise<void> {
  if (!text) throw new Error('empty')
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text)
      return
    } catch {
      /* fall through — insecure context / permission */
    }
  }
  const ta = document.createElement('textarea')
  ta.value = text
  ta.setAttribute('readonly', '')
  ta.style.position = 'fixed'
  ta.style.left = '-9999px'
  ta.style.top = '0'
  document.body.appendChild(ta)
  ta.select()
  const ok = document.execCommand('copy')
  document.body.removeChild(ta)
  if (!ok) throw new Error('copy failed')
}

export function ChatPane({
  user,
  conversation,
  messages,
  draft,
  onDraft,
  onSend,
  onSendImage,
  onSendFile,
  onRecall,
  onForward,
  onOpenHistory,
  sendingMedia,
  hasMore,
  loadingMore,
  onLoadMore,
  onBack,
  onOpenProfile,
  listRef,
  showBack,
  focusMessageId,
  selectMode,
  selectedIds = [],
  onSelectModeChange,
  onToggleSelect,
}: Props) {
  const imageRef = useRef<HTMLInputElement>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const pressTimer = useRef<number | null>(null)
  const ignoreClickUntil = useRef(0)
  const [viewer, setViewer] = useState<{ thumb: string; url: string } | null>(null)
  const [emojiOpen, setEmojiOpen] = useState(false)
  const [menu, setMenu] = useState<MsgMenu | null>(null)
  const [forwardDetail, setForwardDetail] = useState<Message | null>(null)

  useEffect(() => {
    if (!focusMessageId || !listRef.current) return
    const el = listRef.current.querySelector(
      `[data-msg-id="${CSS.escape(focusMessageId)}"]`,
    ) as HTMLElement | null
    el?.scrollIntoView({ block: 'center', behavior: 'smooth' })
  }, [focusMessageId, messages, listRef])

  useEffect(() => {
    if (!menu) return
    const close = () => setMenu(null)
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close()
    }
    // delay so the opening click / contextmenu doesn't instantly dismiss
    const t = window.setTimeout(() => {
      window.addEventListener('pointerdown', close)
      window.addEventListener('scroll', close, true)
    }, 0)
    window.addEventListener('keydown', onKey)
    return () => {
      window.clearTimeout(t)
      window.removeEventListener('pointerdown', close)
      window.removeEventListener('scroll', close, true)
      window.removeEventListener('keydown', onKey)
    }
  }, [menu])

  const clearPress = () => {
    if (pressTimer.current != null) {
      window.clearTimeout(pressTimer.current)
      pressTimer.current = null
    }
  }

  const openMenuFor = (m: Message, clientX: number, clientY: number) => {
    if (selectMode) return
    const copyText = messageCopyText(m)
    const canRecall = canRecallMessage(m, user, conversation)
    const canCopy = !!copyText
    const canForward = canForwardMessage(m) && !!onForward
    if (!canRecall && !canCopy && !canForward) return
    ignoreClickUntil.current = Date.now() + 450
    setMenu({
      messageId: m.id,
      x: Math.min(clientX, window.innerWidth - 140),
      y: Math.min(clientY, window.innerHeight - 160),
      canRecall,
      canCopy,
      canForward,
      copyText,
      recallLabel: recallMenuLabel(m, user, conversation),
    })
  }

  const bindPressHandlers = (m: Message) => ({
    onContextMenu: (e: React.MouseEvent) => {
      e.preventDefault()
      e.stopPropagation()
      openMenuFor(m, e.clientX, e.clientY)
    },
    onPointerDown: (e: React.PointerEvent) => {
      if (e.pointerType === 'mouse' && e.button !== 0) return
      clearPress()
      const { clientX, clientY } = e
      pressTimer.current = window.setTimeout(() => {
        pressTimer.current = null
        openMenuFor(m, clientX, clientY)
      }, LONG_PRESS_MS)
    },
    onPointerUp: clearPress,
    onPointerCancel: clearPress,
    onPointerLeave: clearPress,
    onClick: (e: React.MouseEvent) => {
      if (Date.now() < ignoreClickUntil.current) {
        e.preventDefault()
        e.stopPropagation()
      }
    },
  })

  const handlePaste = (e: React.ClipboardEvent) => {
    if (!conversation || sendingMedia) return
    const dt = e.clipboardData
    if (!dt) return

    const files: File[] = []
    if (dt.items?.length) {
      for (const item of Array.from(dt.items)) {
        if (item.kind !== 'file') continue
        const f = item.getAsFile()
        if (f && f.size > 0) files.push(f)
      }
    }
    if (!files.length && dt.files?.length) {
      for (const f of Array.from(dt.files)) {
        if (f.size > 0) files.push(f)
      }
    }
    if (!files.length) return

    e.preventDefault()
    const isImage = (f: File) =>
      f.type.startsWith('image/') || /\.(png|jpe?g|gif|webp|bmp|heic)$/i.test(f.name)
    const image = files.find(isImage)
    const file = image || files[0]
    if (isImage(file)) onSendImage(file)
    else onSendFile(file)
  }

  const subtitle =
    conversation?.type === 'group'
      ? conversation.groupNo
        ? `群号 ${conversation.groupNo}`
        : `${conversation.memberCount || 0} 人`
      : null

  return (
    <section className="im-pane">
      <header className="im-chat-head">
        {showBack && !selectMode && (
          <button type="button" className="im-back" onClick={onBack}>
            ‹
          </button>
        )}
        {selectMode ? (
          <div className="im-chat-head__main">
            <h2 className="im-chat-head__title">
              {selectedIds.length > 0 ? `已选择 ${selectedIds.length} 条消息` : '选择消息'}
            </h2>
          </div>
        ) : (
          <>
            <div className="im-chat-head__main">
              <h2 className="im-chat-head__title">
                <span className="im-chat-head__title-text">
                  {conversation ? conversationTitle(conversation) : '会话'}
                </span>
                {conversation?.muted ? (
                  <SoundMute1Icon
                    className="im-mute-mark im-mute-mark--head"
                    size="16px"
                  />
                ) : null}
              </h2>
              {subtitle && <span className="im-chat-head__sub">{subtitle}</span>}
            </div>
            {onOpenHistory && (
              <button
                type="button"
                className="im-head-icon-btn"
                title="查找聊天记录"
                aria-label="查找聊天记录"
                onClick={onOpenHistory}
              >
                <SearchIcon size="20px" />
              </button>
            )}
            {onOpenProfile && (
              <button
                type="button"
                className="im-head-icon-btn"
                title="资料"
                aria-label="资料"
                onClick={onOpenProfile}
              >
                <ChatSettingIcon size="20px" />
              </button>
            )}
          </>
        )}
      </header>

      <div className="im-messages" ref={listRef} style={chatBgStyle(user.chatBg)}>
        {hasMore && (
          <button
            type="button"
            className="im-load-more"
            disabled={loadingMore}
            onClick={onLoadMore}
          >
            {loadingMore ? '加载中…' : '加载更早的消息'}
          </button>
        )}
        {messages.map((m, i) => {
          const mine = m.senderId === user.id
          const isGroup = conversation?.type === 'group'
          const name = mine
            ? user.username
            : m.senderUsername ||
            (isGroup
              ? '成员'
              : conversation
                ? conversationTitle(conversation)
                : '好友')
          const avatarSrc = mine ? user.avatarUrl : m.senderAvatarUrl
          const img = !m.recalled && m.type === 'image' ? parseImageBody(m.body) : null
          const file = !m.recalled && m.type === 'file' ? parseFileBody(m.body) : null
          const fwd = !m.recalled && m.type === 'forward' ? parseForwardBody(m.body) : null
          const press = m.recalled || selectMode ? null : bindPressHandlers(m)
          const showMeta = isGroup
          const showTime = shouldShowMessageTimeDivider(
            messages[i - 1]?.createdAt,
            m.createdAt,
          )
          const selected = selectedIds.includes(m.id)
          const focused = focusMessageId === m.id
          const selectable = !!selectMode && canForwardMessage(m)
          return (
            <div
              key={m.id}
              data-msg-id={m.id}
              className={focused ? 'im-msg-block im-msg-block--focus' : 'im-msg-block'}
            >
              {showTime && (
                <div className="im-msg-time">{formatMessageTimeDivider(m.createdAt)}</div>
              )}
              <div
                className={
                  selectMode
                    ? mine
                      ? 'im-msg-select-row im-msg-select-row--mine'
                      : 'im-msg-select-row'
                    : 'im-msg-select-row--off'
                }
              >
                {selectMode && (
                  <button
                    type="button"
                    className={
                      'im-msg__check' +
                      (selected ? ' is-on' : '') +
                      (!selectable ? ' is-disabled' : '')
                    }
                    aria-label={selected ? '取消选择' : '选择'}
                    aria-pressed={selected}
                    disabled={!selectable}
                    onClick={(e) => {
                      e.stopPropagation()
                      if (selectable) onToggleSelect?.(m.id)
                    }}
                  />
                )}
                <div
                  className={
                    (mine ? 'im-msg im-msg--mine' : 'im-msg') +
                    (selectable ? ' im-msg--selectable' : '') +
                    (selectMode ? ' im-msg--in-select' : '')
                  }
                  onClick={() => {
                    if (selectable) onToggleSelect?.(m.id)
                  }}
                >
                <Avatar name={name} src={avatarSrc} size="sm" />
                <div className="im-msg__main">
                  {showMeta && (
                    <div className="im-msg__meta">
                      {mine && m.senderTitle ? (
                        <span className="im-role-badge im-role-badge--inline">
                          {m.senderTitle}
                        </span>
                      ) : null}
                      <span className="im-msg__name">{name}</span>
                      {!mine && m.senderTitle ? (
                        <span className="im-role-badge im-role-badge--inline">
                          {m.senderTitle}
                        </span>
                      ) : null}
                    </div>
                  )}
                  {m.recalled ? (
                    <div className="im-msg__recalled">{recalledHint(m, user)}</div>
                  ) : img ? (
                    <button
                      type="button"
                      className="im-msg__image"
                      {...press}
                      onClick={(e) => {
                        if (selectMode) return
                        press?.onClick(e)
                        if (Date.now() < ignoreClickUntil.current) return
                        setViewer({ thumb: img.thumbUrl, url: img.url })
                      }}
                    >
                      <img
                        src={img.thumbUrl}
                        alt=""
                        loading="lazy"
                        draggable={false}
                        style={
                          img.w && img.h
                            ? {
                              aspectRatio: `${img.w} / ${img.h}`,
                              maxWidth: 220,
                              maxHeight: 280,
                            }
                            : undefined
                        }
                      />
                    </button>
                  ) : file ? (
                    <a
                      className="im-msg__file"
                      href={selectMode ? undefined : file.url}
                      download={file.name}
                      target="_blank"
                      rel="noreferrer"
                      {...press}
                      onClick={(e) => {
                        if (selectMode) {
                          e.preventDefault()
                          return
                        }
                        press?.onClick(e)
                        if (Date.now() < ignoreClickUntil.current) e.preventDefault()
                      }}
                    >
                      <span className="im-msg__file-icon">📄</span>
                      <span>
                        <strong>{file.name}</strong>
                        <span className="im-muted">{formatFileSize(file.size)}</span>
                      </span>
                    </a>
                  ) : fwd ? (
                    <button
                      type="button"
                      className="im-msg__forward"
                      {...press}
                      onClick={(e) => {
                        if (selectMode) return
                        press?.onClick(e)
                        if (Date.now() < ignoreClickUntil.current) return
                        setForwardDetail(m)
                      }}
                    >
                      <div className="im-msg__forward-title">{fwd.fromTitle}的聊天记录</div>
                      <div className="im-msg__forward-items">
                        {fwd.items.slice(0, 4).map((it, idx) => (
                          <div key={idx} className="im-msg__forward-line">
                            <span>{it.senderName}：</span>
                            {it.type === 'image'
                              ? '[图片]'
                              : it.type === 'file'
                                ? `[文件]${it.name || ''}`
                                : it.body || ''}
                          </div>
                        ))}
                        {fwd.items.length > 4 && (
                          <div className="im-msg__forward-more">共 {fwd.items.length} 条</div>
                        )}
                      </div>
                    </button>
                  ) : (
                    <div className="im-msg__bubble" {...press}>
                      {m.body}
                    </div>
                  )}
                </div>
                </div>
              </div>
            </div>
          )
        })}
      </div>

      {!selectMode && (
        <footer className="im-composer" onPaste={handlePaste}>
          <div className="im-composer__tools">
            <Popup
              visible={emojiOpen}
              onVisibleChange={setEmojiOpen}
              trigger="click"
              placement="top-left"
              content={
                <div className="im-emoji-panel">
                  {CHAT_EMOJIS.map((e) => (
                    <button
                      key={e}
                      type="button"
                      className="im-emoji-btn"
                      onClick={() => {
                        onDraft(draft + e)
                        setEmojiOpen(false)
                      }}
                    >
                      {e}
                    </button>
                  ))}
                </div>
              }
            >
              <button type="button" className="im-composer__tool" title="表情" aria-label="表情">
                <SmileIcon size="22px" />
              </button>
            </Popup>
            <button
              type="button"
              className="im-composer__tool"
              title="发送图片"
              aria-label="发送图片"
              disabled={sendingMedia || !conversation}
              onClick={() => imageRef.current?.click()}
            >
              <ImageIcon size="22px" />
            </button>
            <button
              type="button"
              className="im-composer__tool"
              title="发送文件"
              aria-label="发送文件"
              disabled={sendingMedia || !conversation}
              onClick={() => fileRef.current?.click()}
            >
              <FolderOpenIcon size="22px" />
            </button>
            <input
              ref={imageRef}
              type="file"
              accept="image/*"
              hidden
              onChange={(e) => {
                const file = e.target.files?.[0]
                e.target.value = ''
                if (file) onSendImage(file)
              }}
            />
            <input
              ref={fileRef}
              type="file"
              hidden
              onChange={(e) => {
                const file = e.target.files?.[0]
                e.target.value = ''
                if (file) onSendFile(file)
              }}
            />
          </div>

          <Textarea
            className="im-composer__input"
            value={draft}
            onChange={(v) => onDraft(String(v))}
            placeholder="输入消息"
            autosize={{ minRows: 3, maxRows: 8 }}
            onKeydown={(_value, { e }) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault()
                onSend()
              }
            }}
          />

          <div className="im-composer__bar">
            <span className="im-composer__tip">Enter 发送 · 可粘贴图片/文件</span>
            <Button
              className="im-composer__send"
              theme="primary"
              size="small"
              disabled={!draft.trim()}
              onClick={onSend}
            >
              发送(S)
            </Button>
          </div>
        </footer>
      )}

      {selectMode && (
        <footer className="im-select-bar">
          <button
            type="button"
            className="im-select-bar__close"
            title="关闭"
            aria-label="关闭多选"
            onClick={() => onSelectModeChange?.(false)}
          >
            ×
          </button>
          <div className="im-select-bar__actions">
            <button
              type="button"
              className="im-select-bar__action"
              disabled={!selectedIds.length}
              onClick={() => onForward?.(selectedIds)}
            >
              <span className="im-select-bar__action-ico" aria-hidden>
                ↗
              </span>
              <em>转发</em>
            </button>
          </div>
        </footer>
      )}

      {menu && (
        <div
          className="im-msg-menu"
          style={{ left: menu.x, top: menu.y }}
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => e.stopPropagation()}
          role="menu"
        >
          {menu.canCopy && (
            <button
              type="button"
              role="menuitem"
              onClick={async () => {
                try {
                  await copyToClipboard(menu.copyText)
                  MessagePlugin.success('已复制')
                } catch {
                  MessagePlugin.error('复制失败')
                }
                setMenu(null)
              }}
            >
              复制
            </button>
          )}
          {menu.canForward && (
            <button
              type="button"
              role="menuitem"
              onClick={() => {
                const id = menu.messageId
                setMenu(null)
                onForward?.([id])
              }}
            >
              转发
            </button>
          )}
          {menu.canForward && onSelectModeChange && (
            <button
              type="button"
              role="menuitem"
              onClick={() => {
                const id = menu.messageId
                setMenu(null)
                onSelectModeChange(true)
                onToggleSelect?.(id)
              }}
            >
              多选
            </button>
          )}
          {menu.canRecall && (
            <button
              type="button"
              role="menuitem"
              onClick={() => {
                const id = menu.messageId
                setMenu(null)
                onRecall(id)
              }}
            >
              {menu.recallLabel}
            </button>
          )}
        </div>
      )}

      <ImageViewer
        open={!!viewer}
        thumbUrl={viewer?.thumb || ''}
        originalUrl={viewer?.url || ''}
        onClose={() => setViewer(null)}
      />

      <Dialog
        visible={!!forwardDetail}
        header="聊天记录"
        onClose={() => setForwardDetail(null)}
        footer={
          <Button theme="default" onClick={() => setForwardDetail(null)}>
            关闭
          </Button>
        }
        width={420}
      >
        {forwardDetail &&
          (() => {
            const fwd = parseForwardBody(forwardDetail.body)
            if (!fwd) return null
            return (
              <div className="im-forward-detail">
                <p className="im-muted">{fwd.fromTitle}的聊天记录</p>
                {fwd.items.map((it, idx) => (
                  <div key={idx} className="im-forward-detail__row">
                    <strong>{it.senderName}</strong>
                    <div>
                      {it.type === 'image' && it.thumbUrl ? (
                        <button
                          type="button"
                          className="im-msg__image"
                          onClick={() =>
                            setViewer({
                              thumb: it.thumbUrl || '',
                              url: it.url || it.thumbUrl || '',
                            })
                          }
                        >
                          <img src={it.thumbUrl} alt="" />
                        </button>
                      ) : it.type === 'file' ? (
                        <a href={it.url} target="_blank" rel="noreferrer">
                          {it.name || '文件'}
                        </a>
                      ) : (
                        it.body
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )
          })()}
      </Dialog>
    </section>
  )
}
