import { useEffect, useState } from 'react'
import { BrowserRouter, Navigate, Route, Routes, useNavigate, useSearchParams } from 'react-router-dom'
import { ConfigProvider, Loading, MessagePlugin } from 'tdesign-react'
import zhConfig from 'tdesign-react/es/locale/zh_CN'
import { api, AUTH_UNAUTHORIZED_EVENT, getSessionSlot, getToken, setToken, type User } from '@/api'
import { AdminPage } from './pages/AdminPage'
import { AuthPage } from './pages/AuthPage'
import { ChatPage } from './pages/ChatPage'
import { DinoGamePage } from './games/dino/DinoGamePage'
import { GameHubPage } from './games/GameHubPage'
import { ManilaLobbyPage } from './games/manila/ManilaLobbyPage'
import { ManilaRoomPage } from './games/manila/ManilaRoomPage'
import { ManilaRulesPage } from './games/manila/ManilaRulesPage'
import { ManilaBoardPreviewPage } from './games/manila/ManilaBoardPreviewPage'
import { VerifyPage } from './pages/VerifyPage'
import { ResetPasswordPage } from './pages/ResetPasswordPage'
import './App.css'

/** Only allow in-app relative paths (games return, etc.). */
function safeNextPath(raw: string | null): string | null {
  if (!raw) return null
  if (!raw.startsWith('/') || raw.startsWith('//')) return null
  if (raw.startsWith('/game')) return raw
  return null
}

/** Single toast for session expiry; pages listen separately to flip "logged in" UI. */
function AuthSessionWatcher() {
  useEffect(() => {
    const onUnauth = (ev: Event) => {
      const toast = (ev as CustomEvent<{ toast?: boolean }>).detail?.toast
      if (toast) MessagePlugin.warning('登录已失效，请重新登录')
    }
    window.addEventListener(AUTH_UNAUTHORIZED_EVENT, onUnauth)
    return () => window.removeEventListener(AUTH_UNAUTHORIZED_EVENT, onUnauth)
  }, [])
  return null
}

function SlotBadge() {
  const slot = getSessionSlot()
  if (!slot) return null
  return <div className="im-slot-badge">测试槽：{slot}</div>
}

function Home() {
  const [user, setUser] = useState<User | null>(null)
  const [booting, setBooting] = useState(true)
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const nextPath = safeNextPath(searchParams.get('next'))

  useEffect(() => {
    const token = getToken()
    if (!token) {
      setBooting(false)
      return
    }
    void api
      .me()
      .then(setUser)
      .catch(() => {
        setToken(null)
        setUser(null)
      })
      .finally(() => setBooting(false))
  }, [])

  useEffect(() => {
    const onUnauth = () => setUser(null)
    window.addEventListener(AUTH_UNAUTHORIZED_EVENT, onUnauth)
    return () => window.removeEventListener(AUTH_UNAUTHORIZED_EVENT, onUnauth)
  }, [])

  useEffect(() => {
    if (!booting && user && nextPath) {
      navigate(nextPath, { replace: true })
    }
  }, [booting, user, nextPath, navigate])

  if (booting) {
    return (
      <div className="im-boot">
        <Loading text="加载中…" />
      </div>
    )
  }

  return (
    <>
      <SlotBadge />
      {user ? (
        <ChatPage
          user={user}
          onUserChange={setUser}
          onLogout={() => setUser(null)}
        />
      ) : (
        <AuthPage
          onAuthed={(u) => {
            setUser(u)
            if (nextPath) navigate(nextPath, { replace: true })
          }}
        />
      )}
    </>
  )
}

export default function App() {
  return (
    <ConfigProvider globalConfig={zhConfig}>
      <BrowserRouter>
        <AuthSessionWatcher />
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/verify" element={<VerifyPage />} />
          <Route path="/reset-password" element={<ResetPasswordPage />} />
          <Route path="/admin" element={<AdminPage />} />
          <Route path="/game" element={<GameHubPage />} />
          <Route path="/game/dinodasher" element={<DinoGamePage />} />
          <Route path="/game/dino" element={<Navigate to="/game/dinodasher" replace />} />
          <Route path="/game/manila" element={<ManilaLobbyPage />} />
          <Route path="/game/manila/preview" element={<ManilaBoardPreviewPage />} />
          <Route path="/game/manila/rules" element={<ManilaRulesPage />} />
          <Route path="/game/manila/r/:code" element={<ManilaRoomPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </ConfigProvider>
  )
}
