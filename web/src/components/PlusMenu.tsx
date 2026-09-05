import { Dropdown } from 'tdesign-react'

type Action = 'addContact' | 'createGroup'

type Props = {
  onAction: (action: Action) => void
}

const items = [
  { content: '加好友/群', value: 'addContact' as const },
  { content: '创建群聊', value: 'createGroup' as const },
]

/** QQ-style “+” shortcut menu shared by 消息 / 联系人. */
export function PlusMenu({ onAction }: Props) {
  return (
    <Dropdown
      options={items}
      trigger="click"
      placement="bottom-right"
      onClick={(item) => {
        const v = String(item.value) as Action
        if (v === 'addContact' || v === 'createGroup') onAction(v)
      }}
    >
      <button type="button" className="im-icon-btn" title="更多" aria-label="更多">
        +
      </button>
    </Dropdown>
  )
}
