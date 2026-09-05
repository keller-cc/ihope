import type { Contact, Conversation, FriendRequest } from '../api'
import { conversationTitle } from '../lib/chatFormat'
import { Avatar } from './Avatar'

type Section = 'friends' | 'groups' | 'requests'

type Props = {
  section: Section
  onSection: (s: Section) => void
  friends: Contact[]
  groups: Conversation[]
  incoming: FriendRequest[]
  filter: string
  selectedFriendId: string | null
  selectedGroupId: string | null
  onSelectFriend: (f: Contact) => void
  onSelectGroup: (g: Conversation) => void
  onOpenRequests: () => void
  onAccept: (id: string) => void
  onReject: (id: string) => void
}

function displayName(f: Contact) {
  return f.remark?.trim() || f.username
}

export function ContactList({
  section,
  onSection,
  friends,
  groups,
  incoming,
  filter,
  selectedFriendId,
  selectedGroupId,
  onSelectFriend,
  onSelectGroup,
  onOpenRequests,
  onAccept,
  onReject,
}: Props) {
  const q = filter.trim().toLowerCase()
  const filteredFriends = friends.filter(
    (f) =>
      f.username.toLowerCase().includes(q) ||
      (f.remark || '').toLowerCase().includes(q) ||
      (f.hopeId || '').includes(q),
  )
  const filteredGroups = groups.filter((g) => conversationTitle(g).toLowerCase().includes(q))

  return (
    <>
      <div className="im-contact-tabs">
        <button
          type="button"
          className={section === 'friends' || section === 'requests' ? 'is-active' : undefined}
          onClick={() => onSection('friends')}
        >
          好友 ({friends.length})
        </button>
        <button
          type="button"
          className={section === 'groups' ? 'is-active' : undefined}
          onClick={() => onSection('groups')}
        >
          群聊 ({groups.length})
        </button>
      </div>

      {(section === 'friends' || section === 'requests') && (
        <div className="im-list">
          <button type="button" className="im-list-item" onClick={onOpenRequests}>
            <span className="im-avatar im-avatar--soft">新</span>
            <span className="im-list-item__body">
              <span className="im-list-item__row">
                <span className="im-list-item__title">新朋友</span>
                {incoming.length > 0 && <span className="im-badge">{incoming.length}</span>}
              </span>
              <span className="im-list-item__preview">
                {incoming.length > 0 ? `${incoming.length} 条待处理申请` : '添加好友与申请'}
              </span>
            </span>
          </button>

          {section === 'requests' ? (
            incoming.length === 0 ? (
              <p className="im-empty-hint">暂无好友申请</p>
            ) : (
              incoming.map((r) => (
                <div key={r.id} className="im-request-row">
                  <Avatar name={r.fromUser?.username || '?'} src={r.fromUser?.avatarUrl} />
                  <div className="im-list-item__body">
                    <div className="im-list-item__title">{r.fromUser?.username}</div>
                    <div className="im-list-item__preview">{r.message || '请求添加你为好友'}</div>
                  </div>
                  <button type="button" className="im-btn" onClick={() => onAccept(r.id)}>
                    同意
                  </button>
                  <button type="button" className="im-btn im-btn--ghost" onClick={() => onReject(r.id)}>
                    拒绝
                  </button>
                </div>
              ))
            )
          ) : filteredFriends.length === 0 ? (
            <p className="im-empty-hint">还没有好友，点 + 添加</p>
          ) : (
            filteredFriends.map((f) => (
              <button
                key={f.id}
                type="button"
                className={selectedFriendId === f.id ? 'im-list-item is-active' : 'im-list-item'}
                onClick={() => onSelectFriend(f)}
              >
                <Avatar name={displayName(f)} src={f.avatarUrl} />
                <span className="im-list-item__body">
                  <span className="im-list-item__title">{displayName(f)}</span>
                  <span className="im-list-item__preview">
                    {f.remark?.trim()
                      ? `昵称：${f.username}`
                      : f.hopeId
                        ? `IHope 号：${f.hopeId}`
                        : f.email}
                  </span>
                </span>
              </button>
            ))
          )}
        </div>
      )}

      {section === 'groups' && (
        <div className="im-list">
          {filteredGroups.length === 0 ? (
            <p className="im-empty-hint">还没有群，点 + 创建或加入</p>
          ) : (
            filteredGroups.map((g) => (
              <button
                key={g.id}
                type="button"
                className={selectedGroupId === g.id ? 'im-list-item is-active' : 'im-list-item'}
                onClick={() => onSelectGroup(g)}
              >
                <Avatar name={conversationTitle(g)} src={g.avatarUrl} group />
                <span className="im-list-item__body">
                  <span className="im-list-item__title">{conversationTitle(g)}</span>
                  <span className="im-list-item__preview">
                    {g.groupNo
                      ? `群号 ${g.groupNo} · ${g.memberCount || 0} 人`
                      : `${g.memberCount || 0} 名成员`}
                  </span>
                </span>
              </button>
            ))
          )}
        </div>
      )}
    </>
  )
}
