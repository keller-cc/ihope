import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Button, Input, MessagePlugin } from 'tdesign-react'
import { api, apiErrorMessage } from '@/api'

export function ResetPasswordPage() {
  const [params] = useSearchParams()
  const token = params.get('token') || ''
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)

  const onSubmit = async () => {
    if (!token) {
      MessagePlugin.error('链接无效，请重新申请找回密码')
      return
    }
    if (password.length < 6) {
      MessagePlugin.warning('密码至少 6 位')
      return
    }
    if (password !== confirm) {
      MessagePlugin.warning('两次密码不一致')
      return
    }
    setBusy(true)
    try {
      await api.resetPassword(token, password)
      setDone(true)
      MessagePlugin.success('密码已更新')
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '重置失败'))
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

        <div className="im-auth__panel">
          {done ? (
            <>
              <h2 className="im-auth__heading">密码已重置</h2>
              <p className="im-auth__lead">请使用新密码登录。</p>
              <Link className="im-auth__link-btn" to="/">
                <Button theme="primary" size="large" block>
                  去登录
                </Button>
              </Link>
            </>
          ) : (
            <>
              <h2 className="im-auth__heading">设置新密码</h2>
              <p className="im-auth__lead">请输入新密码（至少 6 位）。</p>
              <div className="im-auth-fields">
                <Input
                  size="large"
                  type="password"
                  placeholder="新密码"
                  clearable
                  value={password}
                  onChange={(v) => setPassword(String(v))}
                />
                <Input
                  size="large"
                  type="password"
                  placeholder="确认新密码"
                  clearable
                  value={confirm}
                  onChange={(v) => setConfirm(String(v))}
                  onEnter={() => void onSubmit()}
                />
                <Button
                  size="large"
                  theme="primary"
                  block
                  loading={busy}
                  onClick={() => void onSubmit()}
                >
                  确认重置
                </Button>
                <Link className="im-auth__link-btn" to="/">
                  <Button size="large" variant="outline" block>
                    返回登录
                  </Button>
                </Link>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
