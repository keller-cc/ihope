import { useEffect, useState } from 'react'
import { useSearchParams, Link } from 'react-router-dom'
import { Button, Loading, MessagePlugin } from 'tdesign-react'
import { api } from '../api'

export function VerifyPage() {
  const [params] = useSearchParams()
  const token = params.get('token') || ''
  const [status, setStatus] = useState<'loading' | 'ok' | 'fail'>('loading')

  useEffect(() => {
    if (!token) {
      setStatus('fail')
      return
    }
    void api
      .verifyEmail(token)
      .then(() => setStatus('ok'))
      .catch(() => {
        setStatus('fail')
        MessagePlugin.error('验证失败，链接可能已过期')
      })
  }, [token])

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
          {status === 'loading' && (
            <div className="im-auth__loading">
              <Loading text="正在验证邮箱…" />
            </div>
          )}
          {status === 'ok' && (
            <>
              <h2 className="im-auth__heading">邮箱已验证</h2>
              <p className="im-auth__lead">现在可以登录使用 IHope。</p>
              <Link className="im-auth__link-btn" to="/">
                <Button theme="primary" size="large" block>
                  去登录
                </Button>
              </Link>
            </>
          )}
          {status === 'fail' && (
            <>
              <h2 className="im-auth__heading">验证失败</h2>
              <p className="im-auth__lead">链接无效或已过期，请重新发送验证邮件。</p>
              <Link className="im-auth__link-btn" to="/">
                <Button theme="primary" size="large" block>
                  返回
                </Button>
              </Link>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
