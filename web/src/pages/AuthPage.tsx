import { useEffect, useState } from 'react'
import { Button, Input, MessagePlugin } from 'tdesign-react'
import { api, apiErrorMessage, setToken, type User } from '@/api'

type Props = {
  onAuthed: (user: User) => void
}

type Mode = 'login' | 'register' | 'pending'
type ApiErr = Error & { code?: string; email?: string; username?: string }

const RESEND_COOLDOWN_SEC = 60

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
  const [pendingUsername, setPendingUsername] = useState('')
  const [pendingPassword, setPendingPassword] = useState('')
  const [devToken, setDevToken] = useState('')
  const [resendWait, setResendWait] = useState(0)

  useEffect(() => {
    if (resendWait <= 0) return
    const id = window.setTimeout(() => setResendWait((s) => s - 1), 1000)
    return () => window.clearTimeout(id)
  }, [resendWait])

  const goLogin = () => {
    setLogin(pendingUsername || pendingEmail)
    setMode('login')
  }

  const enterPending = (addr: string, name: string, pwd: string) => {
    setPendingEmail(addr.trim())
    setPendingUsername(name.trim())
    setPendingPassword(pwd)
    setDevToken('')
    setMode('pending')
  }

  const sendOrUpdateMail = async (addr: string) => {
    const account = pendingUsername || pendingEmail || login
    if (pendingPassword && account) {
      const res = await api.changeUnverifiedEmail(account, pendingPassword, addr)
      setPendingEmail(res.email)
      if (res.devVerifyToken) setDevToken(res.devVerifyToken)
    } else {
      const res = await api.resendVerification(addr)
      if (res.status === 'already_verified') {
        goLogin()
        MessagePlugin.success('该邮箱已验证，请直接登录')
        return
      }
      if (res.status !== 'sent') {
        MessagePlugin.warning('未找到该邮箱对应的未验证账号')
        return
      }
      if (res.devVerifyToken) setDevToken(res.devVerifyToken)
    }
    setResendWait(RESEND_COOLDOWN_SEC)
    MessagePlugin.success('验证邮件已发送，请查收邮箱')
  }

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
      const err = e as ApiErr
      if (err.code === 'email_not_verified') {
        const addr = err.email?.trim() || (login.includes('@') ? login.trim() : '')
        const name = err.username?.trim() || (!login.includes('@') ? login.trim() : '')
        if (!addr) {
          MessagePlugin.warning('请先完成邮箱验证')
          return
        }
        enterPending(addr, name, password)
        try {
          await sendOrUpdateMail(addr)
        } catch (err2) {
          MessagePlugin.error(apiErrorMessage(err2, '验证邮件发送失败'))
        }
      } else {
        MessagePlugin.error(apiErrorMessage(e, '登录失败'))
      }
    } finally {
      setBusy(false)
    }
  }

  const onRegister = async () => {
    const emailVal = email.trim()
    const usernameVal = username.trim()
    if (!emailVal || !usernameVal) {
      MessagePlugin.warning('请填写邮箱和用户名')
      return
    }
    if (!emailVal.includes('@')) {
      MessagePlugin.warning('请填写有效邮箱')
      return
    }
    if (usernameVal.includes('@')) {
      MessagePlugin.warning('用户名不要填邮箱')
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
      const res = await api.register(emailVal, usernameVal, regPassword, fellowshipCode.trim())
      enterPending(emailVal, usernameVal, regPassword)
      setDevToken(res.devVerifyToken || '')
      setResendWait(RESEND_COOLDOWN_SEC)
      MessagePlugin.success('验证邮件已发送，请查收邮箱')
    } catch (e) {
      const err = e as ApiErr
      if (err.code === 'email taken') {
        enterPending(emailVal, usernameVal, regPassword)
        try {
          await sendOrUpdateMail(emailVal)
        } catch (err2) {
          MessagePlugin.error(apiErrorMessage(err2, '发送失败'))
        }
      } else {
        MessagePlugin.error(apiErrorMessage(e, '注册失败'))
      }
    } finally {
      setBusy(false)
    }
  }

  const onSendVerify = async () => {
    const addr = pendingEmail.trim()
    if (!addr.includes('@')) {
      MessagePlugin.warning('请填写有效邮箱')
      return
    }
    if (resendWait > 0) return
    setBusy(true)
    try {
      await sendOrUpdateMail(addr)
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
      goLogin()
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
            <p className="im-auth__lead">查收验证链接后即可登录。若邮箱写错可直接修改再发送。</p>
            <div className="im-auth-fields">
              <Input
                size="large"
                placeholder="邮箱"
                clearable
                value={pendingEmail}
                onChange={(v) => setPendingEmail(String(v))}
              />
              <Button
                size="large"
                theme="primary"
                block
                loading={busy}
                disabled={resendWait > 0}
                onClick={() => void onSendVerify()}
              >
                {resendWait > 0 ? `${resendWait} 秒后可再发送` : '发送验证邮件'}
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
              <Button size="large" variant="outline" block onClick={goLogin}>
                返回登录
              </Button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
