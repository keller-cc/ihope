import { useRef, useState } from 'react'
import { Button, Dialog, MessagePlugin } from 'tdesign-react'
import { api, apiErrorMessage, type ChatBg, type User } from '../api'
import { CHAT_BG_GRADIENTS, chatBgStyle } from '../lib/chatBg'

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
      width={460}
    >
      <p className="im-muted" style={{ marginTop: 0 }}>
        对所有会话生效，可选择渐变色或上传图片（最大 10MB）。
      </p>

      <div className="im-bg-section-title">预设渐变</div>
      <div className="im-bg-grid">
        <button
          type="button"
          className={
            current.kind === 'default' ? 'im-bg-swatch is-active' : 'im-bg-swatch'
          }
          style={{ background: '#f5f5f5' }}
          disabled={busy}
          onClick={() => void apply({ kind: 'default' })}
          title="默认"
        >
          <span>默认</span>
        </button>
        {CHAT_BG_GRADIENTS.map((g) => (
          <button
            key={g.id}
            type="button"
            className={
              current.kind === 'gradient' && current.id === g.id
                ? 'im-bg-swatch is-active'
                : 'im-bg-swatch'
            }
            style={{ background: g.css }}
            disabled={busy}
            onClick={() => void apply({ kind: 'gradient', id: g.id })}
            title={g.label}
          >
            <span>{g.label}</span>
          </button>
        ))}
      </div>

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
          <div
            className="im-bg-preview"
            style={chatBgStyle(current)}
            title="当前图片背景"
          />
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
