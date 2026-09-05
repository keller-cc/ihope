export type ChatBg = {
  kind: 'default' | 'gradient' | 'color' | 'image'
  id?: string
  hex?: string
  url?: string
}

export type User = {
  id: string
  email: string
  username: string
  emailVerified?: boolean
  hopeId?: string | null
  hopeIdChangedAt?: string | null
  avatarUrl?: string | null
  chatBg?: ChatBg | null
}

export type Conversation = {
  id: string
  type: string
  title: string
  createdAt: string
  peerUsername?: string
  peerAvatarUrl?: string | null
  memberCount?: number
  lastMessage?: string
  lastMessageAt?: string
  unreadCount?: number
  groupNo?: string | null
  ownerId?: string | null
  isOwner?: boolean
  isAdmin?: boolean
  pinned?: boolean
  muted?: boolean
  pinnedAt?: string | null
  avatarUrl?: string | null
  joined?: boolean
}

export type Contact = {
  id: string
  username: string
  email?: string
  hopeId?: string | null
  avatarUrl?: string | null
  remark?: string
  isFriend?: boolean
  role?: string
  isAdmin?: boolean
  memberTitle?: string
}

export type PublicUser = {
  id: string
  username: string
  hopeId?: string | null
  avatarUrl?: string | null
  isFriend: boolean
  isSelf: boolean
}

export type PublicGroup = {
  id: string
  title: string
  groupNo?: string | null
  memberCount: number
  avatarUrl?: string | null
  joined: boolean
}

export type FriendRequest = {
  id: string
  fromUserId: string
  toUserId: string
  status: string
  message: string
  createdAt: string
  fromUser?: Contact
  toUser?: Contact
}

export type Message = {
  id: string
  conversationId: string
  senderId: string
  senderUsername?: string
  senderAvatarUrl?: string | null
  senderTitle?: string
  type: string
  body: string
  createdAt: string
  recalled?: boolean
  recalledAt?: string | null
  recalledBy?: string | null
}

export type MessageDay = {
  day: string
  count: number
}

export type ForwardItem = {
  senderName: string
  type: string
  body?: string
  thumbUrl?: string
  url?: string
  name?: string
  size?: number
  createdAt: string
}

export type ForwardBody = {
  fromTitle: string
  fromType: string
  items: ForwardItem[]
}

export type QQStatus = {
  botEnabled: boolean
  bound: boolean
  doorbellEnabled?: boolean
  boundAt?: string
}

const DEFAULT_TOKEN_KEY = 'ihope_web_token'
const SLOT_SESSION_KEY = 'ihope_web_slot'

/** 多开测试：?slot=a 与 ?slot=b 使用不同登录态；同一 slot 刷新仍保持。 */
export function getSessionSlot(): string {
  try {
    const fromUrl = new URLSearchParams(window.location.search).get('slot')?.trim()
    if (fromUrl) {
      sessionStorage.setItem(SLOT_SESSION_KEY, fromUrl)
      return fromUrl
    }
    return sessionStorage.getItem(SLOT_SESSION_KEY) || ''
  } catch {
    return ''
  }
}

function tokenKey(): string {
  const slot = getSessionSlot()
  return slot ? `${DEFAULT_TOKEN_KEY}__${slot}` : DEFAULT_TOKEN_KEY
}

export function getToken(): string | null {
  return localStorage.getItem(tokenKey())
}

export function setToken(token: string | null) {
  const key = tokenKey()
  if (token) localStorage.setItem(key, token)
  else localStorage.removeItem(key)
}

/** 合并进行中的相同 GET，避免 StrictMode / 重复 effect 打出双份请求。 */
const inflightGets = new Map<string, Promise<unknown>>()

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const method = (init.method || 'GET').toUpperCase()
  const dedupe = method === 'GET' && init.body == null
  if (dedupe) {
    const hit = inflightGets.get(path)
    if (hit) return hit as Promise<T>
  }

  const run = (async () => {
    const headers = new Headers(init.headers)
    if (!headers.has('Content-Type') && init.body) {
      headers.set('Content-Type', 'application/json')
    }
    const token = getToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)

    const res = await fetch(path, { ...init, headers })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error((data as { error?: string }).error || res.statusText) as Error & {
        code?: string
      }
      err.code = (data as { error?: string }).error
      throw err
    }
    return data as T
  })()

  if (dedupe) {
    inflightGets.set(path, run)
    void run.finally(() => {
      if (inflightGets.get(path) === run) inflightGets.delete(path)
    })
  }
  return run
}

