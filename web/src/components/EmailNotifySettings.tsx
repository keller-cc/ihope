import { useEffect, useState } from 'react'
import { Checkbox, InputNumber, MessagePlugin, Radio, Switch } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  type Conversation,
  type EmailNotifyMode,
  type EmailNotifyPrefs,
  type EmailNotifyScope,
} from '@/api'
import { conversationTitle } from '@/lib/chatFormat'

type Props = {
  compact?: boolean
  conversations?: Conversation[]
}

const MODE_OPTIONS: { value: EmailNotifyMode; label: string; hint: string }[] = [
  { value: 'first_daily', label: '每天第一条', hint: '每天最多提醒一次' },
  { value: 'every', label: '每条消息', hint: '按最短间隔发送' },
  { value: 'batch', label: '累计条数', hint: '达到设定条数后汇总提醒' },
]

const SCOPE_OPTIONS: { value: EmailNotifyScope; label: string }[] = [
  { value: 'all', label: '全部会话' },
  { value: 'dm_only', label: '仅私聊' },
  { value: 'group_only', label: '仅群聊' },
  { value: 'include', label: '指定会话' },
  { value: 'exclude', label: '排除会话' },
]

export function EmailNotifySettings({ compact, conversations: convProp }: Props) {
  const [prefs, setPrefs] = useState<EmailNotifyPrefs | null>(null)
  const [busy, setBusy] = useState(false)
  const [sessions, setSessions] = useState<Conversation[]>(convProp || [])

  useEffect(() => {
    void api
      .emailNotifyGet()
      .then(setPrefs)
      .catch(() => setPrefs(null))
  }, [])

  useEffect(() => {
    if (convProp) {
      setSessions(convProp)
      return
    }
    void api
      .listConversations()
      .then((r) => setSessions(r.conversations || []))
      .catch(() => setSessions([]))
  }, [convProp])

  const patch = async (body: Parameters<typeof api.emailNotifyPatch>[0]) => {
    setBusy(true)
    try {
      const next = await api.emailNotifyPatch(body)
      setPrefs(next)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '保存失败'))
    } finally {
      setBusy(false)
    }
  }

  if (!prefs) {
    return <p className="im-muted">加载邮件提醒设置…</p>
  }

  const paused = prefs.effective === 'paused_by_qq'
  const disabledLooks = !prefs.enabled || prefs.mode === 'off'

  return (
    <div className={compact ? 'im-email-notify im-email-notify--compact' : 'im-email-notify'}>
      <div className="im-switch-row" style={{ marginBottom: 8 }}>
        <span>邮件离线提醒</span>
        <Switch
          value={prefs.enabled && prefs.mode !== 'off'}
          disabled={busy}
          onChange={(v) => void patch({ enabled: Boolean(v), mode: v ? (prefs.mode === 'off' ? 'first_daily' : prefs.mode) : 'off' })}
        />
      </div>

      {!prefs.emailVerified && (
        <p className="im-muted">请先完成邮箱验证。</p>
      )}
      {paused && (
        <p className="im-muted">已开启 QQ 离线提醒，邮件提醒暂不发送。</p>
      )}
      {!paused && !disabledLooks && prefs.effective === 'active' && (
        <p className="im-muted">仅在离线时发送；免打扰会话不会提醒。</p>
      )}

      <div style={{ marginTop: 12, opacity: disabledLooks ? 0.55 : 1, pointerEvents: disabledLooks ? 'none' : undefined }}>
        <div className="im-muted" style={{ marginBottom: 6 }}>频率</div>
        <Radio.Group
          value={prefs.mode === 'off' ? 'first_daily' : prefs.mode}
          onChange={(v) => void patch({ mode: v as EmailNotifyMode, enabled: true })}
        >
          {MODE_OPTIONS.map((o) => (
            <Radio key={o.value} value={o.value} allowUncheck={false}>
              {o.label}
            </Radio>
          ))}
        </Radio.Group>
        <p className="im-muted" style={{ marginTop: 4, fontSize: 12 }}>
          {MODE_OPTIONS.find((o) => o.value === (prefs.mode === 'off' ? 'first_daily' : prefs.mode))?.hint}
        </p>

        {prefs.mode === 'every' && (
          <div className="im-switch-row" style={{ marginTop: 8 }}>
            <span>最短间隔（秒）</span>
            <InputNumber
              min={60}
              max={3600}
              step={60}
              value={prefs.minIntervalSec}
              disabled={busy}
              onChange={(v) => {
                const n = typeof v === 'number' ? v : prefs.minIntervalSec
                void patch({ minIntervalSec: n })
              }}
            />
          </div>
        )}
        {prefs.mode === 'batch' && (
          <div className="im-switch-row" style={{ marginTop: 8 }}>
            <span>累计条数</span>
            <InputNumber
              min={2}
              max={50}
              value={prefs.batchSize}
              disabled={busy}
              onChange={(v) => {
                const n = typeof v === 'number' ? v : prefs.batchSize
                void patch({ batchSize: n })
              }}
            />
          </div>
        )}

        <div className="im-muted" style={{ margin: '14px 0 6px' }}>会话范围</div>
        <Radio.Group
          value={prefs.scope}
          onChange={(v) => void patch({ scope: v as EmailNotifyScope })}
        >
          {SCOPE_OPTIONS.map((o) => (
            <Radio key={o.value} value={o.value} allowUncheck={false}>
              {o.label}
            </Radio>
          ))}
        </Radio.Group>

        {(prefs.scope === 'include' || prefs.scope === 'exclude') && (
          <div style={{ marginTop: 10, maxHeight: 180, overflow: 'auto' }}>
            {sessions.length === 0 ? (
              <p className="im-muted">暂无会话</p>
            ) : (
              sessions.map((c) => {
                const checked = prefs.conversationIds.includes(c.id)
                return (
                  <label
                    key={c.id}
                    style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0' }}
                  >
                    <Checkbox
                      checked={checked}
                      disabled={busy}
                      onChange={(v) => {
                        const on = Boolean(v)
                        const next = on
                          ? [...new Set([...prefs.conversationIds, c.id])]
                          : prefs.conversationIds.filter((id) => id !== c.id)
                        void patch({ conversationIds: next })
                      }}
                    />
                    <span style={{ fontSize: 13 }}>{conversationTitle(c)}</span>
                  </label>
                )
              })
            )}
          </div>
        )}
      </div>
    </div>
  )
}
