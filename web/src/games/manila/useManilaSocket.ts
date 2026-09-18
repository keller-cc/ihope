import { useCallback, useEffect, useRef, useState } from 'react'
import { getToken, type ManilaRoom } from '@/api'

type MsgHandler = (msg: Record<string, unknown>) => void

export function useManilaSocket(roomId: string | undefined, onState: (room: ManilaRoom) => void) {
  const [connected, setConnected] = useState(false)
  const [lastError, setLastError] = useState<string | null>(null)
  const wsRef = useRef<WebSocket | null>(null)
  const onStateRef = useRef(onState)
  const intentionalClose = useRef(false)
  const reconnectTimer = useRef<number | null>(null)
  const attemptRef = useRef(0)
  onStateRef.current = onState

  const clearReconnect = () => {
    if (reconnectTimer.current != null) {
      window.clearTimeout(reconnectTimer.current)
      reconnectTimer.current = null
    }
  }

  const send = useCallback((payload: Record<string, unknown>) => {
    const ws = wsRef.current
    if (!ws || ws.readyState !== WebSocket.OPEN) return
    ws.send(JSON.stringify(payload))
  }, [])

  useEffect(() => {
    if (!roomId) return
    const token = getToken()
    if (!token) return
    intentionalClose.current = false
    attemptRef.current = 0

    const connect = () => {
      const proto = location.protocol === 'https:' ? 'wss' : 'ws'
      const ws = new WebSocket(
        `${proto}://${location.host}/ws/manila/${encodeURIComponent(roomId)}?token=${encodeURIComponent(token)}`,
      )
      wsRef.current = ws
      ws.onopen = () => {
        setConnected(true)
        setLastError(null)
        attemptRef.current = 0
      }
      ws.onclose = () => {
        setConnected(false)
        wsRef.current = null
        if (intentionalClose.current) return
        const attempt = attemptRef.current++
        const delay = Math.min(10000, 1000 * 2 ** Math.min(attempt, 3))
        setLastError('连接断开，正在重连…')
        clearReconnect()
        reconnectTimer.current = window.setTimeout(connect, delay)
      }
      ws.onerror = () => setLastError('连接失败')
      ws.onmessage = (ev) => {
        try {
          const msg = JSON.parse(String(ev.data)) as Record<string, unknown>
          if (msg.type === 'state' && msg.room) {
            onStateRef.current(msg.room as ManilaRoom)
            setLastError(null)
          } else if (msg.type === 'error') {
            setLastError(String(msg.message || '操作失败'))
          }
        } catch {
          /* ignore */
        }
      }
    }

    connect()
    const ping = window.setInterval(() => {
      const ws = wsRef.current
      if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping' }))
    }, 25000)

    return () => {
      intentionalClose.current = true
      clearReconnect()
      window.clearInterval(ping)
      wsRef.current?.close()
      wsRef.current = null
    }
  }, [roomId])

  return { connected, lastError, send, setLastError }
}

export type { MsgHandler }
