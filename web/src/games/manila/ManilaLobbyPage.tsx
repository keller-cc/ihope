import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { MessagePlugin } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  getToken,
  type ManilaMatchResult,
  type ManilaRoom,
} from '@/api'
import '@/games/game-shell.css'
import './manila.css'

const LOGIN_HREF = `/?next=${encodeURIComponent('/game/manila')}`

function statusLabel(status: string) {
  if (status === 'playing') return '游戏中'
  if (status === 'open') return '等待中'
  return status
}

function formatHistoryTime(iso: string) {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  const p = (n: number) => String(n).padStart(2, '0')
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
}

export function ManilaLobbyPage() {
  const navigate = useNavigate()
  const [loggedIn, setLoggedIn] = useState(() => !!getToken())
  const [rooms, setRooms] = useState<ManilaRoom[]>([])
  const [history, setHistory] = useState<ManilaMatchResult[]>([])
  const [code, setCode] = useState('')
  const [maxPlayers, setMaxPlayers] = useState(4)
  const [isPrivate, setIsPrivate] = useState(false)
  const [busy, setBusy] = useState(false)

  const refresh = async () => {
    if (!getToken()) return
    try {
      const [roomRes, histRes] = await Promise.all([
        api.manilaListRooms(),
        api.manilaMyHistory(30),
      ])
      setRooms(roomRes.rooms || [])
      setHistory(histRes.results || [])
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '无法加载大厅数据'))
    }
  }

  useEffect(() => {
    setLoggedIn(!!getToken())
    void refresh()
    const t = window.setInterval(() => void refresh(), 8000)
    return () => window.clearInterval(t)
  }, [])

  const create = async () => {
    if (!getToken()) {
      navigate(LOGIN_HREF)
      return
    }
    setBusy(true)
    try {
      const room = await api.manilaCreateRoom({ maxPlayers, private: isPrivate })
      navigate(`/game/manila/r/${room.code}`)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '创建失败'))
    } finally {
      setBusy(false)
    }
  }

  const join = async (c: string) => {
    if (!getToken()) {
      navigate(LOGIN_HREF)
      return
    }
    const trimmed = c.trim().toLowerCase()
    if (!trimmed) return
    setBusy(true)
    try {
      const room = await api.manilaJoinRoom(trimmed)
      navigate(`/game/manila/r/${room.code}`)
    } catch (e) {
      MessagePlugin.error(
        apiErrorMessage(e, '加入失败（进行中的对局仅原成员可重连）'),
      )
    } finally {
      setBusy(false)
    }
  }

  const publicRooms = [...rooms].sort((a, b) => {
    if (a.status === b.status) return a.code.localeCompare(b.code)
    if (a.status === 'open') return -1
    if (b.status === 'open') return 1
    return 0
  })

  return (
    <div className="manila-shell">
      <div className="manila-sky" aria-hidden />
      <div className="manila-waves" aria-hidden />
      <header className="manila-head">
        <div>
          <p className="manila-eyebrow">港口投机</p>
          <h1>马尼拉</h1>
        </div>
        <div className="manila-head-actions">
          <Link className="manila-link manila-link--accent" to="/game/manila/preview">
            盘面效果图
          </Link>
          <Link className="manila-link" to="/game/manila/rules">
            规则书
          </Link>
          {!loggedIn && (
            <Link className="manila-link manila-link--accent" to={LOGIN_HREF}>
              登录
            </Link>
          )}
          <Link className="manila-link" to="/game">
            返回
          </Link>
        </div>
      </header>

      <main className="manila-lobby">
        <section className="manila-panel manila-panel--create">
          <h2>创建房间</h2>
          <p className="manila-muted">3–5 人，房主开局后进入完整规则对局。</p>
          <label className="manila-field">
            人数上限
            <select
              value={maxPlayers}
              onChange={(e) => setMaxPlayers(Number(e.target.value))}
            >
              {[3, 4, 5].map((n) => (
                <option key={n} value={n}>
                  {n} 人
                </option>
              ))}
            </select>
          </label>
          <label className="manila-check">
            <input
              type="checkbox"
              checked={isPrivate}
              onChange={(e) => setIsPrivate(e.target.checked)}
            />
            私密房（不出现在公开列表）
          </label>
          <button type="button" className="manila-btn" disabled={busy} onClick={() => void create()}>
            创建并进入
          </button>
        </section>

        <section className="manila-panel">
          <h2>加入房间</h2>
          <div className="manila-join-row">
            <input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder="房间码"
              maxLength={8}
            />
            <button
              type="button"
              className="manila-btn manila-btn--ghost"
              disabled={busy}
              onClick={() => void join(code)}
            >
              加入
            </button>
          </div>
        </section>

        <section className="manila-panel manila-panel--list">
          <div className="manila-list-head">
            <h2>公开房间</h2>
            <button type="button" className="manila-text-btn" onClick={() => void refresh()}>
              刷新
            </button>
          </div>
          {!loggedIn ? (
            <p className="manila-muted">登录后可查看并加入。</p>
          ) : publicRooms.length === 0 ? (
            <p className="manila-muted">暂无公开房间，创建一个吧。</p>
          ) : (
            <ul className="manila-room-list">
              {publicRooms.map((r) => (
                <li key={r.id}>
                  <button type="button" onClick={() => void join(r.code)}>
                    <span className="manila-room-code">{r.code}</span>
                    <span>
                      {r.members?.length || 0}/{r.maxPlayers} 人 · {statusLabel(r.status)}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="manila-panel manila-panel--list">
          <div className="manila-list-head">
            <h2>我的战绩</h2>
            <button type="button" className="manila-text-btn" onClick={() => void refresh()}>
              刷新
            </button>
          </div>
          {!loggedIn ? (
            <p className="manila-muted">登录后可查看历史对局。</p>
          ) : history.length === 0 ? (
            <p className="manila-muted">还没有已结束的对局记录。</p>
          ) : (
            <ul className="manila-history-list">
              {history.map((h) => (
                <li key={h.id}>
                  <div className="manila-history-main">
                    <span className="manila-room-code">{h.roomCode || '—'}</span>
                    <span className="manila-history-meta">
                      {formatHistoryTime(h.finishedAt)}
                      {h.myRank ? ` · 第 ${h.myRank} 名` : ''}
                      {typeof h.myFortune === 'number' ? ` · 财富 ${h.myFortune}` : ''}
                    </span>
                  </div>
                  <p className="manila-history-rank">
                    {(h.players || [])
                      .map((p) => `#${p.rank} ${p.username}(${p.fortune})`)
                      .join(' · ')}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </section>
      </main>
    </div>
  )
}
