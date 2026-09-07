import type { Contact, Conversation } from '@/api'
import { conversationTitle } from '@/lib/chatFormat'
import { Avatar } from '@/components/Avatar'

type Section = 'friends' | 'groups'

type Props = {
  section: Section
  onSection: (s: Section) => void
  friends: Contact[]
  groups: Conversation[]
  incomingCount: number
  filter: string
  selectedFriendId: string | null
  selectedGroupId: string | null
  requestsOpen?: boolean
  onSelectFriend: (f: Contact) => void
  onSelectGroup: (g: Conversation) => void
  onOpenRequests: () => void
}

function displayName(f: Contact) {
  return f.remark?.trim() || f.username
}

export function ContactList({
  section,
  onSection,
  friends,
  groups,
  incomingCount,
  filter,
  selectedFriendId,
  selectedGroupId,
  requestsOpen,
  onSelectFriend,
  onSelectGroup,
  onOpenRequests,
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
          className={section === 'friends' ? 'is-active' : undefined}
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

      {section === 'friends' && (
        <div className="im-list">
          <button
            type="button"
            className={requestsOpen ? 'im-list-item is-active' : 'im-list-item'}
            onClick={onOpenRequests}
          >
            <span className="im-avatar im-avatar--soft">新</span>
            <span className="im-list-item__body">
              <span className="im-list-item__row">
                <span className="im-list-item__title">新朋友</span>
                {incomingCount > 0 && <span className="im-badge">{incomingCount}</span>}
              </span>
              <span className="im-list-item__preview">
                {incomingCount > 0 ? `${incomingCount} 条待处理申请` : '添加好友与申请'}
              </span>
            </span>
          </button>

          {filteredFriends.length === 0 ? (
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
