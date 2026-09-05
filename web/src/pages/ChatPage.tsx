import { useCallback, useEffect, useRef, useState } from 'react'
import { ChevronRightIcon } from 'tdesign-icons-react'
import { Button, Checkbox, Dialog, Input, MessagePlugin, Switch } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  getToken,
  setToken,
  type Contact,
  type Conversation,
  type FriendRequest,
  type Message,
  type QQStatus,
  type User,
} from '../api'
import { AddContactDialog } from '../components/AddContactDialog'
import { Avatar } from '../components/Avatar'
import { ChatBackgroundDialog } from '../components/ChatBackgroundDialog'
import { ChatPane } from '../components/ChatPane'
import { ContactList } from '../components/ContactList'
import { ForwardDialog } from '../components/ForwardDialog'
import { FriendProfile } from '../components/FriendProfile'
import { GroupProfile } from '../components/GroupProfile'
import {
  ChatHistoryPanel,
  defaultHistoryCache,
  type HistoryCache,
} from '../components/history/ChatHistoryPanel'
import { PlusMenu } from '../components/PlusMenu'
import { SessionList } from '../components/SessionList'
import { UserDrawer } from '../components/UserDrawer'
import { useIsMobile } from '../hooks/useIsMobile'
import { chatBgSummary } from '../lib/chatBg'
import { initialOf } from '../lib/chatFormat'

type Props = {
  user: User
  onUserChange?: (u: User) => void
  onLogout: () => void
}

type ListNav = 'messages' | 'contacts'
type ContactSection = 'friends' | 'groups' | 'requests'
/** Right pane surface — independent of listNav so switching tabs keeps chat. */
type RightSurface =
  | { kind: 'empty' }
  | { kind: 'chat' }
  | { kind: 'history' }
  | { kind: 'friendProfile'; profile: Contact }
  | { kind: 'groupProfile'; group: Conversation }
  | { kind: 'settings' }

export function ChatPage({ user, onUserChange, onLogout }: Props) {
  const isMobile = useIsMobile()
  const [listNav, setListNav] = useState<ListNav>('messages')
  const [contactSection, setContactSection] = useState<ContactSection>('friends')
  const [right, setRight] = useState<RightSurface>({ kind: 'empty' })
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [friends, setFriends] = useState<Contact[]>([])
  const [groups, setGroups] = useState<Conversation[]>([])
  const [incoming, setIncoming] = useState<FriendRequest[]>([])
  const [activeId, setActiveId] = useState<string | null>(null)
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
      const [f, g, req] = await Promise.all([
        api.listFriends(),
        api.listGroups(),
        api.listFriendRequests(),
      ])
      setFriends(f.friends)
      setGroups(g.groups)
      setIncoming(req.incoming)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '加载联系人失败'))
    }
  }, [])

  const loadMessages = useCallback(
    async (id: string) => {
      try {
        const res = await api.listMessages(id)
        setMessages(res.messages)
        setHasMoreMessages(!!res.hasMore)
        void loadConversations()
      } catch (e) {
        MessagePlugin.error(apiErrorMessage(e, '加载消息失败'))
      }
    },
    [loadConversations],
  )

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
  }, [loadConversations])

  useEffect(() => {
    if (listNav === 'contacts') void loadContacts()
  }, [listNav, loadContacts])

  useEffect(() => {
    if (right.kind === 'settings') void loadQQ()
  }, [right.kind, loadQQ])

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
          setMessages((prev) => {
            if (prev.some((m) => m.id === data.message!.id)) return prev
            return [...prev, data.message!]
          })
          void loadConversations()
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
  }, [activeId, right.kind, loadMessages, loadConversations])

  useEffect(() => {
    if (focusMessageId) return
    const el = listRef.current
    if (el) el.scrollTop = el.scrollHeight
  }, [messages, focusMessageId])

  const active =
    conversations.find((c) => c.id === activeId) || groups.find((c) => c.id === activeId)

  const openChat = (id: string) => {
    setListNav('messages')
    setActiveId(id)
    setRight({ kind: 'chat' })
    setMobileDetail(true)
    setSelectMode(false)
    setSelectedMessageIds([])
    setReturnToHistory(false)
    setFocusMessageId(null)
    void loadConversations()
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
      const c = await api.createDM(username)
      openChat(c.id)
      MessagePlugin.success('已打开会话')
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
    }
  }

  const navBtn = (id: ListNav, label: string, ico: string, badge?: number) => (
    <button
      type="button"
      className={listNav === id ? 'im-nav-btn is-active' : 'im-nav-btn'}
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

  return (
    <div className={isMobile ? 'im-shell im-shell--mobile' : 'im-shell'}>
      <div className={frameClass}>
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
            {navBtn('contacts', '联系人', 'contacts')}
            <button
              type="button"
              className={right.kind === 'settings' ? 'im-nav-btn is-active' : 'im-nav-btn'}
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
                incoming={incoming}
                filter={filter}
                selectedFriendId={
                  right.kind === 'friendProfile' ? right.profile.id : null
                }
                selectedGroupId={
                  right.kind === 'groupProfile' ? right.group.id : null
                }
                onSelectFriend={(f) => {
                  setRight({ kind: 'friendProfile', profile: f })
                  setMobileDetail(true)
                  setContactSection('friends')
                }}
                onSelectGroup={(g) => void openGroupProfile(g)}
                onOpenRequests={() => {
                  setContactSection('requests')
                  setMobileDetail(false)
                  setRight({ kind: 'empty' })
                }}
                onAccept={async (id) => {
                  try {
                    await api.acceptFriendRequest(id)
                    MessagePlugin.success('已添加好友')
                    await loadContacts()
                  } catch (e) {
                    MessagePlugin.error(apiErrorMessage(e, '操作失败'))
                  }
                }}
                onReject={async (id) => {
                  try {
                    await api.rejectFriendRequest(id)
                    await loadContacts()
                  } catch (e) {
                    MessagePlugin.error(apiErrorMessage(e, '操作失败'))
                  }
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
                  <span className="im-set-cell__label">聊天背景</span>
                  <span className="im-set-cell__value">{chatBgSummary(user.chatBg)}</span>
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
            onLeave={async () => {
              try {
                await api.leaveGroup(right.group.id)
                MessagePlugin.success('已退出群聊')
                if (activeId === right.group.id) setActiveId(null)
                setRight({ kind: 'empty' })
                setMobileDetail(false)
                await loadContacts()
                await loadConversations()
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
            onMessage={() => void startDM(right.profile.username)}
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

        {right.kind === 'empty' && !isMobile && listNav === 'contacts' && contactSection !== 'requests' && (
          <section className="im-pane">
            <div className="im-empty">
              <div className="im-logo-mark">IHope</div>
              <p>选择好友查看资料，或打开群资料</p>
            </div>
          </section>
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
            {navBtn('contacts', '联系人', 'contacts')}
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
        onRequestSent={() => void loadContacts()}
        onMessage={(username) => void startDM(username)}
        onJoined={(id) => {
          void loadContacts()
          void loadConversations()
          openChat(id)
        }}
        onEnterGroup={(id) => openChat(id)}
      />

      <ChatBackgroundDialog
        visible={bgOpen}
        value={user.chatBg}
        onClose={() => setBgOpen(false)}
        onChanged={(u) => onUserChange?.(u)}
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
            openChat(c.id)
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
