import { useState } from 'react'
import { Button, Input, MessagePlugin } from 'tdesign-react'
import { api, apiErrorMessage, setToken, type User } from '../api'

type Props = {
  onAuthed: (user: User) => void
}

type Mode = 'login' | 'register' | 'pending'

export function AuthPage({ onAuthed }: Props) {
  const [mode, setMode] = useState<Mode>('login')
  const [busy, setBusy] = useState(false)
  const [login, setLogin] = useState('')
  const [password, setPassword] = useState('')
  const [email, setEmail] = useState('')
  const [username, setUsername] = useState('')
  const [regPassword, setRegPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [fellowshipCode, setFellowshipCode] = useState('')
  const [pendingEmail, setPendingEmail] = useState('')
  const [devToken, setDevToken] = useState('')

  const onLogin = async () => {
    if (!login.trim() || !password) {
      MessagePlugin.warning('请填写账号和密码')
      return
    }
    setBusy(true)
    try {
      const res = await api.login(login.trim(), password)
      setToken(res.token)
      onAuthed(res.user)
      MessagePlugin.success('欢迎回来')
    } catch (e) {
      const code = e instanceof Error ? (e as Error & { code?: string }).code : ''
      if (code === 'email_not_verified') {
        const maybeEmail = login.includes('@') ? login.trim() : ''
        setPendingEmail(maybeEmail)
        setMode('pending')
        MessagePlugin.warning('请先完成邮箱验证')
      } else {
        MessagePlugin.error(apiErrorMessage(e, '登录失败'))
      }
    } finally {
      setBusy(false)
    }
  }

  const onRegister = async () => {
    if (!email.trim() || !username.trim()) {
      MessagePlugin.warning('请填写邮箱和用户名')
      return
    }
    if (!fellowshipCode.trim()) {
      MessagePlugin.warning('请填写团契码')
      return
    }
    if (regPassword.length < 6) {
      MessagePlugin.warning('密码至少 6 位')
      return
    }
    if (regPassword !== confirm) {
      MessagePlugin.warning('两次密码不一致')
      return
    }
    setBusy(true)
    try {
      const res = await api.register(
        email.trim(),
        username.trim(),
        regPassword,
        fellowshipCode.trim(),
      )
      setPendingEmail(email.trim())
      setDevToken(res.devVerifyToken || '')
      setMode('pending')
      MessagePlugin.success('验证邮件已发送')
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '注册失败'))
    } finally {
      setBusy(false)
    }
  }

  const onResend = async () => {
    if (!pendingEmail) {
      MessagePlugin.warning('请填写注册邮箱')
      return
    }
    setBusy(true)
    try {
      const res = await api.resendVerification(pendingEmail)
      if (res.devVerifyToken) setDevToken(res.devVerifyToken)
      MessagePlugin.success('如账号未验证，已重新发送邮件')
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '发送失败'))
    } finally {
      setBusy(false)
    }
  }

  const onDevVerify = async () => {
    if (!devToken) return
    setBusy(true)
    try {
      await api.verifyEmail(devToken)
      MessagePlugin.success('邮箱已验证，请登录')
      setMode('login')
      setLogin(pendingEmail)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '验证失败'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="im-auth">
      <div className="im-auth__card">
        <header className="im-auth__brand">
          <img
            className="im-auth__logo"
            src="/mmexport1571484547096.webp"
            alt=""
            width={72}
            height={72}
          />
          <h1 className="im-auth__title">IHope</h1>
        </header>

        {mode === 'login' && (
          <>
            <div className="im-auth__tabs">
              <button type="button" className="im-auth__tab is-active">
                登录
              </button>
              <button type="button" className="im-auth__tab" onClick={() => setMode('register')}>
                注册
              </button>
            </div>
            <div className="im-auth-fields">
              <Input
                size="large"
                placeholder="邮箱 / 用户名 / IHope 号"
                clearable
                value={login}
                onChange={(v) => setLogin(String(v))}
              />
              <Input
                size="large"
                type="password"
                placeholder="密码"
                clearable
                value={password}
                onChange={(v) => setPassword(String(v))}
                onEnter={() => void onLogin()}
              />
              <Button size="large" theme="primary" block loading={busy} onClick={() => void onLogin()}>
                登 录
              </Button>
            </div>
          </>
        )}

        {mode === 'register' && (
          <>
            <div className="im-auth__tabs">
              <button type="button" className="im-auth__tab" onClick={() => setMode('login')}>
                登录
              </button>
              <button type="button" className="im-auth__tab is-active">
                注册
              </button>
            </div>
            <div className="im-auth-fields">
              <Input
                size="large"
                placeholder="邮箱"
                clearable
                value={email}
                onChange={(v) => setEmail(String(v))}
              />
              <Input
                size="large"
                placeholder="用户名（支持中文，1–32 字）"
                clearable
                value={username}
                onChange={(v) => setUsername(String(v))}
              />
              <Input
                size="large"
                type="password"
                placeholder="密码（至少 6 位）"
                clearable
                value={regPassword}
                onChange={(v) => setRegPassword(String(v))}
              />
              <Input
                size="large"
                type="password"
                placeholder="确认密码"
                clearable
                value={confirm}
                onChange={(v) => setConfirm(String(v))}
              />
              <Input
                size="large"
                placeholder="团契码（组织码）"
                clearable
                value={fellowshipCode}
                onChange={(v) => setFellowshipCode(String(v))}
              />
              <Button
                size="large"
                theme="primary"
                block
                loading={busy}
                onClick={() => void onRegister()}
              >
                注册并发送验证邮件
              </Button>
            </div>
          </>
        )}

        {mode === 'pending' && (
          <div className="im-auth__panel">
            <h2 className="im-auth__heading">验证邮箱</h2>
            <p className="im-auth__lead">
              已向 <strong>{pendingEmail || '你的邮箱'}</strong> 发送验证链接，完成后即可登录。
            </p>
            <div className="im-auth-fields">
              {!pendingEmail && (
                <Input
                  size="large"
                  placeholder="注册邮箱"
                  value={pendingEmail}
                  onChange={(v) => setPendingEmail(String(v))}
                />
              )}
              <Button size="large" theme="primary" block loading={busy} onClick={() => void onResend()}>
                重新发送验证邮件
              </Button>
              {devToken && (
                <div className="im-dev-verify">
                  <p className="im-dev-verify__label">开发环境验证码</p>
                  <code className="im-dev-verify__token">{devToken}</code>
                  <Button
                    size="small"
                    variant="outline"
                    block
                    loading={busy}
                    onClick={() => void onDevVerify()}
                  >
                    用此码完成验证
                  </Button>
                </div>
              )}
              <Button size="large" variant="outline" block onClick={() => setMode('login')}>
                返回登录
              </Button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
