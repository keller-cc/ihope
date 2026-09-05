import { useEffect, useRef, useState } from 'react'
import {
  CallIcon,
  ChatOffIcon,
  ChatSettingIcon,
  FolderOpenIcon,
  ImageIcon,
  KeyboardIcon,
  Microphone1Icon,
  SearchIcon,
  SmileIcon,
  VideoCamera1Icon,
} from 'tdesign-icons-react'
import { Button, Dialog, MessagePlugin, Popup, Textarea } from 'tdesign-react'
import type { Conversation, Message, User } from '../api'
import {
  conversationTitle,
  formatFileSize,
  formatMessageTimeDivider,
  formatVoiceDuration,
  formatCallMessage,
  messageCopyText,
  parseFileBody,
  parseForwardBody,
  parseImageBody,
  parseVoiceBody,
  parseCallBody,
  shouldShowMessageTimeDivider,
} from '../lib/chatFormat'
import { CHAT_EMOJIS } from '../lib/emojis'
import { chatBgStyle, resolveUserTheme } from '../lib/chatBg'
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
  onSendVoice: (blob: Blob, duration: number, mime: string) => void
  onRecall: (messageId: string) => void
  onForward?: (messageIds: string[]) => void
  onOpenHistory?: () => void
  sendingMedia?: boolean
  hasMore?: boolean
  loadingMore?: boolean
  onLoadMore?: () => void
  onBack: () => void
  onOpenProfile?: () => void
  onVoiceCall?: () => void
  onVideoCall?: () => void
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
  return m.type === 'text' || m.type === 'image' || m.type === 'file' || m.type === 'voice'
}

