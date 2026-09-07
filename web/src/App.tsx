import { useEffect, useState } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { ConfigProvider, Loading } from 'tdesign-react'
import zhConfig from 'tdesign-react/es/locale/zh_CN'
import { api, getSessionSlot, getToken, setToken, type User } from '@/api'
import { AdminPage } from './pages/AdminPage'
import { AuthPage } from './pages/AuthPage'
import { ChatPage } from './pages/ChatPage'
import { VerifyPage } from './pages/VerifyPage'
import './App.css'

function SlotBadge() {
  const slot = getSessionSlot()
  if (!slot) return null
  return <div className="im-slot-badge">测试槽：{slot}</div>
}

function Home() {
  const [user, setUser] = useState<User | null>(null)
  const [booting, setBooting] = useState(true)

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
        <AuthPage onAuthed={setUser} />
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
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </ConfigProvider>
  )
}
