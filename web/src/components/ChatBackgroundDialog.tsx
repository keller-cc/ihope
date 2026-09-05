import { useCallback, useEffect, useRef, useState } from 'react'
import { Button, Dialog, MessagePlugin } from 'tdesign-react'
import { api, apiErrorMessage, type ChatBg, type User } from '../api'
import {
  CHINESE_COLOR_RECIPES,
  chatBgStyle,
  hexToHsv,
  hsvToHex,
  softChatHex,
} from '../lib/chatBg'

type Props = {
  visible: boolean
  value?: ChatBg | null
  onClose: () => void
  onChanged: (user: User) => void
}

export function ChatBackgroundDialog({ visible, value, onClose, onChanged }: Props) {
  const fileRef = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const current = value || { kind: 'default' as const }

  const apply = async (bg: ChatBg) => {
    setBusy(true)
    try {
      const u = await api.patchMeChatBg(bg)
      onChanged(u)
      MessagePlugin.success('聊天背景已更新')
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '设置失败'))
    } finally {
      setBusy(false)
    }
  }

  const initHex =
    current.kind === 'color' && current.hex
      ? current.hex
      : current.kind === 'color' && current.id
        ? CHINESE_COLOR_RECIPES.find((c) => c.id === current.id)?.hex || '#88ADED'
        : '#88ADED'

  return (
    <Dialog
      visible={visible}
      header="聊天背景"
      onClose={onClose}
      footer={
        <Button theme="default" onClick={onClose}>
          关闭
        </Button>
      }
      width={480}
    >
      <p className="im-muted" style={{ marginTop: 0, marginBottom: 12 }}>
        对所有会话生效。可选中国色配方、调色盘或上传图片。
      </p>

      <div className="im-bg-section-title">预设</div>
      <div className="im-bg-palette">
        <button
          type="button"
          className={
            current.kind === 'default' ? 'im-bg-chip is-active' : 'im-bg-chip'
          }
          style={{ background: '#f5f5f5' }}
          disabled={busy}
          title="默认"
          onClick={() => void apply({ kind: 'default' })}
        >
          <span>默认</span>
        </button>
        {CHINESE_COLOR_RECIPES.map((c) => {
          const soft = softChatHex(c.hex)
          const on = current.kind === 'color' && current.id === c.id
          return (
            <button
              key={c.id}
              type="button"
              className={on ? 'im-bg-chip is-active' : 'im-bg-chip'}
              style={{ background: soft }}
              disabled={busy}
              title={`${c.name} ${c.hex}`}
              onClick={() => void apply({ kind: 'color', id: c.id, hex: c.hex })}
            >
              <i className="im-bg-chip__dot" style={{ background: c.hex }} />
              <span>{c.name}</span>
            </button>
          )
        })}
      </div>

      <div className="im-bg-section-title">调色盘</div>
      <QqColorPicker
        key={visible ? initHex : 'closed'}
        initialHex={initHex}
        busy={busy}
        onApply={(hex) => void apply({ kind: 'color', hex })}
      />

      <div className="im-bg-section-title">自定义图片</div>
      <div className="im-bg-actions">
        <Button
          theme="primary"
          variant="outline"
          loading={busy}
          onClick={() => fileRef.current?.click()}
        >
          上传图片
        </Button>
        {current.kind === 'image' && current.url && (
          <div className="im-bg-preview" style={chatBgStyle(current)} title="当前图片背景" />
        )}
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          hidden
          onChange={async (e) => {
            const file = e.target.files?.[0]
            e.target.value = ''
            if (!file) return
            if (file.size > 10 * 1024 * 1024) {
              MessagePlugin.warning('图片过大（最大 10MB）')
              return
            }
            setBusy(true)
            try {
              const u = await api.uploadMeChatBg(file)
              onChanged(u)
              MessagePlugin.success('聊天背景已更新')
            } catch (err) {
              MessagePlugin.error(apiErrorMessage(err, '上传失败'))
            } finally {
              setBusy(false)
            }
          }}
        />
      </div>
    </Dialog>
  )
}

function QqColorPicker({
  initialHex,
  busy,
  onApply,
}: {
  initialHex: string
  busy: boolean
  onApply: (hex: string) => void
}) {
  const svRef = useRef<HTMLDivElement>(null)
  const [hsv, setHsv] = useState(() => hexToHsv(initialHex))
  const hex = hsvToHex(hsv.h, hsv.s, hsv.v)
  const pure = hsvToHex(hsv.h, 1, 1)

  useEffect(() => {
    setHsv(hexToHsv(initialHex))
  }, [initialHex])

  const pickSv = useCallback((clientX: number, clientY: number) => {
    const el = svRef.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    const s = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width))
    const v = Math.max(0, Math.min(1, 1 - (clientY - rect.top) / rect.height))
    setHsv((prev) => ({ ...prev, s, v }))
  }, [])

  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      if (!svRef.current?.hasPointerCapture(e.pointerId)) return
      pickSv(e.clientX, e.clientY)
    }
    const onUp = (e: PointerEvent) => {
      if (svRef.current?.hasPointerCapture(e.pointerId)) {
        svRef.current.releasePointerCapture(e.pointerId)
      }
    }
    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
    return () => {
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
    }
  }, [pickSv])

  return (
    <div className="im-bg-picker">
      <div className="im-bg-picker__sv-wrap">
        <div
          ref={svRef}
          className="im-bg-picker__sv"
          style={{ backgroundColor: pure }}
          onPointerDown={(e) => {
            e.currentTarget.setPointerCapture(e.pointerId)
            pickSv(e.clientX, e.clientY)
          }}
        >
          <span
            className="im-bg-picker__knob"
            style={{ left: `${hsv.s * 100}%`, top: `${(1 - hsv.v) * 100}%` }}
          />
        </div>
        <input
          className="im-bg-picker__hue"
          type="range"
          min={0}
          max={360}
          value={Math.round(hsv.h)}
          aria-label="色相"
          onChange={(e) => setHsv((prev) => ({ ...prev, h: Number(e.target.value) }))}
        />
      </div>
      <div className="im-bg-picker__side">
        <div className="im-bg-picker__preview" style={{ background: hex }} />
        <code className="im-bg-picker__hex">{hex}</code>
        <Button size="small" theme="primary" disabled={busy} onClick={() => onApply(hex)}>
          应用此色
        </Button>
      </div>
    </div>
  )
}
