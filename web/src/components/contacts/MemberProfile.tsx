import { useState } from 'react'
import { ChevronRightIcon } from 'tdesign-icons-react'
import { Dialog, Input, MessagePlugin } from 'tdesign-react'
import { api, apiErrorMessage, type Contact, type Conversation } from '@/api'
import { Avatar } from '@/components/Avatar'

type Props = {
  member: Contact
  group: Conversation
  selfId: string
  onBack: () => void
  onMessage: () => void
  onFriendAdded?: () => void
  onMembersChanged?: () => void
  showBack: boolean
}

export function MemberProfile({
  member,
  group,
  selfId,
  onBack,
  onMessage,
  onFriendAdded,
  onMembersChanged,
  showBack,
}: Props) {
  const [busy, setBusy] = useState(false)
  const [addOpen, setAddOpen] = useState(false)
  const [addMsg, setAddMsg] = useState('')
  const [titleEdit, setTitleEdit] = useState(false)
  const [titleDraft, setTitleDraft] = useState('')
  const [confirm, setConfirm] = useState<{
    title: string
    body: string
    danger?: boolean
    onOk: () => void
  } | null>(null)

  const isSelf = member.id === selfId
  const isOwner = group.ownerId === member.id
  const canManage = !!(group.isOwner || group.isAdmin)
  const canKick =
    !isSelf &&
    !isOwner &&
    (group.isOwner || (group.isAdmin && !member.isAdmin))
  const displayName = member.remark?.trim() || member.username
  const isFriend = !!member.isFriend
  const showManage = !isSelf && (canManage || canKick || (group.isOwner && !isOwner))
  const customTitle =
    member.memberTitle &&
    member.memberTitle !== '群主' &&
    member.memberTitle !== '管理员'
      ? member.memberTitle
      : ''

  const addFriend = async () => {
    setBusy(true)
    try {
      const source = `来自群「${group.title || '群聊'}」`
      const custom = addMsg.trim()
      const message = custom ? `${source}：${custom}` : source
      await api.addFriend(member.username, message)
      MessagePlugin.success('好友申请已发送')
      setAddOpen(false)
      setAddMsg('')
      onFriendAdded?.()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '添加失败'))
    } finally {
      setBusy(false)
    }
  }

  const saveTitle = async () => {
    setBusy(true)
    try {
      await api.setGroupMemberTitle(group.id, member.id, titleDraft.trim())
      MessagePlugin.success(titleDraft.trim() ? '头衔已更新' : '已清除自定义头衔')
      setTitleEdit(false)
      onMembersChanged?.()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '设置失败'))
    } finally {
      setBusy(false)
    }
  }

  const toggleAdmin = () => {
    const makeAdmin = !member.isAdmin
    setConfirm({
      title: makeAdmin ? '设为管理员' : '取消管理员',
      body: makeAdmin
        ? `将「${displayName}」设为管理员？`
        : `取消「${displayName}」的管理员身份？`,
      onOk: async () => {
        try {
          await api.setGroupMemberRole(group.id, member.id, makeAdmin ? 'admin' : 'member')
          MessagePlugin.success(makeAdmin ? '已设为管理员' : '已取消管理员')
          onMembersChanged?.()
        } catch (e) {
          MessagePlugin.error(apiErrorMessage(e, '设置失败'))
        }
      },
    })
  }

  const kick = () => {
    setConfirm({
      title: '移出群聊',
      body: `将「${displayName}」移出本群？`,
      danger: true,
      onOk: async () => {
        try {
          await api.kickGroupMember(group.id, member.id)
          MessagePlugin.success('已移除')
          onMembersChanged?.()
          onBack()
        } catch (e) {
          MessagePlugin.error(apiErrorMessage(e, '移除失败'))
        }
      },
    })
  }

  return (
    <section className="im-pane im-pane--settings">
      <header className="im-chat-head">
        {showBack && (
          <button type="button" className="im-back" style={{ display: 'grid' }} onClick={onBack}>
            ‹
          </button>
        )}
        <h2 className="im-chat-head__title">群成员</h2>
      </header>

      <div className="im-settings-scroll">
        <div className="im-set-hero">
          <Avatar name={displayName} src={member.avatarUrl} size="xl" />
          <div className="im-set-hero__meta">
            <strong>
              {displayName}
              {member.memberTitle ? (
                <span
                  className={
                    member.memberTitle === '群主'
                      ? 'im-role-badge'
                      : member.memberTitle === '管理员'
                        ? 'im-role-badge im-role-badge--admin'
                        : 'im-role-badge im-role-badge--custom'
                  }
                >
                  {member.memberTitle}
                </span>
              ) : null}
            </strong>
            {member.remark?.trim() && member.remark.trim() !== member.username && (
              <span>昵称：{member.username}</span>
            )}
            {member.hopeId && <span>IHope 号：{member.hopeId}</span>}
            <span className="im-muted">来自群「{group.title || '群聊'}」</span>
            {isFriend && !isSelf && <span className="im-muted">已是好友</span>}
          </div>
        </div>

        {!isSelf && (
          <div className="im-set-group">
            {isFriend ? (
              <button type="button" className="im-set-cell" onClick={onMessage}>
                <span className="im-set-cell__label">发消息</span>
                <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
              </button>
            ) : (
              <button type="button" className="im-set-cell" onClick={() => setAddOpen(true)}>
                <span className="im-set-cell__label">加好友</span>
                <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
              </button>
            )}
          </div>
        )}

        {isSelf && <p className="im-empty-hint">这是你自己</p>}

        {showManage && (
          <div className="im-set-group">
            {canManage && (
              <button
                type="button"
                className="im-set-cell"
                onClick={() => {
                  setTitleDraft(customTitle)
                  setTitleEdit(true)
                }}
              >
                <span className="im-set-cell__label">设置群头衔</span>
                <span className="im-set-cell__value">{customTitle || '未设置'}</span>
                <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
              </button>
            )}
            {group.isOwner && !isOwner && (
              <button type="button" className="im-set-cell" onClick={toggleAdmin}>
                <span className="im-set-cell__label">
                  {member.isAdmin ? '取消管理员' : '设为管理员'}
                </span>
                <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
              </button>
            )}
            {canKick && (
              <button type="button" className="im-set-cell im-set-cell--danger" onClick={kick}>
                <span className="im-set-cell__label">移出群聊</span>
              </button>
            )}
          </div>
        )}
      </div>

      <Dialog
        visible={addOpen}
        header={`添加「${displayName}」为好友`}
        onClose={() => setAddOpen(false)}
        onConfirm={() => void addFriend()}
        confirmBtn={{ content: '发送申请', loading: busy }}
        cancelBtn="取消"
      >
        <Input
          autofocus
          placeholder="验证信息（可选）"
          value={addMsg}
          onChange={(v) => setAddMsg(String(v))}
        />
      </Dialog>

      <Dialog
        visible={titleEdit}
        header={`设置「${displayName}」的群头衔`}
        onClose={() => setTitleEdit(false)}
        onConfirm={() => void saveTitle()}
        confirmBtn={{ content: '保存', loading: busy }}
        cancelBtn="取消"
      >
        <Input
          autofocus
          maxlength={12}
          placeholder="最多 12 字，留空清除"
          value={titleDraft}
          onChange={(v) => setTitleDraft(String(v))}
        />
      </Dialog>

      <Dialog
        visible={!!confirm}
        header={confirm?.title}
        theme={confirm?.danger ? 'danger' : 'default'}
        onClose={() => setConfirm(null)}
        onConfirm={() => {
          const fn = confirm?.onOk
          setConfirm(null)
          fn?.()
        }}
        confirmBtn={confirm?.danger ? { content: '确定', theme: 'danger' } : '确定'}
        cancelBtn="取消"
      >
        <p style={{ margin: 0 }}>{confirm?.body}</p>
      </Dialog>
    </section>
  )
}