function canRecallMessage(
  m: Message,
  user: User,
  conversation: Conversation | undefined,
): boolean {
  if (m.recalled) return false
  const isGroupAdmin =
    conversation?.type === 'group' && (conversation.isOwner || conversation.isAdmin)
  // 群主/管理员可随时撤回任意消息（含自己超时的）
  if (isGroupAdmin) return true
  // 私聊与普通成员：仅本人消息，且 5 分钟内
  if (m.senderId !== user.id) return false
  const ageMs = Date.now() - new Date(m.createdAt).getTime()
  return ageMs <= 5 * 60 * 1000
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
  onSendVoice,
  onRecall,
  onForward,
  onOpenHistory,
  sendingMedia,
  hasMore,
  loadingMore,
  onLoadMore,
  onBack,
  onOpenProfile,
  onVoiceCall,
  onVideoCall,
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
  const theme = resolveUserTheme(user)
  const texture = theme?.texture && theme.texture !== 'none' ? theme.texture : null
  const pressTimer = useRef<number | null>(null)
  const ignoreClickUntil = useRef(0)
  const [viewer, setViewer] = useState<{ thumb: string; url: string } | null>(null)
  const [emojiOpen, setEmojiOpen] = useState(false)
  const [menu, setMenu] = useState<MsgMenu | null>(null)
  const [forwardDetail, setForwardDetail] = useState<Message | null>(null)
  const [voiceMode, setVoiceMode] = useState(false)
  const [recording, setRecording] = useState(false)
  const [willCancel, setWillCancel] = useState(false)
  const [recSec, setRecSec] = useState(0)
  const mediaRec = useRef<MediaRecorder | null>(null)
  const recChunks = useRef<Blob[]>([])
  const recStartedAt = useRef(0)
  const recTimer = useRef<number | null>(null)
  const recMime = useRef('audio/webm')
  const recStream = useRef<MediaStream | null>(null)
  const pressActive = useRef(false)
  const pressStartY = useRef(0)
  const recCancelRef = useRef(false)

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

  const stopRecTracks = () => {
    recStream.current?.getTracks().forEach((t) => t.stop())
    recStream.current = null
  }

  const clearRecTimer = () => {
    if (recTimer.current != null) {
      window.clearInterval(recTimer.current)
      recTimer.current = null
    }
  }

  useEffect(() => {
    return () => {
      clearRecTimer()
      try {
        mediaRec.current?.stop()
      } catch {
        /* ignore */
      }
      stopRecTracks()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const startVoiceRecord = async () => {
    if (recording || sendingMedia || !conversation) return
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      if (!pressActive.current) {
        stream.getTracks().forEach((t) => t.stop())
        return
      }
      recStream.current = stream
      const candidates = [
        'audio/webm;codecs=opus',
        'audio/webm',
        'audio/ogg;codecs=opus',
        'audio/mp4',
      ]
      const mime =
        candidates.find((c) => MediaRecorder.isTypeSupported(c)) || ''
      recMime.current = mime || 'audio/webm'
      const rec = mime
        ? new MediaRecorder(stream, { mimeType: mime })
        : new MediaRecorder(stream)
      recChunks.current = []
      rec.ondataavailable = (e) => {
        if (e.data.size > 0) recChunks.current.push(e.data)
      }
      rec.onstop = () => {
        clearRecTimer()
        const cancelled = recCancelRef.current
        setRecording(false)
        setWillCancel(false)
        setRecSec(0)
        const elapsed = (Date.now() - recStartedAt.current) / 1000
        stopRecTracks()
        const blob = new Blob(recChunks.current, {
          type: recMime.current || 'audio/webm',
        })
        recChunks.current = []
        mediaRec.current = null
        recCancelRef.current = false
        if (cancelled) return
        if (elapsed < 0.5 || blob.size < 200) {
          MessagePlugin.warning('说话时间太短')
          return
        }
        onSendVoice(blob, Math.min(60, elapsed), recMime.current || blob.type || 'audio/webm')
      }
      mediaRec.current = rec
      recStartedAt.current = Date.now()
      setRecSec(0)
      setRecording(true)
      rec.start(200)
      recTimer.current = window.setInterval(() => {
        const s = (Date.now() - recStartedAt.current) / 1000
        setRecSec(s)
        if (s >= 60) {
          recCancelRef.current = false
          setWillCancel(false)
          try {
            rec.stop()
          } catch {
            /* ignore */
          }
        }
      }, 200)
    } catch {
      MessagePlugin.error('无法使用麦克风，请检查权限')
      pressActive.current = false
      setRecording(false)
      setWillCancel(false)
      stopRecTracks()
    }
  }

  const endVoiceRecord = () => {
    pressActive.current = false
    const rec = mediaRec.current
    if (!rec || rec.state === 'inactive') {
      setRecording(false)
      setWillCancel(false)
      clearRecTimer()
      stopRecTracks()
      return
    }
    try {
      rec.stop()
    } catch {
      setRecording(false)
      setWillCancel(false)
      clearRecTimer()
      stopRecTracks()
    }
  }

  const cancelVoiceRecord = () => {
    pressActive.current = false
    recCancelRef.current = true
    setWillCancel(true)
    const rec = mediaRec.current
    if (rec) {
      try {
        rec.stop()
      } catch {
        clearRecTimer()
        setRecording(false)
        setWillCancel(false)
        stopRecTracks()
        recChunks.current = []
        mediaRec.current = null
        recCancelRef.current = false
      }
    } else {
      clearRecTimer()
      setRecording(false)
      setWillCancel(false)
      stopRecTracks()
      recCancelRef.current = false
    }
  }

  const onHoldPointerDown = (e: React.PointerEvent<HTMLButtonElement>) => {
    if (sendingMedia || !conversation) return
    e.preventDefault()
    e.currentTarget.setPointerCapture(e.pointerId)
    pressActive.current = true
    recCancelRef.current = false
    setWillCancel(false)
    pressStartY.current = e.clientY
    void startVoiceRecord()
  }

  const onHoldPointerMove = (e: React.PointerEvent<HTMLButtonElement>) => {
    if (!pressActive.current) return
    const up = pressStartY.current - e.clientY
    const cancel = up > 56
    if (cancel !== recCancelRef.current) {
      recCancelRef.current = cancel
      setWillCancel(cancel)
    }
  }

  const onHoldPointerUp = () => {
    if (recCancelRef.current) cancelVoiceRecord()
    else endVoiceRecord()
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
      recallLabel: '撤回',
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
      {recording && (
        <div
          className={willCancel ? 'im-voice-hud is-cancel' : 'im-voice-hud'}
          aria-live="polite"
        >
          <div className="im-voice-hud__card">
            <div className="im-voice-hud__waves" aria-hidden>
              <i />
              <i />
              <i />
              <i />
              <i />
            </div>
            <div className="im-voice-hud__sec">
              {Math.min(60, Math.ceil(recSec))}″
            </div>
            <div className="im-voice-hud__hint">
              {willCancel ? '松开手指，取消发送' : '手指上滑，取消发送'}
            </div>
          </div>
        </div>
      )}
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
                  <ChatOffIcon
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
            {onVoiceCall && (
              <button
                type="button"
                className="im-head-icon-btn"
                title="语音通话"
                aria-label="语音通话"
                onClick={onVoiceCall}
              >
                <CallIcon size="20px" />
              </button>
            )}
            {onVideoCall && (
              <button
                type="button"
                className="im-head-icon-btn"
                title="视频通话"
                aria-label="视频通话"
                onClick={onVideoCall}
              >
                <VideoCamera1Icon size="20px" />
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

      <div
        className="im-messages"
        ref={listRef}
        style={
          theme?.background && theme.background.kind !== 'default'
            ? undefined
            : chatBgStyle(theme?.background || user.chatBg)
        }
      >
        {texture && !(theme?.background && theme.background.kind !== 'default') && (
          <div className={`im-messages__texture im-messages__texture--${texture}`} aria-hidden />
        )}
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
          const voice = !m.recalled && m.type === 'voice' ? parseVoiceBody(m.body) : null
          const callInfo = !m.recalled && m.type === 'call' ? parseCallBody(m.body) : null
          const fwd = !m.recalled && m.type === 'forward' ? parseForwardBody(m.body) : null
          const press = m.recalled || selectMode || callInfo ? null : bindPressHandlers(m)
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
              {callInfo ? (
                <div className="im-msg-call">
                  {callInfo.kind === 'video' ? (
                    <VideoCamera1Icon size="14px" />
                  ) : (
                    <CallIcon size="14px" />
                  )}
                  <span>{formatCallMessage(callInfo)}</span>
                </div>
              ) : (
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
                  ) : voice ? (
                    <VoiceBubble
                      url={voice.url}
                      duration={voice.duration}
                      mine={mine}
                      press={press}
                      selectMode={!!selectMode}
                      ignoreClickUntil={ignoreClickUntil}
                    />
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
                                : it.type === 'voice'
                                  ? `[语音]${it.duration != null ? formatVoiceDuration(it.duration) : ''}`
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
              )}
            </div>
          )
        })}
      </div>

      {!selectMode && (
        <footer
          className="im-composer"
          onPaste={handlePaste}
        >
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
            <button
              type="button"
              className={
                voiceMode
                  ? 'im-composer__tool im-composer__tool--on'
                  : 'im-composer__tool'
              }
              title={voiceMode ? '切换到键盘' : '切换到语音'}
              aria-label={voiceMode ? '切换到键盘' : '切换到语音'}
              disabled={sendingMedia || !conversation}
              onClick={() => {
                if (recording) cancelVoiceRecord()
                setVoiceMode((v) => !v)
              }}
            >
              {voiceMode ? <KeyboardIcon size="22px" /> : <Microphone1Icon size="22px" />}
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

          {voiceMode ? (
            <div className="im-composer__voice">
              <button
                type="button"
                className={[
                  'im-composer__hold',
                  recording ? 'is-rec' : '',
                  recording && willCancel ? 'is-cancel' : '',
                ]
                  .filter(Boolean)
                  .join(' ')}
                disabled={sendingMedia || !conversation}
                onPointerDown={onHoldPointerDown}
                onPointerMove={onHoldPointerMove}
                onPointerUp={onHoldPointerUp}
                onPointerCancel={() => cancelVoiceRecord()}
                onLostPointerCapture={() => {
                  if (pressActive.current) onHoldPointerUp()
                }}
                onContextMenu={(e) => e.preventDefault()}
              >
                {!recording
                  ? '按住 说话'
                  : willCancel
                    ? '松开 取消'
                    : `松开发送 ${Math.min(60, Math.ceil(recSec))}″`}
              </button>
            </div>
          ) : (
            <>
              <Textarea
                className="im-composer__input"
                value={draft}
                onChange={(v) => onDraft(String(v))}
                placeholder="输入消息"
                autosize={{ minRows: 2, maxRows: 6 }}
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
            </>
          )}
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
                      ) : it.type === 'voice' && it.url ? (
                        <VoiceBubble
                          url={it.url}
                          duration={it.duration || 1}
                          mine={false}
                          selectMode={false}
                          ignoreClickUntil={{ current: 0 }}
                        />
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

function VoiceBubble({
  url,
  duration,
  mine,
  press,
  selectMode,
  ignoreClickUntil,
}: {
  url: string
  duration: number
  mine: boolean
  press?: Record<string, unknown> | null
  selectMode: boolean
  ignoreClickUntil: { current: number }
}) {
  const audioRef = useRef<HTMLAudioElement | null>(null)
  const [playing, setPlaying] = useState(false)
  const width = Math.min(220, Math.max(72, 56 + duration * 8))

  useEffect(() => {
    return () => {
      audioRef.current?.pause()
      audioRef.current = null
    }
  }, [])

  const toggle = () => {
    if (selectMode) return
    if (Date.now() < ignoreClickUntil.current) return
    let a = audioRef.current
    if (!a) {
      a = new Audio(url)
      audioRef.current = a
      a.onended = () => setPlaying(false)
      a.onpause = () => setPlaying(false)
      a.onplay = () => setPlaying(true)
    }
    if (a.paused) {
      void a.play().catch(() => MessagePlugin.error('无法播放语音'))
    } else {
      a.pause()
      a.currentTime = 0
      setPlaying(false)
    }
  }

  return (
    <button
      type="button"
      className={mine ? 'im-msg__voice im-msg__voice--mine' : 'im-msg__voice'}
      style={{ width }}
      {...(press || {})}
      onClick={(e) => {
        if (selectMode) return
        const p = press as { onClick?: (ev: unknown) => void } | null | undefined
        p?.onClick?.(e)
        toggle()
      }}
    >
      <span className="im-msg__voice-ico" aria-hidden>
        {playing ? '❚❚' : '▶'}
      </span>
      <span className="im-msg__voice-wave" aria-hidden />
      <span className="im-msg__voice-dur">{formatVoiceDuration(duration)}</span>
    </button>
  )
}
