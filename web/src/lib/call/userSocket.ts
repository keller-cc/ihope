import { getToken } from '@/api'

type Handler = (data: Record<string, unknown>) => void

/** 用户级 WebSocket：来电振铃与 WebRTC 信令 */
class UserSocket {
  private ws: WebSocket | null = null
  private handlers = new Set<Handler>()
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private intentionalClose = false
  private pingTimer: ReturnType<typeof setInterval> | null = null

  connect() {
    const token = getToken()
    if (!token) return
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return
    }
    this.intentionalClose = false
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(
      `${proto}://${location.host}/ws/user?token=${encodeURIComponent(token)}`,
    )
    this.ws = ws
    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(String(ev.data)) as Record<string, unknown>
        for (const h of this.handlers) h(data)
      } catch {
        /* ignore */
      }
    }
    ws.onopen = () => {
      this.pingTimer = setInterval(() => {
        this.send({ type: 'ping' })
      }, 25000)
    }
    ws.onclose = () => {
      if (this.pingTimer) {
        clearInterval(this.pingTimer)
        this.pingTimer = null
      }
      this.ws = null
      if (!this.intentionalClose) {
        this.reconnectTimer = setTimeout(() => this.connect(), 2000)
      }
    }
  }

  disconnect() {
    this.intentionalClose = true
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    if (this.pingTimer) {
      clearInterval(this.pingTimer)
      this.pingTimer = null
    }
    this.ws?.close()
    this.ws = null
  }

  on(handler: Handler) {
    this.handlers.add(handler)
    return () => {
      this.handlers.delete(handler)
    }
  }

  send(payload: Record<string, unknown>) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload))
    }
  }
}

export const userSocket = new UserSocket()
