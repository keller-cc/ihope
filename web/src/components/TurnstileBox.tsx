import { Turnstile, type TurnstileInstance } from '@marsidev/react-turnstile'
import { useEffect, useRef, useState } from 'react'
import { api } from '@/api'

export type PublicTurnstile = {
  enabled: boolean
  siteKey: string
}

type Props = {
  onToken: (token: string) => void
  /** Bump to reset widget after submit / error. */
  resetKey?: number
}

let cachedConfig: PublicTurnstile | null = null
let configPromise: Promise<PublicTurnstile> | null = null

export function loadTurnstileConfig(): Promise<PublicTurnstile> {
  if (cachedConfig) return Promise.resolve(cachedConfig)
  if (!configPromise) {
    configPromise = api
      .publicConfig()
      .then((c) => {
        cachedConfig = c.turnstile
        return c.turnstile
      })
      .catch(() => {
        configPromise = null
        return { enabled: false, siteKey: '' }
      })
  }
  return configPromise
}

/** Cloudflare Turnstile widget; renders nothing when server has it disabled. */
export function TurnstileBox({ onToken, resetKey = 0 }: Props) {
  const [cfg, setCfg] = useState<PublicTurnstile | null>(cachedConfig)
  const ref = useRef<TurnstileInstance>(null)

  useEffect(() => {
    let cancelled = false
    void loadTurnstileConfig().then((c) => {
      if (!cancelled) setCfg(c)
    })
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (resetKey > 0) {
      onToken('')
      ref.current?.reset()
    }
    // intentionally only react to resetKey
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resetKey])

  if (!cfg?.enabled || !cfg.siteKey) return null

  return (
    <div className="im-turnstile">
      <Turnstile
        ref={ref}
        siteKey={cfg.siteKey}
        options={{ theme: 'light', size: 'flexible' }}
        onSuccess={(token) => onToken(token)}
        onExpire={() => onToken('')}
        onError={() => onToken('')}
      />
    </div>
  )
}