/** Map API error codes to Chinese UI messages. */
export function apiErrorMessage(e: unknown, fallback: string): string {
  const code =
    e instanceof Error
      ? ((e as Error & { code?: string }).code || e.message || '').trim()
      : ''
  const map: Record<string, string> = {
    'email taken': '该邮箱已被注册',
    'username taken': '该用户名已被占用',
    'qq_bot_disabled': 'QQ 机器人未启用',
    'qq not bound': '该用户未绑定 QQ',
    'create bind code failed': '生成绑定码失败',
    'unbind failed': '解绑失败',
    'username must be 1-32 characters after trim': '用户名须为 1–32 个字符（字母/中文/数字等）',
    'nothing to update': '没有可更新的内容',
    'invalid fellowship code': '团契码不正确',
    'invalid credentials': '账号或密码错误',
    email_not_verified: '请先完成邮箱验证',
    'invalid verify token': '验证链接无效或已过期',
    unauthorized: '请重新登录',
    forbidden: '没有权限',
    'user not found': '用户不存在',
    'cannot add yourself': '不能添加自己',
    'cannot dm yourself': '不能和自己私聊',
    'group title required': '请填写群名称',
    'group needs at least one other member': '群聊至少需要一名其他成员',
    'group not found': '群不存在或群号错误',
    'not a group': '不是群聊',
    'only owner can rename': '仅群主可修改群名称',
    'invalid hope id': 'IHope 号无效',
    'hope id taken': '该 IHope 号已被占用',
    'hope id cooldown': 'IHope 号 30 天内只能刷新一次',
    'quotes disabled': '今日金句未配置',
    'quotes error': '无法读取今日金句',
    'already friends': '已经是好友',
    'friend request pending': '已发送过好友申请，请等待对方处理',
    'not friends': '还不是好友，请先添加好友',
    'request not found': '申请不存在或已处理',
    'friend request sent': '好友申请已发送',
    'query required': '请输入查找内容',
    'file required': '请选择图片',
    'file too large': '图片过大（最大 10MB）',
    'invalid image': '无法识别的图片格式',
    'empty message': '消息不能为空',
    'invalid form': '上传表单无效',
    'remark too long': '备注最多 32 字',
    'no new members': '没有可邀请的新成员',
    'only owner can kick': '仅群主可移除成员',
    'only owner can dissolve': '仅群主可解散群聊',
    'only owner can set admin': '仅群主可设置管理员',
    'cannot kick yourself': '不能移除自己',
    'cannot kick owner': '不能移除群主',
    'admin cannot kick admin': '管理员不能移除其他管理员',
    'cannot change own role': '不能修改自己的身份',
    'cannot change owner role': '不能修改群主身份',
    'invalid role': '无效的成员身份',
    'member not found': '成员不在群中',
    'invalid file': '文件无效',
    'title too long': '头衔最多 12 字',
    'recall expired': '超过 5 分钟，无法撤回',
    'message not found': '消息不存在',
  }
  if (code && map[code]) return map[code]
  if (code && !/^[a-z_ ]+$/i.test(code)) return code
  return fallback
}

