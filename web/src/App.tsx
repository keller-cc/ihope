import { useEffect, useState } from 'react'
import { BrowserRouter, Navigate, Route, Routes, useNavigate, useSearchParams } from 'react-router-dom'
import { ConfigProvider, Loading } from 'tdesign-react'
import zhConfig from 'tdesign-react/es/locale/zh_CN'
import { api, getSessionSlot, getToken, setToken, type User } from '@/api'
import { AdminPage } from './pages/AdminPage'
import { AuthPage } from './pages/AuthPage'
import { ChatPage } from './pages/ChatPage'
import { DinoGamePage } from './pages/DinoGamePage'
import { GameHubPage } from './pages/GameHubPage'
import { VerifyPage } from './pages/VerifyPage'
import './App.css'

/** Only allow in-app relative paths (games return, etc.). */
function safeNextPath(raw: string | null): string | null {
  if (!raw) return null
  if (!raw.startsWith('/') || raw.startsWith('//')) return null
  if (raw.startsWith('/game')) return raw
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
      .catch(() => setToken(null))
      .finally(() => setBooting(false))
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
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/verify" element={<VerifyPage />} />
          <Route path="/admin" element={<AdminPage />} />
          <Route path="/game" element={<GameHubPage />} />
          <Route path="/game/dinodasher" element={<DinoGamePage />} />
          <Route path="/game/dino" element={<Navigate to="/game/dinodasher" replace />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </ConfigProvider>
  )
}
