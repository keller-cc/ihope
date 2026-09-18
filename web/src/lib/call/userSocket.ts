import { getToken } from '@/api'

type Handler = (data: Record<string, unknown>) => void
type ConnHandler = (connected: boolean) => void

const PING_MS = 25000
const RECONNECT_MIN_MS = 1000
const RECONNECT_MAX_MS = 15000

/**
 * Session-scoped user WebSocket.
 * Keeps presence / inbox / call signaling for the whole login; disconnect only on logout.
 */
class UserSocket {
  private ws: WebSocket | null = null
  private handlers = new Set<Handler>()
  private connHandlers = new Set<ConnHandler>()
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private intentionalClose = false
  private pingTimer: ReturnType<typeof setInterval> | null = null
  private connected = false
  private attempt = 0
  private lifecycleBound = false

  get isConnected() {
    return this.connected && this.ws?.readyState === WebSocket.OPEN
  }

  private setConnected(value: boolean) {
    if (this.connected === value) return
    this.connected = value
    for (const h of this.connHandlers) {
      try {
        h(value)
      } catch {
        /* ignore */
      }
    }
  }

  /** Bind once: keep the socket alive across tab focus / network flips. */
  private ensureLifecycle() {
    if (this.lifecycleBound || typeof window === 'undefined') return
    this.lifecycleBound = true
    window.addEventListener('online', this.onOnline)
    document.addEventListener('visibilitychange', this.onVisibility)
  }

  private onOnline = () => {
    if (!this.intentionalClose) this.connect()
  }

  private onVisibility = () => {
    if (document.visibilityState !== 'visible' || this.intentionalClose) return
    if (!this.ws || this.ws.readyState === WebSocket.CLOSED) {
      this.connect()
    }
  }

  connect() {
    const token = getToken()
    if (!token) return
    this.ensureLifecycle()
    this.intentionalClose = false
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return
    }
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(
      `${proto}://${location.host}/ws/user?token=${encodeURIComponent(token)}`,
    )
    this.ws = ws
    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(String(ev.data)) as Record<string, unknown>
        for (const h of this.handlers) {
          try {
            h(data)
          } catch {
            /* one bad handler must not block the rest */
          }
        }
      } catch {
        /* ignore */
      }
    }
    ws.onopen = () => {
      this.attempt = 0
      this.setConnected(true)
      if (this.pingTimer) clearInterval(this.pingTimer)
      this.pingTimer = setInterval(() => {
        this.send({ type: 'ping' })
      }, PING_MS)
    }
    ws.onclose = () => {
      this.setConnected(false)
      if (this.pingTimer) {
        clearInterval(this.pingTimer)
        this.pingTimer = null
      }
      if (this.ws === ws) this.ws = null
      if (this.intentionalClose) return
      const delay = Math.min(
        RECONNECT_MAX_MS,
        RECONNECT_MIN_MS * 2 ** Math.min(this.attempt++, 4),
      )
      if (this.reconnectTimer) clearTimeout(this.reconnectTimer)
      this.reconnectTimer = setTimeout(() => this.connect(), delay)
    }
  }

  disconnect() {
    this.intentionalClose = true
    this.attempt = 0
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    if (this.pingTimer) {
      clearInterval(this.pingTimer)
      this.pingTimer = null
    }
    const ws = this.ws
    this.ws = null
    if (ws && ws.readyState !== WebSocket.CLOSED) {
      ws.close()
    }
    this.setConnected(false)
  }

  on(handler: Handler) {
    this.handlers.add(handler)
    return () => {
      this.handlers.delete(handler)
    }
  }

  onConnection(handler: ConnHandler) {
    this.connHandlers.add(handler)
    if (this.ws?.readyState === WebSocket.OPEN) {
      handler(true)
    } else if (!this.ws || this.ws.readyState === WebSocket.CLOSED) {
      handler(false)
    }
    return () => {
      this.connHandlers.delete(handler)
    }
  }

  send(payload: Record<string, unknown>) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(payload))
    }
  }
}

// Survive Vite HMR — a fresh module singleton would open a 2nd /ws/user and fight the old one.
type UserSocketGlobal = typeof globalThis & { __ihopeUserSocket?: UserSocket }
const g = globalThis as UserSocketGlobal
export const userSocket = g.__ihopeUserSocket ?? new UserSocket()
g.__ihopeUserSocket = userSocket