export const api = {
  register: (email: string, username: string, password: string, fellowshipCode: string) =>
    request<{
      user: User
      message: string
      devVerifyToken?: string
    }>('/api/auth/register', {
      method: 'POST',
      body: JSON.stringify({ email, username, password, fellowshipCode }),
    }),
  login: (login: string, password: string) =>
    request<{ user: User; token: string }>('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ login, password }),
    }),
  resendVerification: (email: string) =>
    request<{ message: string; devVerifyToken?: string }>(
      '/api/auth/resend-verification',
      {
        method: 'POST',
        body: JSON.stringify({ email }),
      },
    ),
  verifyEmail: (token: string) =>
    request<{ message: string }>('/api/auth/verify-email', {
      method: 'POST',
      body: JSON.stringify({ token }),
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    }),
  me: () => request<User>('/api/me'),
  patchMe: (body: { username: string }) =>
    request<User>('/api/me', {
      method: 'PATCH',
      body: JSON.stringify(body),
    }),
  todayQuote: () =>
    request<{ body: string; author?: string; date: string }>('/api/quotes/today'),
  refreshHopeId: () =>
    request<User>('/api/me/hope-id/refresh', {
      method: 'POST',
    }),
  uploadAvatar: async (file: File) => {
    const fd = new FormData()
    fd.append('file', file)
    const headers = new Headers()
    const token = getToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)
    const res = await fetch('/api/me/avatar', { method: 'POST', headers, body: fd })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error((data as { error?: string }).error || res.statusText) as Error & {
        code?: string
      }
      err.code = (data as { error?: string }).error
      throw err
    }
    return data as User
  },
  uploadGroupAvatar: async (id: string, file: File) => {
    const fd = new FormData()
    fd.append('file', file)
    const headers = new Headers()
    const token = getToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)
    const res = await fetch(`/api/conversations/${id}/avatar`, {
      method: 'POST',
      headers,
      body: fd,
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error((data as { error?: string }).error || res.statusText) as Error & {
        code?: string
      }
      err.code = (data as { error?: string }).error
      throw err
    }
    return data as Conversation
  },
  searchUser: (q: string) =>
    request<PublicUser>(`/api/search/users?q=${encodeURIComponent(q)}`),
  searchGroup: (q: string) =>
    request<PublicGroup>(`/api/search/groups?q=${encodeURIComponent(q)}`),
  setFriendRemark: (friendId: string, remark: string) =>
    request<Contact>(`/api/contacts/friends/${friendId}`, {
      method: 'PATCH',
      body: JSON.stringify({ remark }),
    }),
  listConversations: () =>
    request<{ conversations: Conversation[] }>('/api/conversations'),
  createDM: (username: string) =>
    request<Conversation>('/api/conversations/dm', {
      method: 'POST',
      body: JSON.stringify({ username }),
    }),
  createGroup: (title: string, members: string[]) =>
    request<Conversation>('/api/conversations/group', {
      method: 'POST',
      body: JSON.stringify({ title, members }),
    }),
  joinGroup: (groupNo: string) =>
    request<Conversation>('/api/conversations/group/join', {
      method: 'POST',
      body: JSON.stringify({ groupNo }),
    }),
  listGroupMembers: (id: string) =>
    request<{ members: Contact[] }>(`/api/conversations/${id}/members`),
  renameGroup: (id: string, title: string) =>
    request<Conversation>(`/api/conversations/${id}`, {
      method: 'PATCH',
      body: JSON.stringify({ title }),
    }),
  leaveGroup: (id: string) =>
    request<{ message: string }>(`/api/conversations/${id}/leave`, {
      method: 'POST',
    }),
  listFriends: () => request<{ friends: Contact[] }>('/api/contacts/friends'),
  addFriend: (username: string, message = '') =>
    request<FriendRequest>('/api/contacts/friends', {
      method: 'POST',
      body: JSON.stringify({ username, message }),
    }),
  listFriendRequests: () =>
    request<{ incoming: FriendRequest[]; outgoing: FriendRequest[] }>(
      '/api/contacts/friend-requests',
    ),
  acceptFriendRequest: (id: string) =>
    request<Contact>(`/api/contacts/friend-requests/${id}/accept`, { method: 'POST' }),
  rejectFriendRequest: (id: string) =>
    request<{ message: string }>(`/api/contacts/friend-requests/${id}/reject`, {
      method: 'POST',
    }),
  listGroups: () => request<{ groups: Conversation[] }>('/api/contacts/groups'),
  patchConversationMember: (
    id: string,
    prefs: { pinned?: boolean; muted?: boolean; hidden?: boolean },
  ) =>
    request<{ message: string }>(`/api/conversations/${id}/member`, {
      method: 'PATCH',
      body: JSON.stringify(prefs),
    }),
  patchMeChatBg: (chatBg: ChatBg) =>
    request<User>('/api/me/chat-bg', {
      method: 'PATCH',
      body: JSON.stringify(chatBg),
    }),
  uploadMeChatBg: async (file: File) => {
    const fd = new FormData()
    fd.append('file', file)
    const headers = new Headers()
    const token = getToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)
    const res = await fetch('/api/me/chat-bg', {
      method: 'POST',
      headers,
      body: fd,
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error((data as { error?: string }).error || res.statusText) as Error & {
        code?: string
      }
      err.code = (data as { error?: string }).error
      throw err
    }
    return data as User
  },
  markRead: (id: string) =>
    request<{ message: string }>(`/api/conversations/${id}/read`, { method: 'POST' }),
  listMessages: (
    id: string,
    opts?: {
      before?: string
      type?: string
      senderId?: string
      senderIds?: string[]
      day?: string
    },
  ) => {
    const p = new URLSearchParams()
    if (opts?.before) p.set('before', opts.before)
    if (opts?.type) p.set('type', opts.type)
    if (opts?.senderId) p.set('senderId', opts.senderId)
    if (opts?.senderIds?.length) p.set('senderIds', opts.senderIds.join(','))
    if (opts?.day) p.set('day', opts.day)
    const q = p.toString() ? `?${p}` : ''
    return request<{ messages: Message[]; hasMore: boolean }>(
      `/api/conversations/${id}/messages${q}`,
    )
  },
  searchMessages: (
    id: string,
    query: string,
    before?: string,
    opts?: { day?: string; senderIds?: string[] },
  ) => {
    const p = new URLSearchParams({ q: query })
    if (before) p.set('before', before)
    if (opts?.day) p.set('day', opts.day)
    if (opts?.senderIds?.length) p.set('senderIds', opts.senderIds.join(','))
    return request<{ messages: Message[]; hasMore: boolean }>(
      `/api/conversations/${id}/messages/search?${p}`,
    )
  },
  listMessageDays: (id: string) =>
    request<{ days: MessageDay[] }>(`/api/conversations/${id}/messages/days`),
  messageContext: (id: string, messageId: string) =>
    request<{ messages: Message[] }>(
      `/api/conversations/${id}/messages/${messageId}/context`,
    ),
  forwardMessages: (
    targetId: string,
    body: {
      sourceConversationId: string
      messageIds: string[]
      mode: 'one_by_one' | 'merge'
    },
  ) =>
    request<{ messages: Message[] }>(`/api/conversations/${targetId}/messages/forward`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  sendMessage: (id: string, body: string) =>
    request<Message>(`/api/conversations/${id}/messages`, {
      method: 'POST',
      body: JSON.stringify({ body }),
    }),
  sendImage: async (id: string, file: File) => {
    const fd = new FormData()
    fd.append('file', file)
    const headers = new Headers()
    const token = getToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)
    const res = await fetch(`/api/conversations/${id}/messages/image`, {
      method: 'POST',
      headers,
      body: fd,
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error((data as { error?: string }).error || res.statusText) as Error & {
        code?: string
      }
      err.code = (data as { error?: string }).error
      throw err
    }
    return data as Message
  },
  sendFile: async (id: string, file: File) => {
    const fd = new FormData()
    fd.append('file', file)
    const headers = new Headers()
    const token = getToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)
    const res = await fetch(`/api/conversations/${id}/messages/file`, {
      method: 'POST',
      headers,
      body: fd,
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error((data as { error?: string }).error || res.statusText) as Error & {
        code?: string
      }
      err.code = (data as { error?: string }).error
      throw err
    }
    return data as Message
  },
  sendVoice: async (id: string, file: Blob, duration: number, mime?: string) => {
    const fd = new FormData()
    const ext = mime?.includes('ogg')
      ? 'ogg'
      : mime?.includes('mp4') || mime?.includes('m4a')
        ? 'm4a'
        : mime?.includes('mpeg') || mime?.includes('mp3')
          ? 'mp3'
          : 'webm'
    fd.append('file', file, `voice.${ext}`)
    fd.append('duration', String(duration))
    if (mime) fd.append('mime', mime)
    const headers = new Headers()
    const token = getToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)
    const res = await fetch(`/api/conversations/${id}/messages/voice`, {
      method: 'POST',
      headers,
      body: fd,
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error((data as { error?: string }).error || res.statusText) as Error & {
        code?: string
      }
      err.code = (data as { error?: string }).error
      throw err
    }
    return data as Message
  },
  inviteGroupMembers: (id: string, memberIds: string[]) =>
    request<Conversation>(`/api/conversations/${id}/invite`, {
      method: 'POST',
      body: JSON.stringify({ memberIds }),
    }),
  kickGroupMember: (id: string, memberId: string) =>
    request<{ message: string }>(`/api/conversations/${id}/kick`, {
      method: 'POST',
      body: JSON.stringify({ memberId }),
    }),
  setGroupMemberRole: (id: string, memberId: string, role: 'admin' | 'member') =>
    request<{ message: string }>(`/api/conversations/${id}/members/role`, {
      method: 'PATCH',
      body: JSON.stringify({ memberId, role }),
    }),
  setGroupMemberTitle: (id: string, memberId: string, title: string) =>
    request<{ message: string }>(`/api/conversations/${id}/members/title`, {
      method: 'PATCH',
      body: JSON.stringify({ memberId, title }),
    }),
  dissolveGroup: (id: string) =>
    request<{ message: string }>(`/api/conversations/${id}/dissolve`, { method: 'POST' }),
  recallMessage: (conversationId: string, messageId: string) =>
    request<Message>(`/api/conversations/${conversationId}/messages/${messageId}/recall`, {
      method: 'POST',
    }),
  qqStatus: () => request<QQStatus>('/api/me/qq-bot'),
  qqBindCode: () =>
    request<{ code: string; expiresAt: string; botAddHint: string }>(
      '/api/me/qq-bot/bind-code',
      { method: 'POST' },
    ),
  qqPatch: (doorbellEnabled: boolean) =>
    request<{ message: string }>('/api/me/qq-bot', {
      method: 'PATCH',
      body: JSON.stringify({ doorbellEnabled }),
    }),
  qqUnbind: () =>
    request<{ message: string }>('/api/me/qq-bot', { method: 'DELETE' }),
}

