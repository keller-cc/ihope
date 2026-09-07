import { useCallback, useEffect, useRef, useState } from 'react'
import { ChevronRightIcon } from 'tdesign-icons-react'
import { Button, Checkbox, Dialog, Input, MessagePlugin, Switch } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  getToken,
  setToken,
  type CallKind,
  type Contact,
  type Conversation,
  type FriendRequest,
  type GroupAnnouncement,
  type GroupJoinRequest,
  type Message,
  type QQStatus,
  type User,
} from '@/api'
import { Avatar } from '@/components/Avatar'
import { CallOverlay, CallSetupDialog, IncomingCallModal, type CallSetupResult } from '@/components/call'
import { ChatPane, ChatThemeDialog, ForwardDialog } from '@/components/chat'
import {
  AddContactDialog,
  ContactList,
  FriendProfile,
  FriendRequestsPane,
  GroupJoinRequestsPane,
  GroupProfile,
  MemberProfile,
  SessionList,
} from '@/components/contacts'
import {
  ChatHistoryPanel,
  defaultHistoryCache,
  type HistoryCache,
} from '@/components/history/ChatHistoryPanel'
import { PlusMenu } from '@/components/PlusMenu'
import { UserDrawer } from '@/components/UserDrawer'
import { useIsMobile } from '@/hooks/useIsMobile'
import { useVisualViewportLock } from '@/hooks/useVisualViewportLock'
import { callController } from '@/lib/call/CallController'
import { userSocket } from '@/lib/call/userSocket'
import { chatBgStyle, chatThemeSummary, chatThemeVars, resolveUserTheme, usesFrameWallpaper } from '@/lib/chatBg'
import { conversationTitle, initialOf } from '@/lib/chatFormat'

type Props = {
  user: User
  onUserChange?: (u: User) => void
  onLogout: () => void
}

type ListNav = 'messages' | 'contacts'
type ContactSection = 'friends' | 'groups'
/** Right pane surface — independent of listNav so switching tabs keeps chat. */
type RightSurface =
  | { kind: 'empty' }
  | { kind: 'chat' }
  | { kind: 'history' }
  | { kind: 'friendProfile'; profile: Contact }
  | { kind: 'groupProfile'; group: Conversation }
  | { kind: 'memberProfile'; member: Contact; group: Conversation; backTo?: 'group' | 'chat' }
  | { kind: 'friendRequests' }
  | { kind: 'groupJoinRequests' }
  | { kind: 'settings' }

