import type { FriendRequest } from '../api'
import { Avatar } from './Avatar'

type Props = {
  incoming: FriendRequest[]
  outgoing: FriendRequest[]
  busyId?: string | null
  onBack?: () => void
  onAccept: (id: string) => void
  onReject: (id: string) => void
  onCancel: (id: string) => void
}

export function FriendRequestsPane({
  incoming,
  outgoing,
  busyId,
  onBack,
  onAccept,
  onReject,
  onCancel,
}: Props) {
  const empty = incoming.length === 0 && outgoing.length === 0

  return (
    <section className="im-friend-req">
      <header className="im-chat-head">
        {onBack && (
          <button type="button" className="im-back" onClick={onBack} aria-label="返回">
            ‹
          </button>
        )}
        <h2 className="im-chat-head__title">新朋友</h2>
      </header>

      <div className="im-friend-req__body">
        {empty ? (
          <p className="im-empty-hint">暂无好友申请。点右上角 + 可搜索添加好友。</p>
        ) : (
          <>
            {incoming.length > 0 && (
              <div className="im-section">待处理 · {incoming.length}</div>
            )}
            {incoming.map((r) => (
              <div key={r.id} className="im-request-row">
                <Avatar name={r.fromUser?.username || '?'} src={r.fromUser?.avatarUrl} />
                <div className="im-list-item__body">
                  <div className="im-list-item__title">{r.fromUser?.username || '用户'}</div>
                  <div className="im-list-item__preview">
                    {r.message?.trim() || '请求添加你为好友'}
                  </div>
                </div>
                <button
                  type="button"
                  className="im-btn"
                  disabled={busyId === r.id}
                  onClick={() => onAccept(r.id)}
                >
                  同意
                </button>
                <button
                  type="button"
                  className="im-btn im-btn--ghost"
                  disabled={busyId === r.id}
                  onClick={() => onReject(r.id)}
                >
                  拒绝
                </button>
              </div>
            ))}

            {outgoing.length > 0 && (
              <div className="im-section">等待对方验证 · {outgoing.length}</div>
            )}
            {outgoing.map((r) => (
              <div key={r.id} className="im-request-row">
                <Avatar name={r.toUser?.username || '?'} src={r.toUser?.avatarUrl} />
                <div className="im-list-item__body">
                  <div className="im-list-item__title">{r.toUser?.username || '用户'}</div>
                  <div className="im-list-item__preview">
                    {r.message?.trim() ? `已发送：${r.message}` : '等待对方通过'}
                  </div>
                </div>
                <button
                  type="button"
                  className="im-btn im-btn--ghost"
                  disabled={busyId === r.id}
                  onClick={() => onCancel(r.id)}
                >
                  撤回
                </button>
              </div>
            ))}
          </>
        )}
      </div>
    </section>
  )
}
