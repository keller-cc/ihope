import type { GroupJoinRequest } from '@/api'
import { Avatar } from '@/components/Avatar'

type Props = {
  requests: GroupJoinRequest[]
  busyId?: string | null
  onBack?: () => void
  onAccept: (conversationId: string, requestId: string) => void
  onReject: (conversationId: string, requestId: string) => void
  onOpenGroup?: (conversationId: string) => void
}

export function GroupJoinRequestsPane({
  requests,
  busyId,
  onBack,
  onAccept,
  onReject,
  onOpenGroup,
}: Props) {
  return (
    <section className="im-friend-req">
      <header className="im-chat-head">
        {onBack && (
          <button type="button" className="im-back" onClick={onBack} aria-label="返回">
            ‹
          </button>
        )}
        <h2 className="im-chat-head__title">入群申请</h2>
      </header>

      <div className="im-friend-req__body">
        {requests.length === 0 ? (
          <p className="im-empty-hint">暂无待处理的入群申请</p>
        ) : (
          requests.map((r) => {
            const groupTitle = r.group?.title || '群聊'
            return (
              <div key={r.id} className="im-request-row">
                <Avatar name={r.fromUser?.username || '?'} src={r.fromUser?.avatarUrl} />
                <div className="im-list-item__body">
                  <div className="im-list-item__title">{r.fromUser?.username || '用户'}</div>
                  <div className="im-list-item__preview">
                    申请加入「{groupTitle}」
                    {r.invitedBy?.username
                      ? ` · ${r.invitedBy.username} 邀请`
                      : r.message?.trim()
                        ? ` · ${r.message}`
                        : ''}
                  </div>
                  {onOpenGroup && (
                    <button
                      type="button"
                      className="im-request-row__group"
                      onClick={() => onOpenGroup(r.conversationId)}
                    >
                      来自群 · {groupTitle}
                      {r.group?.groupNo ? `（${r.group.groupNo}）` : ''}
                    </button>
                  )}
                </div>
                <button
                  type="button"
                  className="im-btn"
                  disabled={busyId === r.id}
                  onClick={() => onAccept(r.conversationId, r.id)}
                >
                  同意
                </button>
                <button
                  type="button"
                  className="im-btn im-btn--ghost"
                  disabled={busyId === r.id}
                  onClick={() => onReject(r.conversationId, r.id)}
                >
                  拒绝
                </button>
              </div>
            )
          })
        )}
      </div>
    </section>
  )
}
