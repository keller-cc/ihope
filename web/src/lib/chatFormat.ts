/** Shared chat display helpers. */
import type { Conversation } from '../api'

export function initialOf(name: string): string {
  const t = name.trim()
  return t ? t.slice(0, 1) : '?'
}

/** 会话列表右侧时间（今天 HH:mm，否则 M/d HH:mm）。 */
export function formatMessageTime(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const now = new Date()
  const sameDay =
    d.getFullYear() === now.getFullYear() &&
    d.getMonth() === now.getMonth() &&
    d.getDate() === now.getDate()
  const hm = formatHm(d)
  if (sameDay) return hm
  return `${d.getMonth() + 1}/${d.getDate()} ${hm}`
}

/** 相邻消息间隔超过该分钟数则插入居中时间条（微信/QQ 惯例）。 */
export const MESSAGE_TIME_DIVIDER_GAP_MINUTES = 5

export function shouldShowMessageTimeDivider(
  previousIso: string | undefined,
  currentIso: string,
): boolean {
  if (!previousIso) return true
  const prev = new Date(previousIso).getTime()
  const cur = new Date(currentIso).getTime()
  if (Number.isNaN(prev) || Number.isNaN(cur)) return false
  return cur - prev >= MESSAGE_TIME_DIVIDER_GAP_MINUTES * 60_000
}

/** 居中时间条（微信/QQ 惯例）：今天 HH:mm，昨天，近 7 天星期，同年日期，跨年完整日期。 */
export function formatMessageTimeDivider(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const now = new Date()
  const today = dateOnly(now)
  const msgDay = dateOnly(d)
  const hm = formatHm(d)
  const dayDiff = Math.round((today.getTime() - msgDay.getTime()) / 86_400_000)

  if (dayDiff === 0) return hm
  if (dayDiff === 1) return `昨天 ${hm}`
  if (dayDiff >= 2 && dayDiff < 7) return `${WEEKDAYS[d.getDay()]} ${hm}`
  if (d.getFullYear() === now.getFullYear()) {
    return `${d.getMonth() + 1}月${d.getDate()}日 ${hm}`
  }
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 ${hm}`
}

const WEEKDAYS = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']

function formatHm(d: Date): string {
  const h = String(d.getHours()).padStart(2, '0')
  const m = String(d.getMinutes()).padStart(2, '0')
  return `${h}:${m}`
}

function dateOnly(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

export function conversationTitle(c: Conversation): string {
  // DM：title 为备注（有则）或原名；peerUsername 始终是对方原用户名
  if (c.type === 'dm') return c.title || c.peerUsername || '私聊'
  return c.title || '群聊'
}

export type ImagePayload = {
  thumbUrl: string
  url: string
  w?: number
  h?: number
}

export function parseImageBody(body: string): ImagePayload | null {
  try {
    const o = JSON.parse(body) as Partial<ImagePayload>
    if (o && typeof o.thumbUrl === 'string' && typeof o.url === 'string') {
      return { thumbUrl: o.thumbUrl, url: o.url, w: o.w, h: o.h }
    }
  } catch {
    /* ignore */
  }
  return null
}

export type FilePayload = {
  url: string
  name: string
  size?: number
  mime?: string
}

export function parseFileBody(body: string): FilePayload | null {
  try {
    const o = JSON.parse(body) as Partial<FilePayload>
    if (o && typeof o.url === 'string' && typeof o.name === 'string') {
      return { url: o.url, name: o.name, size: o.size, mime: o.mime }
    }
  } catch {
    /* ignore */
  }
  return null
}

export type VoicePayload = {
  url: string
  duration: number
  size?: number
  mime?: string
}

export function parseVoiceBody(body: string): VoicePayload | null {
  try {
    const o = JSON.parse(body) as Partial<VoicePayload>
    if (o && typeof o.url === 'string' && typeof o.duration === 'number' && o.duration > 0) {
      return { url: o.url, duration: o.duration, size: o.size, mime: o.mime }
    }
  } catch {
    /* ignore */
  }
  return null
}

export function formatVoiceDuration(sec: number): string {
  const s = Math.max(1, Math.round(sec))
  const m = Math.floor(s / 60)
  const r = s % 60
  if (m <= 0) return `${r}"`
  return `${m}'${String(r).padStart(2, '0')}"`
}

export function formatFileSize(n?: number): string {
  if (n == null || n < 0) return ''
  if (n < 1024) return `${n} B`
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`
  return `${(n / (1024 * 1024)).toFixed(1)} MB`
}

export type ForwardPayload = {
  fromTitle: string
  fromType: string
  items: Array<{
    senderName: string
    type: string
    body?: string
    thumbUrl?: string
    url?: string
    name?: string
    size?: number
    duration?: number
    createdAt: string
  }>
}

export function parseForwardBody(body: string): ForwardPayload | null {
  try {
    const o = JSON.parse(body) as Partial<ForwardPayload>
    if (o && typeof o.fromTitle === 'string' && Array.isArray(o.items)) {
      return {
        fromTitle: o.fromTitle,
        fromType: o.fromType || '',
        items: o.items,
      }
    }
  } catch {
    /* ignore */
  }
  return null
}

/** Plain text suitable for clipboard from a chat message. */
export function messageCopyText(m: {
  type: string
  body: string
  recalled?: boolean
}): string {
  if (m.recalled) return ''
  if (m.type === 'text') return m.body || ''
  if (m.type === 'file') {
    const f = parseFileBody(m.body)
    return f?.name || f?.url || ''
  }
  if (m.type === 'image') {
    const img = parseImageBody(m.body)
    return img?.url || img?.thumbUrl || ''
  }
  if (m.type === 'voice') {
    const v = parseVoiceBody(m.body)
    return v ? `[语音] ${formatVoiceDuration(v.duration)}` : '[语音]'
  }
  if (m.type === 'forward') {
    const fwd = parseForwardBody(m.body)
    if (!fwd) return ''
    const lines = fwd.items.map((it) => {
      const content =
        it.type === 'image'
          ? '[图片]'
          : it.type === 'file'
            ? `[文件]${it.name || ''}`
            : it.type === 'voice'
              ? `[语音]${it.duration != null ? formatVoiceDuration(it.duration) : ''}`
              : it.body || ''
      return `${it.senderName}：${content}`
    })
    return `${fwd.fromTitle}的聊天记录\n${lines.join('\n')}`
  }
  return ''
}