const ADMIN_TOKEN_KEY = 'ihope_web_admin_token'

export function getAdminToken(): string | null {
  return sessionStorage.getItem(ADMIN_TOKEN_KEY)
}

export function setAdminToken(token: string | null) {
  if (token) sessionStorage.setItem(ADMIN_TOKEN_KEY, token)
  else sessionStorage.removeItem(ADMIN_TOKEN_KEY)
}

/** 合并进行中的相同 GET（含管理端）。 */
const inflightAdminGets = new Map<string, Promise<unknown>>()

async function adminRequest<T>(path: string, init: RequestInit = {}): Promise<T> {
  const method = (init.method || 'GET').toUpperCase()
  const dedupe = method === 'GET' && init.body == null
  if (dedupe) {
    const hit = inflightAdminGets.get(path)
    if (hit) return hit as Promise<T>
  }

  const run = (async () => {
    const headers = new Headers(init.headers)
    if (!headers.has('Content-Type') && init.body) {
      headers.set('Content-Type', 'application/json')
    }
    const token = getAdminToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)
    const res = await fetch(path, { ...init, headers })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error((data as { error?: string }).error || res.statusText) as Error & {
        code?: string
      }
      err.code = (data as { error?: string }).error
      throw err
    }
    return data as T
  })()

  if (dedupe) {
    inflightAdminGets.set(path, run)
    void run.finally(() => {
      if (inflightAdminGets.get(path) === run) inflightAdminGets.delete(path)
    })
  }
  return run
}

