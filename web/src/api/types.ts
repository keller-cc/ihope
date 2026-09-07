export type ChatBg = {
  kind: 'default' | 'gradient' | 'color' | 'image'
  id?: string
  hex?: string
  url?: string
}

export type ChatBgImage = {
  id: string
  url: string
  createdAt: string
}

/** QQ 式随心调：主题色 / 气泡 / 背景 / 纹理 / 透明度 / 毛玻璃 */
export type ChatTheme = {
  accent?: string
  bubbleMine?: string
  bubblePeer?: string
  background?: ChatBg | null
  texture?: string
  /** 0–1 面板透明度（不影响气泡） */
  opacity?: number
  /** 0–1 毛玻璃模糊强度（与透明度独立） */
  blur?: number
}

export type User = {
  id: string
  email: string
  username: string
  emailVerified?: boolean
  hopeId?: string | null
  avatarUrl?: string | null
  chatTheme?: ChatTheme | null
  /** @deprecated use chatTheme.background */
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

export type CallKind = 'voice' | 'video'

export type CallPeer = {
  userId: string
  username: string
  avatarUrl?: string | null
  state: string
  audio: boolean
  video: boolean
}

export type CallRoom = {
  id: string
  conversationId: string
  convType: string
  kind: CallKind
  hostId: string
  status: string
  createdAt: string
  startedAt?: string
  participants: CallPeer[]
}

export type CallIceServer = {
  urls: string[]
  username?: string
  credential?: string
}

export type QQStatus = {
  botEnabled: boolean
  bound: boolean
  doorbellEnabled?: boolean
  boundAt?: string
}
