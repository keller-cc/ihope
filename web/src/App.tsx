import { lazy, Suspense, useEffect, useState, type ReactNode } from 'react'
import { BrowserRouter, Navigate, Route, Routes, useNavigate, useSearchParams } from 'react-router-dom'
import { ConfigProvider, Loading, MessagePlugin } from 'tdesign-react'
import zhConfig from 'tdesign-react/es/locale/zh_CN'
import { api, AUTH_UNAUTHORIZED_EVENT, getSessionSlot, getToken, setToken, type User } from '@/api'
import { AuthPage } from './pages/AuthPage'
import { ChatPage } from './pages/ChatPage'
import { VerifyPage } from './pages/VerifyPage'
import { ResetPasswordPage } from './pages/ResetPasswordPage'
import './App.css'

const AdminPage = lazy(() =>
  import('./pages/AdminPage').then((m) => ({ default: m.AdminPage })),
)
const GameHubPage = lazy(() =>
  import('./games/GameHubPage').then((m) => ({ default: m.GameHubPage })),
)
const DinoGamePage = lazy(() =>
  import('./games/dino/DinoGamePage').then((m) => ({ default: m.DinoGamePage })),
)
const ManilaLobbyPage = lazy(() =>
  import('./games/manila/ManilaLobbyPage').then((m) => ({ default: m.ManilaLobbyPage })),
)
const ManilaRoomPage = lazy(() =>
  import('./games/manila/ManilaRoomPage').then((m) => ({ default: m.ManilaRoomPage })),
)
const ManilaRulesPage = lazy(() =>
  import('./games/manila/ManilaRulesPage').then((m) => ({ default: m.ManilaRulesPage })),
)
const ManilaBoardPreviewPage = lazy(() =>
  import('./games/manila/ManilaBoardPreviewPage').then((m) => ({
    default: m.ManilaBoardPreviewPage,
  })),
)

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

function RouteFallback() {
  return (
    <div className="im-boot">
      <Loading text="加载中…" />
    </div>
  )
}

function LazyRoute({ children }: { children: ReactNode }) {
  return <Suspense fallback={<RouteFallback />}>{children}</Suspense>
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
    return <RouteFallback />
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
          <Route
            path="/admin"
            element={
              <LazyRoute>
                <AdminPage />
              </LazyRoute>
            }
          />
          <Route
            path="/game"
            element={
              <LazyRoute>
                <GameHubPage />
              </LazyRoute>
            }
          />
          <Route
            path="/game/dinodasher"
            element={
              <LazyRoute>
                <DinoGamePage />
              </LazyRoute>
            }
          />
          <Route path="/game/dino" element={<Navigate to="/game/dinodasher" replace />} />
          <Route
            path="/game/manila"
            element={
              <LazyRoute>
                <ManilaLobbyPage />
              </LazyRoute>
            }
          />
          <Route
            path="/game/manila/preview"
            element={
              <LazyRoute>
                <ManilaBoardPreviewPage />
              </LazyRoute>
            }
          />
          <Route
            path="/game/manila/rules"
            element={
              <LazyRoute>
                <ManilaRulesPage />
              </LazyRoute>
            }
          />
          <Route
            path="/game/manila/r/:code"
            element={
              <LazyRoute>
                <ManilaRoomPage />
              </LazyRoute>
            }
          />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </ConfigProvider>
  )
}