export function ChatPage({ user, onUserChange, onLogout }: Props) {
  const isMobile = useIsMobile()
  useVisualViewportLock(isMobile)
  const [listNav, setListNav] = useState<ListNav>('messages')

  useEffect(() => {
    callController.setUserId(user.id)
    callController.start()
    return () => {
      void callController.stop()
    }
  }, [user.id])

  const [callUi, setCallUi] = useState(callController.state)
  useEffect(() => callController.subscribe(() => setCallUi({ ...callController.state })), [])

  const [contactSection, setContactSection] = useState<ContactSection>('friends')
  const [right, setRight] = useState<RightSurface>({ kind: 'empty' })
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [friends, setFriends] = useState<Contact[]>([])
  const [groups, setGroups] = useState<Conversation[]>([])
  const [incoming, setIncoming] = useState<FriendRequest[]>([])
  const [outgoing, setOutgoing] = useState<FriendRequest[]>([])
  const [groupJoins, setGroupJoins] = useState<GroupJoinRequest[]>([])
  const [reqBusyId, setReqBusyId] = useState<string | null>(null)
  const [activeId, setActiveId] = useState<string | null>(null)

  useEffect(() => {
    void callController.watchConversation(activeId)
  }, [activeId])

  const [messages, setMessages] = useState<Message[]>([])
  const [draft, setDraft] = useState('')
  const [filter, setFilter] = useState('')
  const [addOpen, setAddOpen] = useState(false)
  const [groupOpen, setGroupOpen] = useState(false)
  const [groupTitle, setGroupTitle] = useState('')
  const [selectedMemberIds, setSelectedMemberIds] = useState<string[]>([])
  const [groupMembers, setGroupMembersList] = useState<Contact[]>([])
  const [renameDraft, setRenameDraft] = useState('')
  const [qq, setQq] = useState<QQStatus | null>(null)
  const [bindCode, setBindCode] = useState('')
  const [bindHint, setBindHint] = useState('')
  const [bgOpen, setBgOpen] = useState(false)
  const [renameUserOpen, setRenameUserOpen] = useState(false)
  const [renameUserDraft, setRenameUserDraft] = useState('')
  const [sendingMedia, setSendingMedia] = useState(false)
  const [hasMoreMessages, setHasMoreMessages] = useState(false)
  const [loadingMore, setLoadingMore] = useState(false)
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [mobileDetail, setMobileDetail] = useState(false)
  const [historyCaches, setHistoryCaches] = useState<Record<string, HistoryCache>>({})
  const [returnToHistory, setReturnToHistory] = useState(false)
  const [focusMessageId, setFocusMessageId] = useState<string | null>(null)
  const [selectMode, setSelectMode] = useState(false)
  const [selectedMessageIds, setSelectedMessageIds] = useState<string[]>([])
  const [forwardOpen, setForwardOpen] = useState(false)
  const [forwardIds, setForwardIds] = useState<string[]>([])
  const [callSetup, setCallSetup] = useState<{ kind: CallKind; conversationId: string } | null>(
    null,
  )
  const [callSetupBusy, setCallSetupBusy] = useState(false)
  const listRef = useRef<HTMLDivElement>(null)
  const wsRef = useRef<WebSocket | null>(null)

  const loadConversations = useCallback(async () => {
    try {
      const res = await api.listConversations()
      setConversations(res.conversations)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '加载会话失败'))
    }
  }, [])

  const loadContacts = useCallback(async () => {
    try {
      const [f, g, req, joins] = await Promise.all([
        api.listFriends(),
        api.listGroups(),
        api.listFriendRequests(),
        api.listManagedGroupJoinRequests().catch(() => ({ requests: [] as GroupJoinRequest[] })),
      ])
      setFriends(f.friends)
      setGroups(g.groups)
      setIncoming(req.incoming || [])
      setOutgoing(req.outgoing || [])
      setGroupJoins(joins.requests || [])
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '加载联系人失败'))
    }
  }, [])

  const loadMessages = useCallback(async (id: string) => {
    try {
      const res = await api.listMessages(id)
      setMessages(res.messages)
      setHasMoreMessages(!!res.hasMore)
      // listMessages 服务端已 MarkRead；本地清未读即可，避免再打 /conversations
      setConversations((prev) =>
        prev.map((c) => (c.id === id && c.unreadCount ? { ...c, unreadCount: 0 } : c)),
      )
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '加载消息失败'))
    }
  }, [])

  useEffect(() => {
    return callController.onCallEnded((conversationId) => {
      void loadConversations()
      if (activeId === conversationId && right.kind === 'chat') {
        // 会话 WS 可能未挂上；结束后主动拉一次，避免超时摘要要刷新才出现
        window.setTimeout(() => {
          void loadMessages(conversationId)
        }, 200)
      }
    })
  }, [activeId, right.kind, loadConversations, loadMessages])

  useEffect(() => {
    userSocket.connect()
    return userSocket.on((data) => {
      const t = String(data.type || '')
      if (t === 'friend.request') {
        MessagePlugin.info('收到一条好友申请')
        void loadContacts()
        return
      }
      if (t === 'group.join_request') {
        const cid = String(data.conversationId || '')
        const conv =
          conversations.find((c) => c.id === cid) || groups.find((c) => c.id === cid)
        // 仅群主/管理员应收到；若本地能判定且无权限则忽略
        if (conv && !(conv.isOwner || conv.isAdmin)) return
        const req = data.request as { group?: { title?: string } } | undefined
        const title = req?.group?.title || conv?.title || '群聊'
        MessagePlugin.info(`「${title}」有新的入群申请`)
        void loadContacts()
        return
      }
      if (t === 'group.announcement') {
        const cid = String(data.conversationId || '')
        const ann = data.announcement as GroupAnnouncement | undefined
        if (cid && ann?.id) {
          const patch = (c: Conversation): Conversation =>
            c.id === cid
              ? {
                  ...c,
                  announcement: ann.body,
                  announcementCount: (c.announcementCount || 0) + 1,
                  pendingAnnouncement:
                    ann.authorId === user.id ? c.pendingAnnouncement ?? null : ann,
                }
              : c
          setConversations((prev) => prev.map(patch))
          setGroups((prev) => prev.map(patch))
          if (ann.authorId !== user.id) {
            MessagePlugin.info('有新的群公告')
          }
        }
        return
      }
      if (t === 'group.kicked') {
        const cid = String(data.conversationId || '')
        const tip = String(data.body || '你已被移出群聊')
        MessagePlugin.warning(tip)
        void loadConversations()
        void loadContacts()
        if (cid && activeId === cid) {
          const msg = data.message as Message | undefined
          if (msg?.id) {
            setMessages((prev) => (prev.some((m) => m.id === msg.id) ? prev : [...prev, msg]))
          }
          setConversations((prev) =>
            prev.map((c) =>
              c.id === cid ? { ...c, removed: true, removeReason: 'kicked' } : c,
            ),
          )
        }
      }
    })
  }, [activeId, conversations, groups, loadContacts, loadConversations])

  const loadOlderMessages = async () => {
    if (!activeId || !messages.length || loadingMore) return
    setLoadingMore(true)
    const el = listRef.current
    const prevHeight = el?.scrollHeight || 0
    try {
      const oldest = messages[0]
      const res = await api.listMessages(activeId, { before: oldest.createdAt })
      setMessages((prev) => {
        const ids = new Set(prev.map((m) => m.id))
        const merged = [...res.messages.filter((m) => !ids.has(m.id)), ...prev]
        return merged
      })
      setHasMoreMessages(!!res.hasMore)
      requestAnimationFrame(() => {
        if (el) el.scrollTop = el.scrollHeight - prevHeight
      })
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '加载失败'))
    } finally {
      setLoadingMore(false)
    }
  }

  const loadQQ = useCallback(async () => {
    try {
      setQq(await api.qqStatus())
    } catch {
      setQq({ botEnabled: false, bound: false })
    }
  }, [])

  useEffect(() => {
    void loadConversations()
    void loadContacts()
  }, [loadConversations, loadContacts])

  useEffect(() => {
    if (right.kind === 'settings') void loadQQ()
  }, [right.kind, loadQQ])

  // 主题 CSS 变量同步到 :root，使 Drawer / Dialog 等 portal 也吃到随心调
  useEffect(() => {
    const theme = resolveUserTheme(user)
    const frameWallpaper = usesFrameWallpaper(theme)
    const vars = chatThemeVars(theme, { frameWallpaper }) as Record<string, string>
    const root = document.documentElement
    const keys: string[] = []
    for (const [k, v] of Object.entries(vars)) {
      if (typeof v !== 'string') continue
      root.style.setProperty(k, v)
      keys.push(k)
    }
    return () => {
      for (const k of keys) root.style.removeProperty(k)
    }
  }, [user.chatTheme, user.chatBg])

  useEffect(() => {
    if (!activeId || right.kind !== 'chat') return
    void loadMessages(activeId)
    wsRef.current?.close()
    const token = getToken()
    if (!token) return
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(
      `${proto}://${location.host}/ws?token=${encodeURIComponent(token)}&conversationId=${encodeURIComponent(activeId)}`,
    )
    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data as string) as {
          type?: string
          message?: Message
        }
        if (data.type === 'message' && data.message) {
          const msg = data.message
          setMessages((prev) => {
            if (prev.some((m) => m.id === msg.id)) return prev
            return [...prev, msg]
          })
          // 正在看该会话：标已读，避免通话摘要等把未读刷出来
          void api.markRead(activeId).then(() => {
            setConversations((prev) =>
              prev.map((c) =>
                c.id === activeId
                  ? {
                      ...c,
                      unreadCount: 0,
                      lastMessage:
                        msg.type === 'call'
                          ? '[通话]'
                          : msg.type === 'image'
                            ? '[图片]'
                            : msg.type === 'voice'
                              ? '[语音]'
                              : msg.type === 'file'
                                ? '[文件]'
                                : msg.recalled
                                  ? '[消息已撤回]'
                                  : msg.body || c.lastMessage,
                      lastMessageAt: msg.createdAt || c.lastMessageAt,
                    }
                  : c,
              ),
            )
          }).catch(() => {
            void loadConversations()
          })
        }
        if (data.type === 'message_recalled' && data.message) {
          setMessages((prev) =>
            prev.map((m) => (m.id === data.message!.id ? { ...m, ...data.message! } : m)),
          )
          void loadConversations()
        }
      } catch {
        /* ignore */
      }
    }
    wsRef.current = ws
    return () => ws.close()
  }, [activeId, right.kind, loadMessages])

  useEffect(() => {
    if (focusMessageId) return
    const el = listRef.current
    if (el) el.scrollTop = el.scrollHeight
  }, [messages, focusMessageId])

  const active =
    conversations.find((c) => c.id === activeId) || groups.find((c) => c.id === activeId)

  const openChat = (id: string, seed?: Conversation) => {
    if (seed) {
      setConversations((prev) => {
        if (prev.some((c) => c.id === id)) {
          return prev.map((c) => (c.id === id ? { ...c, ...seed, unreadCount: 0 } : c))
        }
        return [{ ...seed, unreadCount: 0 }, ...prev]
      })
      if (seed.type === 'group') {
        setGroups((prev) => {
          if (prev.some((c) => c.id === id)) {
            return prev.map((c) => (c.id === id ? { ...c, ...seed } : c))
          }
          return [seed, ...prev]
        })
      }
    }
    setListNav('messages')
    setActiveId(id)
    setRight({ kind: 'chat' })
    setMobileDetail(true)
    setSelectMode(false)
    setSelectedMessageIds([])
    setReturnToHistory(false)
    setFocusMessageId(null)
    // 取消隐藏；不在这里拉消息/会话（由 chat effect 加载消息）
    void api.patchConversationMember(id, { hidden: false }).catch(() => undefined)
  }

  const openHistory = (conversationId?: string) => {
    const id = conversationId || activeId
    if (!id) return
    if (id !== activeId) {
      setActiveId(id)
      void loadMessages(id)
    }
    const conv =
      conversations.find((c) => c.id === id) || groups.find((c) => c.id === id)
    if (conv?.type === 'group') {
      void api
        .listGroupMembers(id)
        .then((r) => setGroupMembersList(r.members))
        .catch(() => undefined)
    }
    setHistoryCaches((prev) => ({
      ...prev,
      [id]: prev[id] || defaultHistoryCache(),
    }))
    setRight({ kind: 'history' })
    setMobileDetail(true)
    setReturnToHistory(false)
  }

  const jumpToMessage = async (messageId: string) => {
    if (!activeId) return
    setRight({ kind: 'chat' })
    setReturnToHistory(true)
    setFocusMessageId(messageId)
    try {
      if (!messages.some((m) => m.id === messageId)) {
        const res = await api.messageContext(activeId, messageId)
        setMessages(res.messages)
        setHasMoreMessages(true)
      }
      // re-trigger scroll after paint
      requestAnimationFrame(() => setFocusMessageId(messageId))
      window.setTimeout(() => setFocusMessageId((cur) => (cur === messageId ? null : cur)), 2500)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '定位失败'))
    }
  }

  const send = async () => {
    if (!activeId || !draft.trim()) return
    const body = draft.trim()
    setDraft('')
    try {
      const m = await api.sendMessage(activeId, body)
      setMessages((prev) => (prev.some((x) => x.id === m.id) ? prev : [...prev, m]))
      void loadConversations()
    } catch (e) {
      setDraft(body)
      MessagePlugin.error(apiErrorMessage(e, '发送失败'))
    }
  }

  const sendImage = async (file: File) => {
    if (!activeId) return
    if (file.size > 10 * 1024 * 1024) {
      MessagePlugin.warning('图片过大（最大 10MB）')
      return
    }
    setSendingMedia(true)
    try {
      const m = await api.sendImage(activeId, file)
      setMessages((prev) => (prev.some((x) => x.id === m.id) ? prev : [...prev, m]))
      void loadConversations()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '发送图片失败'))
    } finally {
      setSendingMedia(false)
    }
  }

  const sendFile = async (file: File) => {
    if (!activeId) return
    if (file.size > 20 * 1024 * 1024) {
      MessagePlugin.warning('文件过大（最大 20MB）')
      return
    }
    setSendingMedia(true)
    try {
      const m = await api.sendFile(activeId, file)
      setMessages((prev) => (prev.some((x) => x.id === m.id) ? prev : [...prev, m]))
      void loadConversations()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '发送文件失败'))
    } finally {
      setSendingMedia(false)
    }
  }

  const sendVoice = async (blob: Blob, duration: number, mime: string) => {
    if (!activeId) return
    if (blob.size > 5 * 1024 * 1024) {
      MessagePlugin.warning('语音过大')
      return
    }
    setSendingMedia(true)
    try {
      const m = await api.sendVoice(activeId, blob, duration, mime)
      setMessages((prev) => (prev.some((x) => x.id === m.id) ? prev : [...prev, m]))
      void loadConversations()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '发送语音失败'))
    } finally {
      setSendingMedia(false)
    }
  }

  const recall = async (messageId: string) => {
    if (!activeId) return
    try {
      const m = await api.recallMessage(activeId, messageId)
      setMessages((prev) => prev.map((x) => (x.id === m.id ? m : x)))
      void loadConversations()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '撤回失败'))
    }
  }

  const startDM = async (username: string) => {
    try {
      const existing = conversations.find(
        (c) => c.type === 'dm' && c.peerUsername === username,
      )
      if (existing) {
        openChat(existing.id, existing)
        return
      }
      const c = await api.createDM(username)
      openChat(c.id, c)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '打开会话失败'))
    }
  }

  const openGroupProfile = async (g: Conversation) => {
    try {
      const membersRes = await api.listGroupMembers(g.id)
      const latest =
        conversations.find((x) => x.id === g.id) ||
        groups.find((x) => x.id === g.id) ||
        g
      setRenameDraft(latest.title)
      setGroupMembersList(membersRes.members)
      setRight({
        kind: 'groupProfile',
        group: { ...latest, memberCount: membersRes.members.length },
      })
      setMobileDetail(true)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '加载群资料失败'))
    }
  }

  const openGroupMember = async (g: Conversation, memberId: string) => {
    try {
      const membersRes = await api.listGroupMembers(g.id)
      setGroupMembersList(membersRes.members)
      const member = membersRes.members.find((m) => m.id === memberId)
      if (!member) {
        MessagePlugin.warning('该成员不在本群')
        return
      }
      const latest =
        conversations.find((x) => x.id === g.id) ||
        groups.find((x) => x.id === g.id) ||
        g
      setRight({
        kind: 'memberProfile',
        member,
        group: { ...latest, memberCount: membersRes.members.length },
        backTo: 'chat',
      })
      setMobileDetail(true)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '加载成员资料失败'))
    }
  }

  const refreshMemberProfile = async (groupId: string, memberId: string) => {
    const membersRes = await api.listGroupMembers(groupId)
    setGroupMembersList(membersRes.members)
    const member = membersRes.members.find((m) => m.id === memberId)
    const g =
      groups.find((x) => x.id === groupId) ||
      conversations.find((x) => x.id === groupId)
    return { members: membersRes.members, member, group: g }
  }

  const totalUnread = conversations.reduce(
    (n, c) => n + (c.muted ? 0 : c.unreadCount || 0),
    0,
  )

  const showingList = isMobile && !mobileDetail && right.kind !== 'settings'
  const frameClass = [
    'im-frame',
    isMobile ? 'im-frame--mobile' : '',
    right.kind === 'settings' ? 'im-frame--settings' : '',
    showingList ? 'im-frame--list' : 'im-frame--chat',
  ]
    .filter(Boolean)
    .join(' ')

  const goMessages = () => {
    setListNav('messages')
    if (isMobile) {
      setMobileDetail(false)
    } else if (activeId) {
      setRight({ kind: 'chat' })
    } else {
      setRight({ kind: 'empty' })
    }
  }

  const goContacts = () => {
    setListNav('contacts')
    if (isMobile) {
      setMobileDetail(false)
    } else if (right.kind === 'settings') {
      setRight({ kind: 'empty' })
    }
  }

  const navActive = (id: ListNav) => right.kind !== 'settings' && listNav === id

  const navBtn = (id: ListNav, label: string, ico: string, badge?: number) => (
    <button
      type="button"
      className={navActive(id) ? 'im-nav-btn is-active' : 'im-nav-btn'}
      aria-current={navActive(id) ? 'page' : undefined}
      onClick={() => (id === 'messages' ? goMessages() : goContacts())}
    >
      <span className={`im-ico im-ico--${ico}`} />
      <em>{label}</em>
      {!!badge && badge > 0 && (
        <span className="im-nav-btn__badge">{badge > 99 ? '99+' : badge}</span>
      )}
    </button>
  )

  const friendNamesById = Object.fromEntries(friends.map((f) => [f.id, f.username]))
  const theme = resolveUserTheme(user)
  const hasWallpaper = !!(theme?.background && theme.background.kind !== 'default')
  const frameWallpaper = usesFrameWallpaper(theme)
  const themed = !!(
    theme?.accent ||
    hasWallpaper ||
    theme?.bubbleMine ||
    theme?.bubblePeer ||
    theme?.texture ||
    (theme?.opacity != null && theme.opacity < 1) ||
    theme?.blur != null
  )

  return (
    <div
      className={[
        isMobile ? 'im-shell im-shell--mobile' : 'im-shell',
        themed ? 'im-shell--themed' : '',
        frameWallpaper ? 'im-shell--wallpaper' : '',
      ]
        .filter(Boolean)
        .join(' ')}
      style={chatThemeVars(theme, { frameWallpaper })}
    >
      <div className={frameClass}>
        {frameWallpaper && theme?.background && (
          <div
            className={[
              'im-frame__wallpaper',
              !isMobile ? 'im-frame__wallpaper--skip-rail' : '',
            ]
              .filter(Boolean)
              .join(' ')}
            style={chatBgStyle(theme.background)}
            aria-hidden
          >
            {theme.texture && theme.texture !== 'none' ? (
              <div
                className={`im-messages__texture im-messages__texture--${theme.texture}`}
              />
            ) : null}
          </div>
        )}
        {!isMobile && (
          <aside className="im-rail" aria-label="主导航">
            <button
              type="button"
              className="im-avatar im-avatar--rail"
              title={user.username}
              onClick={() => setDrawerOpen(true)}
            >
              {user.avatarUrl ? (
                <img src={user.avatarUrl} alt="" />
              ) : (
                initialOf(user.username)
              )}
            </button>
            {navBtn('messages', '消息', 'msg', totalUnread)}
            {navBtn('contacts', '联系人', 'contacts', incoming.length + groupJoins.length)}
            <button
              type="button"
              className={right.kind === 'settings' ? 'im-nav-btn is-active' : 'im-nav-btn'}
              aria-current={right.kind === 'settings' ? 'page' : undefined}
              onClick={() => {
                setRight({ kind: 'settings' })
                setMobileDetail(true)
              }}
            >
              <span className="im-ico im-ico--set" />
              <em>设置</em>
            </button>
            <button
              type="button"
              className="im-nav-btn"
              onClick={() => {
                setToken(null)
                onLogout()
              }}
            >
              <span className="im-ico im-ico--out" />
              <em>退出</em>
            </button>
          </aside>
        )}

        {right.kind !== 'settings' && (
          <section className="im-sidebar">
            <header className="im-sidebar__head">
              {isMobile && (
                <button
                  type="button"
                  className="im-avatar im-avatar--rail im-mobile-only"
                  title="我"
                  onClick={() => setDrawerOpen(true)}
                >
                  {user.avatarUrl ? (
                    <img src={user.avatarUrl} alt="" />
                  ) : (
                    initialOf(user.username)
                  )}
                </button>
              )}
              <Input
                className="im-sidebar__search"
                borderless
                placeholder={listNav === 'messages' ? '搜索会话' : '搜索联系人 / 群'}
                value={filter}
                clearable
                onChange={(v) => setFilter(String(v))}
              />
              <PlusMenu
                onAction={(a) => {
                  if (a === 'addContact') {
                    void loadContacts()
                    setAddOpen(true)
                  } else {
                    void loadContacts()
                    setSelectedMemberIds([])
                    setGroupTitle('')
                    setGroupOpen(true)
                  }
                }}
              />
            </header>

            {listNav === 'messages' && (
              <SessionList
                sessions={conversations}
                activeId={activeId}
                filter={filter}
                onOpen={(id) => {
                  // PC：再次点击当前会话 → 取消挂载右侧聊天
                  if (
                    !isMobile &&
                    activeId === id &&
                    (right.kind === 'chat' || right.kind === 'history')
                  ) {
                    setActiveId(null)
                    setRight({ kind: 'empty' })
                    setMessages([])
                    setSelectMode(false)
                    setSelectedMessageIds([])
                    setFocusMessageId(null)
                    setReturnToHistory(false)
                    return
                  }
                  setActiveId(id)
                  setRight({ kind: 'chat' })
                  setMobileDetail(true)
                }}
                onTogglePin={async (c) => {
                  try {
                    await api.patchConversationMember(c.id, { pinned: !c.pinned })
                    await loadConversations()
                  } catch (e) {
                    MessagePlugin.error(apiErrorMessage(e, '操作失败'))
                  }
                }}
                onToggleMute={async (c) => {
                  try {
                    await api.patchConversationMember(c.id, { muted: !c.muted })
                    await loadConversations()
                  } catch (e) {
                    MessagePlugin.error(apiErrorMessage(e, '操作失败'))
                  }
                }}
                onHide={async (c) => {
                  try {
                    await api.patchConversationMember(c.id, { hidden: true })
                    if (activeId === c.id) {
                      setActiveId(null)
                      setRight({ kind: 'empty' })
                      setMobileDetail(false)
                    }
                    await loadConversations()
                  } catch (e) {
                    MessagePlugin.error(apiErrorMessage(e, '操作失败'))
                  }
                }}
              />
            )}

            {listNav === 'contacts' && (
              <ContactList
                section={contactSection}
                onSection={setContactSection}
                friends={friends}
                groups={groups}
                friendRequestCount={incoming.length}
                groupJoinCount={groupJoins.length}
                filter={filter}
                selectedFriendId={
                  right.kind === 'friendProfile' ? right.profile.id : null
                }
                selectedGroupId={
                  right.kind === 'groupProfile' ? right.group.id : null
                }
                requestsOpen={right.kind === 'friendRequests'}
                groupJoinsOpen={right.kind === 'groupJoinRequests'}
                onSelectFriend={(f) => {
                  setRight({ kind: 'friendProfile', profile: f })
                  setMobileDetail(true)
                  setContactSection('friends')
                }}
                onSelectGroup={(g) => void openGroupProfile(g)}
                onOpenFriendRequests={() => {
                  setContactSection('friends')
                  setRight({ kind: 'friendRequests' })
                  setMobileDetail(true)
                  void loadContacts()
                }}
                onOpenGroupJoins={() => {
                  setContactSection('groups')
                  setRight({ kind: 'groupJoinRequests' })
                  setMobileDetail(true)
                  void loadContacts()
                }}
              />
            )}
          </section>
        )}

        {right.kind === 'settings' && (
          <section className="im-settings">
            <header className="im-chat-head">
              {isMobile && (
                <button
                  type="button"
                  className="im-back"
                  onClick={() => {
                    setRight(activeId ? { kind: 'chat' } : { kind: 'empty' })
                    setMobileDetail(false)
                    setListNav('messages')
                  }}
                >
                  ‹
                </button>
              )}
              <h2 className="im-chat-head__title">设置</h2>
            </header>
            <div className="im-settings-scroll">
              <div className="im-set-hero">
                <button
                  type="button"
                  className="im-set-hero__avatar"
                  onClick={() => {
                    const input = document.createElement('input')
                    input.type = 'file'
                    input.accept = 'image/*'
                    input.onchange = async () => {
                      const file = input.files?.[0]
                      if (!file) return
                      try {
                        const u = await api.uploadAvatar(file)
                        onUserChange?.(u)
                        MessagePlugin.success('头像已更新')
                      } catch (e) {
                        MessagePlugin.error(apiErrorMessage(e, '上传失败'))
                      }
                    }
                    input.click()
                  }}
                  title="更换头像"
                >
                  <Avatar name={user.username} src={user.avatarUrl} size="xl" />
                </button>
                <div className="im-set-hero__meta">
                  <strong>{user.username}</strong>
                  <span>{user.email}</span>
                  <span>{user.hopeId ? `IHope 号：${user.hopeId}` : '正在分配 IHope 号…'}</span>
                </div>
              </div>

              <div className="im-set-group">
                <button
                  type="button"
                  className="im-set-cell"
                  onClick={() => {
                    setRenameUserDraft(user.username)
                    setRenameUserOpen(true)
                  }}
                >
                  <span className="im-set-cell__label">修改昵称</span>
                  <span className="im-set-cell__value">{user.username}</span>
                  <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
                </button>
                <button
                  type="button"
                  className="im-set-cell"
                  onClick={() => {
                    const input = document.createElement('input')
                    input.type = 'file'
                    input.accept = 'image/*'
                    input.onchange = async () => {
                      const file = input.files?.[0]
                      if (!file) return
                      try {
                        const u = await api.uploadAvatar(file)
                        onUserChange?.(u)
                        MessagePlugin.success('头像已更新')
                      } catch (e) {
                        MessagePlugin.error(apiErrorMessage(e, '上传失败'))
                      }
                    }
                    input.click()
                  }}
                >
                  <span className="im-set-cell__label">更换头像</span>
                  <Avatar name={user.username} src={user.avatarUrl} size="sm" />
                  <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
                </button>
                <div className="im-set-cell im-set-cell--static">
                  <span className="im-set-cell__label">IHope 号</span>
                  <span className="im-set-cell__value" style={{ letterSpacing: '0.04em' }}>
                    {user.hopeId || '—'}
                  </span>
                </div>
                <button
                  type="button"
                  className="im-set-cell"
                  onClick={() => setBgOpen(true)}
                >
                  <span className="im-set-cell__label">随心调</span>
                  <span className="im-set-cell__value">
                    {chatThemeSummary(resolveUserTheme(user))}
                  </span>
                  <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
                </button>
              </div>

              <div className="im-set-group">
                <div className="im-set-section-title">QQ 消息提醒</div>
                {!qq?.botEnabled ? (
                  <div className="im-set-cell im-set-cell--static">
                    <span className="im-set-cell__value" style={{ maxWidth: '100%', textAlign: 'left' }}>
                      服务器未启用 QQ 机器人
                    </span>
                  </div>
                ) : !qq.bound ? (
                  <div style={{ padding: '12px 14px' }}>
                    <Button
                      theme="primary"
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
                      <div className="im-bind-box" style={{ marginTop: 12 }}>
                        <p>{bindHint}</p>
                        <strong className="im-bind-code">{bindCode}</strong>
                      </div>
                    )}
                  </div>
                ) : (
                  <>
                    <div className="im-set-cell im-set-cell--switch">
                      <span className="im-set-cell__label">离线消息提醒</span>
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
                    <button
                      type="button"
                      className="im-set-cell im-set-cell--danger"
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
                      <span className="im-set-cell__label">解除绑定</span>
                    </button>
                  </>
                )}
              </div>
            </div>
          </section>
        )}

        {right.kind === 'groupProfile' && (
          <GroupProfile
            group={right.group}
            members={groupMembers}
            friends={friends}
            renameDraft={renameDraft}
            onRenameDraft={setRenameDraft}
            onSaveRename={async () => {
              try {
                const g = await api.renameGroup(right.group.id, renameDraft.trim())
                setRight({
                  kind: 'groupProfile',
                  group: { ...right.group, ...g, title: g.title },
                })
                MessagePlugin.success('群名称已更新')
                await loadContacts()
                await loadConversations()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '修改失败'))
                throw e
              }
            }}
            onAvatarUpdated={(g) => {
              setRight({ kind: 'groupProfile', group: g })
              void loadContacts()
              void loadConversations()
            }}
            onGroupUpdated={(g) => {
              setRight({ kind: 'groupProfile', group: { ...right.group, ...g } })
              const apply = (c: Conversation) =>
                c.id === g.id ? { ...c, ...g } : c
              setConversations((prev) => prev.map(apply))
              setGroups((prev) => prev.map(apply))
            }}
            onMembersChanged={async () => {
              try {
                const membersRes = await api.listGroupMembers(right.group.id)
                setGroupMembersList(membersRes.members)
                const g =
                  groups.find((x) => x.id === right.group.id) ||
                  conversations.find((x) => x.id === right.group.id) ||
                  right.group
                setRight({
                  kind: 'groupProfile',
                  group: { ...g, memberCount: membersRes.members.length },
                })
                await loadContacts()
                await loadConversations()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '刷新成员失败'))
              }
            }}
            onSelectMember={(m) => {
              setRight({
                kind: 'memberProfile',
                member: m,
                group: right.group,
                backTo: 'group',
              })
              setMobileDetail(true)
            }}
            onTogglePin={async () => {
              try {
                await api.patchConversationMember(right.group.id, {
                  pinned: !right.group.pinned,
                })
                setRight({
                  kind: 'groupProfile',
                  group: { ...right.group, pinned: !right.group.pinned },
                })
                await loadConversations()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '操作失败'))
              }
            }}
            onToggleMute={async () => {
              try {
                await api.patchConversationMember(right.group.id, {
                  muted: !right.group.muted,
                })
                setRight({
                  kind: 'groupProfile',
                  group: { ...right.group, muted: !right.group.muted },
                })
                await loadConversations()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '操作失败'))
              }
            }}
            onFindHistory={() => {
              void (async () => {
                try {
                  const membersRes = await api.listGroupMembers(right.group.id)
                  setGroupMembersList(membersRes.members)
                } catch {
                  /* ignore */
                }
                openHistory(right.group.id)
              })()
            }}
            onEnterChat={() => openChat(right.group.id, right.group)}
            onLeave={async () => {
              const gid = right.group.id
              try {
                await api.leaveGroup(gid)
                MessagePlugin.success('已退出群聊')
                await loadContacts()
                await loadConversations()
                setActiveId(gid)
                setRight({ kind: 'chat' })
                setMobileDetail(true)
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '退出失败'))
              }
            }}
            onDissolved={async () => {
              if (activeId === right.group.id) setActiveId(null)
              setRight({ kind: 'empty' })
              setMobileDetail(false)
              await loadContacts()
              await loadConversations()
            }}
            onBack={() => {
              setRight(activeId ? { kind: 'chat' } : { kind: 'empty' })
              setMobileDetail(false)
            }}
            showBack={isMobile || !!activeId}
          />
        )}

        {right.kind === 'memberProfile' && (
          <MemberProfile
            member={right.member}
            group={right.group}
            selfId={user.id}
            showBack
            onBack={() => {
              if (right.backTo === 'chat') {
                setRight({ kind: 'chat' })
                return
              }
              setRight({ kind: 'groupProfile', group: right.group })
            }}
            onMessage={() => void startDM(right.member.username)}
            onFriendAdded={() => {
              void loadContacts()
            }}
            onMembersChanged={async () => {
              try {
                const refreshed = await refreshMemberProfile(right.group.id, right.member.id)
                if (!refreshed.member) {
                  if (right.backTo === 'chat') {
                    setRight({ kind: 'chat' })
                  } else {
                    setRight({
                      kind: 'groupProfile',
                      group: {
                        ...right.group,
                        ...(refreshed.group || {}),
                        memberCount: refreshed.members.length,
                      },
                    })
                  }
                } else {
                  setRight({
                    kind: 'memberProfile',
                    member: refreshed.member,
                    group: {
                      ...right.group,
                      ...(refreshed.group || {}),
                      memberCount: refreshed.members.length,
                    },
                    backTo: right.backTo,
                  })
                }
                await loadContacts()
                await loadConversations()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '刷新成员失败'))
              }
            }}
          />
        )}

        {right.kind === 'friendProfile' && (
          <FriendProfile
            profile={right.profile}
            conversation={conversations.find(
              (c) => c.type === 'dm' && c.peerUsername === right.profile.username,
            )}
            onBack={() => {
              setRight(activeId ? { kind: 'chat' } : { kind: 'empty' })
              setMobileDetail(false)
            }}
            onMessage={() => {
              const conv = conversations.find(
                (c) => c.type === 'dm' && c.peerUsername === right.profile.username,
              )
              if (conv) openChat(conv.id, conv)
              else void startDM(right.profile.username)
            }}
            onSaveRemark={async (remark) => {
              if (!right.profile.id) {
                MessagePlugin.warning('请先添加好友后再设置备注')
                return
              }
              try {
                const c = await api.setFriendRemark(right.profile.id, remark)
                setRight({ kind: 'friendProfile', profile: c })
                MessagePlugin.success('备注已保存')
                await loadContacts()
                await loadConversations()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '保存失败'))
              }
            }}
            onDeleteFriend={async () => {
              if (!right.profile.id) return
              const peer = right.profile.username
              try {
                await api.removeFriend(right.profile.id)
                MessagePlugin.success('已删除好友')
                await loadContacts()
                const res = await api.listConversations()
                setConversations(res.conversations)
                const dm = res.conversations.find(
                  (c) => c.type === 'dm' && c.peerUsername === peer,
                )
                if (dm) {
                  setActiveId(dm.id)
                  setRight({ kind: 'chat' })
                  setMobileDetail(true)
                } else {
                  setRight({ kind: 'empty' })
                  setMobileDetail(false)
                }
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '删除失败'))
                throw e
              }
            }}
            onTogglePin={
              conversations.some(
                (c) => c.type === 'dm' && c.peerUsername === right.profile.username,
              )
                ? async () => {
                    const conv = conversations.find(
                      (c) => c.type === 'dm' && c.peerUsername === right.profile.username,
                    )
                    if (!conv) return
                    try {
                      await api.patchConversationMember(conv.id, { pinned: !conv.pinned })
                      await loadConversations()
                    } catch (e) {
                      MessagePlugin.error(apiErrorMessage(e, '操作失败'))
                    }
                  }
                : undefined
            }
            onToggleMute={
              conversations.some(
                (c) => c.type === 'dm' && c.peerUsername === right.profile.username,
              )
                ? async () => {
                    const conv = conversations.find(
                      (c) => c.type === 'dm' && c.peerUsername === right.profile.username,
                    )
                    if (!conv) return
                    try {
                      await api.patchConversationMember(conv.id, { muted: !conv.muted })
                      await loadConversations()
                    } catch (e) {
                      MessagePlugin.error(apiErrorMessage(e, '操作失败'))
                    }
                  }
                : undefined
            }
            onFindHistory={
              conversations.some(
                (c) => c.type === 'dm' && c.peerUsername === right.profile.username,
              )
                ? () => {
                    const conv = conversations.find(
                      (c) => c.type === 'dm' && c.peerUsername === right.profile.username,
                    )
                    if (conv) openHistory(conv.id)
                  }
                : undefined
            }
            showBack={isMobile || !!activeId}
          />
        )}

        {right.kind === 'empty' && !isMobile && listNav === 'messages' && (
          <section className="im-pane">
            <div className="im-empty">
              <div className="im-logo-mark">IHope</div>
              <p>选择左侧会话开始聊天</p>
            </div>
          </section>
        )}

        {right.kind === 'empty' && !isMobile && listNav === 'contacts' && (
          <section className="im-pane">
            <div className="im-empty">
              <div className="im-logo-mark">IHope</div>
              <p>选择好友查看资料，或打开群资料</p>
            </div>
          </section>
        )}

        {right.kind === 'friendRequests' && (
          <FriendRequestsPane
            incoming={incoming}
            outgoing={outgoing}
            busyId={reqBusyId}
            onBack={
              isMobile
                ? () => {
                    setRight({ kind: 'empty' })
                    setMobileDetail(false)
                  }
                : undefined
            }
            onAccept={async (id) => {
              const req = incoming.find((r) => r.id === id)
              setReqBusyId(id)
              try {
                const friend = await api.acceptFriendRequest(id)
                MessagePlugin.success('已添加好友')
                await loadContacts()
                const name = friend.username || req?.fromUser?.username
                if (name) await startDM(name)
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '操作失败'))
              } finally {
                setReqBusyId(null)
              }
            }}
            onReject={async (id) => {
              setReqBusyId(id)
              try {
                await api.rejectFriendRequest(id)
                MessagePlugin.success('已拒绝')
                await loadContacts()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '操作失败'))
              } finally {
                setReqBusyId(null)
              }
            }}
            onCancel={async (id) => {
              setReqBusyId(id)
              try {
                await api.cancelFriendRequest(id)
                MessagePlugin.success('已撤回申请')
                await loadContacts()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '操作失败'))
              } finally {
                setReqBusyId(null)
              }
            }}
          />
        )}

        {right.kind === 'groupJoinRequests' && (
          <GroupJoinRequestsPane
            requests={groupJoins}
            busyId={reqBusyId}
            onBack={
              isMobile
                ? () => {
                    setRight({ kind: 'empty' })
                    setMobileDetail(false)
                  }
                : undefined
            }
            onOpenGroup={(conversationId) => {
              const g =
                groups.find((x) => x.id === conversationId) ||
                conversations.find((x) => x.id === conversationId)
              if (g) void openGroupProfile(g)
            }}
            onAccept={async (conversationId, requestId) => {
              setReqBusyId(requestId)
              try {
                await api.acceptGroupJoinRequest(conversationId, requestId)
                MessagePlugin.success('已同意入群')
                await loadContacts()
                await loadConversations()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '操作失败'))
              } finally {
                setReqBusyId(null)
              }
            }}
            onReject={async (conversationId, requestId) => {
              setReqBusyId(requestId)
              try {
                await api.rejectGroupJoinRequest(conversationId, requestId)
                MessagePlugin.success('已拒绝')
                await loadContacts()
              } catch (e) {
                MessagePlugin.error(apiErrorMessage(e, '操作失败'))
              } finally {
                setReqBusyId(null)
              }
            }}
          />
        )}

        {right.kind === 'history' && activeId && active && (
          <ChatHistoryPanel
            conversation={active}
            members={groupMembers}
            cache={historyCaches[activeId] || defaultHistoryCache()}
            onCacheChange={(c) =>
              setHistoryCaches((prev) => ({ ...prev, [activeId]: c }))
            }
            onJump={(mid) => void jumpToMessage(mid)}
            onClose={() => {
              setRight(activeId ? { kind: 'chat' } : { kind: 'empty' })
              setReturnToHistory(false)
            }}
          />
        )}

        {right.kind === 'chat' && activeId && (
          <div className="im-chat-surface">
            {returnToHistory && (
              <button
                type="button"
                className="im-return-history"
                onClick={() => {
                  setRight({ kind: 'history' })
                  setReturnToHistory(false)
                  setFocusMessageId(null)
                }}
              >
                返回查找
              </button>
            )}
          <ChatPane
            user={user}
            conversation={active}
            messages={messages}
            draft={draft}
            onDraft={setDraft}
            onSend={() => void send()}
            onSendImage={(file) => void sendImage(file)}
            onSendFile={(file) => void sendFile(file)}
            onSendVoice={(blob, duration, mime) => void sendVoice(blob, duration, mime)}
            onRecall={(id) => void recall(id)}
            onForward={(ids) => {
              setForwardIds(ids)
              setForwardOpen(true)
            }}
            onOpenHistory={() => openHistory()}
            sendingMedia={sendingMedia}
            hasMore={hasMoreMessages}
            loadingMore={loadingMore}
            onLoadMore={() => void loadOlderMessages()}
            onBack={() => {
              setMobileDetail(false)
              if (isMobile) setRight({ kind: 'empty' })
            }}
            onOpenProfile={
              active?.type === 'group'
                ? () => void openGroupProfile(active)
                : active?.type === 'dm' && active.peerUsername
                  ? () => {
                      const peer = active.peerUsername as string
                      const friend = friends.find((f) => f.username === peer)
                      if (friend) {
                        setRight({ kind: 'friendProfile', profile: friend })
                        setMobileDetail(true)
                      } else {
                        const title = (active.title || '').trim()
                        setRight({
                          kind: 'friendProfile',
                          profile: {
                            id: '',
                            username: peer,
                            remark: title && title !== peer ? title : undefined,
                            avatarUrl: active.peerAvatarUrl,
                          },
                        })
                        setMobileDetail(true)
                      }
                    }
                  : undefined
            }
            onOpenSender={
              active?.type === 'group'
                ? (senderId) => void openGroupMember(active, senderId)
                : active?.type === 'dm' && active.peerUsername
                  ? (senderId) => {
                      if (senderId === user.id) return
                      const peer = active.peerUsername as string
                      const friend = friends.find((f) => f.username === peer)
                      if (friend) {
                        setRight({ kind: 'friendProfile', profile: friend })
                        setMobileDetail(true)
                      } else {
                        const title = (active.title || '').trim()
                        setRight({
                          kind: 'friendProfile',
                          profile: {
                            id: '',
                            username: peer,
                            remark: title && title !== peer ? title : undefined,
                            avatarUrl: active.peerAvatarUrl,
                          },
                        })
                        setMobileDetail(true)
                      }
                    }
                  : undefined
            }
            onVoiceCall={
              activeId
                ? () => {
                    const ongoing = callUi.conversationCall
                    if (ongoing && ongoing.conversationId === activeId) {
                      const joined = ongoing.participants.some(
                        (p) => p.userId === user.id && p.state === 'joined',
                      )
                      if (joined || callUi.active?.id === ongoing.id) {
                        callController.restore()
                        return
                      }
                      void callController.joinCall(ongoing.id, { cameraOff: true }).catch((e) => {
                        MessagePlugin.error(apiErrorMessage(e, '无法加入语音通话'))
                      })
                      return
                    }
                    setCallSetup({ kind: 'voice', conversationId: activeId })
                  }
                : undefined
            }
            onVideoCall={
              activeId
                ? () => {
                    const ongoing = callUi.conversationCall
                    if (ongoing && ongoing.conversationId === activeId) {
                      const joined = ongoing.participants.some(
                        (p) => p.userId === user.id && p.state === 'joined',
                      )
                      if (joined || callUi.active?.id === ongoing.id) {
                        callController.restore()
                        return
                      }
                      void callController.joinCall(ongoing.id, { cameraOff: true }).catch((e) => {
                        MessagePlugin.error(apiErrorMessage(e, '无法加入视频通话'))
                      })
                      return
                    }
                    setCallSetup({ kind: 'video', conversationId: activeId })
                  }
                : undefined
            }
            ongoingCall={
              callUi.conversationCall &&
              activeId &&
              callUi.conversationCall.conversationId === activeId
                ? callUi.conversationCall
                : null
            }
            selfInOngoingCall={
              !!(
                callUi.active &&
                activeId &&
                callUi.active.conversationId === activeId
              )
            }
            ongoingCallBusy={callUi.connecting}
            onJoinOngoingCall={() => {
              const id = callUi.conversationCall?.id
              if (!id) return
              void callController.joinCall(id, { cameraOff: true }).catch((e) => {
                MessagePlugin.error(apiErrorMessage(e, '无法加入通话'))
              })
            }}
            onLeaveOngoingCall={() => {
              void callController.hangup()
            }}
            onReturnToOngoingCall={() => callController.restore()}
            onConversationPatch={(patch) => {
              if (!activeId) return
              const apply = (c: Conversation) =>
                c.id === activeId ? { ...c, ...patch } : c
              setConversations((prev) => prev.map(apply))
              setGroups((prev) => prev.map(apply))
            }}
            listRef={listRef}
            showBack={isMobile}
            focusMessageId={focusMessageId}
            selectMode={selectMode}
            selectedIds={selectedMessageIds}
            onSelectModeChange={(on) => {
              setSelectMode(on)
              if (!on) setSelectedMessageIds([])
            }}
            onToggleSelect={(id) => {
              setSelectedMessageIds((prev) =>
                prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id],
              )
            }}
          />
          </div>
        )}

        {isMobile && (
          <nav className="im-tabbar" aria-label="底部导航">
            {navBtn('messages', '消息', 'msg', totalUnread)}
            {navBtn('contacts', '联系人', 'contacts', incoming.length + groupJoins.length)}
          </nav>
        )}
      </div>

      <UserDrawer
        open={drawerOpen}
        user={user}
        onClose={() => setDrawerOpen(false)}
        onUserChange={onUserChange}
        onLogout={onLogout}
        onOpenSettings={() => {
          setRight({ kind: 'settings' })
          setMobileDetail(true)
        }}
      />

      <AddContactDialog
        visible={addOpen}
        onClose={() => setAddOpen(false)}
        onRequestSent={() => {
          void loadContacts()
          setListNav('contacts')
          setContactSection('friends')
          setRight({ kind: 'friendRequests' })
          setMobileDetail(true)
        }}
        onMessage={(username) => void startDM(username)}
        onJoined={(id) => {
          void loadContacts()
          void loadConversations()
          const g = groups.find((x) => x.id === id)
          openChat(id, g)
        }}
        onEnterGroup={(id) => {
          const g = groups.find((x) => x.id === id)
          openChat(id, g)
        }}
      />

      <ChatThemeDialog
        visible={bgOpen}
        value={resolveUserTheme(user)}
        onClose={() => setBgOpen(false)}
        onChanged={(u) => onUserChange?.(u)}
      />

      <IncomingCallModal
        onOpenChat={(id) => {
          openChat(id)
        }}
      />
      <CallSetupDialog
        visible={!!callSetup}
        kind={callSetup?.kind || 'voice'}
        title={
          active && callSetup?.conversationId === active.id
            ? conversationTitle(active)
            : '会话'
        }
        selfName={user.username}
        selfAvatar={user.avatarUrl}
        busy={callSetupBusy}
        onCancel={() => {
          if (callSetupBusy) return
          setCallSetup(null)
        }}
        onConfirm={(result: CallSetupResult) => {
          if (!callSetup) return
          const { conversationId } = callSetup
          setCallSetupBusy(true)
          void callController
            .startCall(conversationId, result.kind, {
              muted: result.muted,
              cameraOff: result.cameraOff,
              stream: result.stream,
            })
            .then(() => {
              setCallSetup(null)
            })
            .catch((e) => {
              const msg = apiErrorMessage(
                e,
                result.kind === 'video' ? '无法发起视频通话' : '无法发起语音通话',
              )
              MessagePlugin.error(msg)
              if (
                String((e as { message?: string })?.message || '').includes(
                  'conversation already has an active call',
                ) ||
                msg.includes('已有通话')
              ) {
                void callController.watchConversation(conversationId)
              }
            })
            .finally(() => setCallSetupBusy(false))
        }}
      />
      <CallOverlay
        selfName={user.username}
        selfAvatar={user.avatarUrl}
        resolveTitle={(id) => {
          const c =
            conversations.find((x) => x.id === id) || groups.find((x) => x.id === id)
          return c ? conversationTitle(c) : undefined
        }}
      />

      <Dialog
        visible={renameUserOpen}
        header="修改昵称"
        onClose={() => setRenameUserOpen(false)}
        onConfirm={async () => {
          const name = renameUserDraft.trim()
          if (!name) {
            MessagePlugin.warning('请输入昵称')
            return
          }
          try {
            const u = await api.patchMe({ username: name })
            onUserChange?.(u)
            setRenameUserOpen(false)
            MessagePlugin.success('昵称已更新')
          } catch (e) {
            MessagePlugin.error(apiErrorMessage(e, '修改失败'))
          }
        }}
        confirmBtn="保存"
        cancelBtn="取消"
      >
        <p className="im-muted" style={{ marginTop: 0 }}>
          1–32 个字符，可用中文、字母、数字、空格等。
        </p>
        <Input
          autofocus
          maxlength={32}
          placeholder="昵称"
          value={renameUserDraft}
          onChange={(v) => setRenameUserDraft(String(v))}
        />
      </Dialog>

      {activeId && (
        <ForwardDialog
          visible={forwardOpen}
          sourceConversationId={activeId}
          messageIds={forwardIds}
          conversations={conversations}
          onClose={() => {
            setForwardOpen(false)
            setForwardIds([])
          }}
          onDone={() => {
            setSelectMode(false)
            setSelectedMessageIds([])
            void loadConversations()
          }}
        />
      )}

      <Dialog
        visible={groupOpen}
        header="创建群聊"
        onClose={() => setGroupOpen(false)}
        onConfirm={async () => {
          try {
            const members = selectedMemberIds
              .map((id) => friendNamesById[id])
              .filter(Boolean)
            const title =
              groupTitle.trim() ||
              (members.length ? `${user.username}、${members.slice(0, 2).join('、')}的群` : '')
            const c = await api.createGroup(title, members)
            MessagePlugin.success(c.groupNo ? `群已创建，群号 ${c.groupNo}` : '群已创建')
            setGroupOpen(false)
            setGroupTitle('')
            setSelectedMemberIds([])
            await loadContacts()
            openChat(c.id, c)
          } catch (e) {
            MessagePlugin.error(apiErrorMessage(e, '创建失败'))
          }
        }}
        confirmBtn="创建"
      >
        <div className="im-auth-fields">
          <Input
            placeholder="群名称（可选）"
            value={groupTitle}
            onChange={(v) => setGroupTitle(String(v))}
          />
          <p className="im-muted">勾选要邀请的好友</p>
          <div className="im-friend-pick">
            {friends.length === 0 ? (
              <p className="im-muted">暂无好友，请先添加好友</p>
            ) : (
              friends.map((f) => (
                <label key={f.id} className="im-friend-pick__row">
                  <Checkbox
                    checked={selectedMemberIds.includes(f.id)}
                    onChange={(checked) => {
                      setSelectedMemberIds((prev) =>
                        checked ? [...prev, f.id] : prev.filter((x) => x !== f.id),
                      )
                    }}
                  />
                  <Avatar name={f.remark || f.username} src={f.avatarUrl} size="sm" />
                  <span>{f.remark || f.username}</span>
                </label>
              ))
            )}
          </div>
        </div>
      </Dialog>
    </div>
  )
}
