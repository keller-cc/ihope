import { useMemo, useState } from 'react'
import { Button, Checkbox, Dialog, MessagePlugin, Radio } from 'tdesign-react'
import { api, apiErrorMessage, type Conversation } from '../api'
import { conversationTitle } from '../lib/chatFormat'
import { Avatar } from './Avatar'

type Props = {
  visible: boolean
  sourceConversationId: string
  messageIds: string[]
  conversations: Conversation[]
  onClose: () => void
  onDone: () => void
}

export function ForwardDialog({
  visible,
  sourceConversationId,
  messageIds,
  conversations,
  onClose,
  onDone,
}: Props) {
  const [selected, setSelected] = useState<string[]>([])
  const [mode, setMode] = useState<'one_by_one' | 'merge'>('one_by_one')
  const [busy, setBusy] = useState(false)
  const multi = messageIds.length > 1

  const targets = useMemo(
    () => conversations.filter((c) => c.id !== sourceConversationId),
    [conversations, sourceConversationId],
  )

  const toggle = (id: string) => {
    setSelected((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id],
    )
  }

  const submit = async () => {
    if (!selected.length) {
      MessagePlugin.warning('请选择会话')
      return
    }
    setBusy(true)
    try {
      for (const targetId of selected) {
        await api.forwardMessages(targetId, {
          sourceConversationId,
          messageIds,
          mode: multi ? mode : 'one_by_one',
        })
      }
      MessagePlugin.success('已转发')
      onDone()
      onClose()
      setSelected([])
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '转发失败'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Dialog
      visible={visible}
      header="转发"
      onClose={onClose}
      confirmBtn={
        <Button theme="primary" loading={busy} onClick={() => void submit()}>
          发送
        </Button>
      }
      cancelBtn={
        <Button theme="default" onClick={onClose}>
          取消
        </Button>
      }
      width={420}
    >
      <p className="im-muted" style={{ marginTop: 0 }}>
        已选 {messageIds.length} 条消息，选择目标会话
      </p>
      {multi && (
        <div style={{ marginBottom: 12 }}>
          <Radio.Group
            value={mode}
            onChange={(v) => setMode(v as 'one_by_one' | 'merge')}
          >
            <Radio value="one_by_one">逐条转发</Radio>
            <Radio value="merge">合并转发</Radio>
          </Radio.Group>
        </div>
      )}
      <div className="im-forward-list">
        {targets.length === 0 ? (
          <p className="im-muted">暂无其他会话</p>
        ) : (
          targets.map((c) => (
            <label key={c.id} className="im-forward-row">
              <Checkbox
                checked={selected.includes(c.id)}
                onChange={() => toggle(c.id)}
              />
              <Avatar
                name={conversationTitle(c)}
                src={c.type === 'dm' ? c.peerAvatarUrl : c.avatarUrl}
                size="sm"
              />
              <span>{conversationTitle(c)}</span>
            </label>
          ))
        )}
      </div>
    </Dialog>
  )
}
