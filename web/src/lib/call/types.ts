export type CallKind = 'voice' | 'video'

export type CallPeer = {
  userId: string
  username: string
  avatarUrl?: string | null
  state: 'invited' | 'joined' | 'left' | 'rejected' | string
  audio: boolean
  video: boolean
}

export type CallRoom = {
  id: string
  conversationId: string
  convType: string
  kind: CallKind
  hostId: string
  status: 'ringing' | 'active' | 'ended' | string
  createdAt: string
  startedAt?: string
  participants: CallPeer[]
}

export type CallBody = {
  kind: CallKind | string
  status: string
  durationSec?: number
}

export type RemoteMedia = {
  userId: string
  stream: MediaStream
  username?: string
  avatarUrl?: string | null
}