export type AdminUser = {
  id: string
  email: string
  username: string
  hopeId?: string | null
  emailVerified: boolean
  createdAt: string
  qqBound?: boolean
  qqOpenId?: string | null
}

export type AdminConversation = {
  id: string
  type: string
  title: string
  memberCount: number
  createdAt: string
  members: string
}

export type AdminQQBinding = {
  userId: string
  username: string
  email: string
  hopeId?: string | null
  qqOpenId: string
  doorbellEnabled: boolean
  boundAt: string
}

export const adminApi = {
  listUsers: () => adminRequest<{ users: AdminUser[] }>('/api/admin/users'),
  deleteUser: (id: string) =>
    adminRequest<{ message: string }>(`/api/admin/users/${id}`, { method: 'DELETE' }),
  listConversations: () =>
    adminRequest<{ conversations: AdminConversation[] }>('/api/admin/conversations'),
  deleteConversation: (id: string) =>
    adminRequest<{ message: string }>(`/api/admin/conversations/${id}`, {
      method: 'DELETE',
    }),
  listQQBindings: () =>
    adminRequest<{
      botEnabled: boolean
      bindings: AdminQQBinding[]
      botAddHint?: string
    }>('/api/admin/qq-bindings'),
  createQQBindCode: (userId: string) =>
    adminRequest<{ code: string; expiresAt: string; botAddHint: string }>(
      `/api/admin/users/${userId}/qq-bind-code`,
      { method: 'POST' },
    ),
  unbindQQ: (userId: string) =>
    adminRequest<{ message: string }>(`/api/admin/users/${userId}/qq-bot`, {
      method: 'DELETE',
    }),
}
