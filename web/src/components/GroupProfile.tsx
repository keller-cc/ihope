import { useMemo, useRef, useState } from 'react'
import { ChevronRightIcon } from 'tdesign-icons-react'
import { Button, Checkbox, Dialog, Input, MessagePlugin, Switch } from 'tdesign-react'
import { api, apiErrorMessage, type Contact, type Conversation } from '../api'
import { Avatar } from './Avatar'

type Props = {
  group: Conversation
  members: Contact[]
  friends: Contact[]
  renameDraft: string
  onRenameDraft: (v: string) => void
  onSaveRename: () => void | Promise<void>
  onAvatarUpdated: (g: Conversation) => void
  onMembersChanged: () => void
  onTogglePin?: () => void
  onToggleMute?: () => void
  onFindHistory?: () => void
  onLeave: () => void
  onDissolved: () => void
  onBack: () => void
  showBack: boolean
}

export function GroupProfile({
  group,
  members,
  friends,
  renameDraft,
  onRenameDraft,
  onSaveRename,
  onAvatarUpdated,
  onMembersChanged,
  onTogglePin,
  onToggleMute,
  onFindHistory,
  onLeave,
  onDissolved,
  onBack,
  showBack,
}: Props) {
  const fileRef = useRef<HTMLInputElement>(null)
  const [inviteOpen, setInviteOpen] = useState(false)
  const [renameOpen, setRenameOpen] = useState(false)
  const [titleEdit, setTitleEdit] = useState<{ member: Contact; value: string } | null>(null)
  const [confirm, setConfirm] = useState<{
    title: string
    body: string
    danger?: boolean
    onOk: () => void
  } | null>(null)
  const [picked, setPicked] = useState<string[]>([])
  const [busy, setBusy] = useState(false)

  const canManage = !!(group.isOwner || group.isAdmin)
  const memberCount = group.memberCount || members.length || 0

  const inviteCandidates = useMemo(() => {
    const inGroup = new Set(members.map((m) => m.id))
    return friends.filter((f) => !inGroup.has(f.id))
  }, [friends, members])

  const canKick = (m: Contact) => {
    if (group.ownerId === m.id) return false
    if (group.isOwner) return true
    if (group.isAdmin && !m.isAdmin) return true
    return false
  }

  const invite = async () => {
    if (!picked.length) {
      MessagePlugin.warning('请选择要邀请的好友')
      return
    }
    setBusy(true)
    try {
      await api.inviteGroupMembers(group.id, picked)
      MessagePlugin.success('已邀请')
      setInviteOpen(false)
      setPicked([])
      onMembersChanged()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '邀请失败'))
    } finally {
      setBusy(false)
    }
  }

  const kick = (memberId: string, name: string) => {
    setConfirm({
      title: '移出群聊',
      body: `将「${name}」移出本群？`,
      danger: true,
      onOk: async () => {
        try {
          await api.kickGroupMember(group.id, memberId)
          MessagePlugin.success('已移除')
          onMembersChanged()
        } catch (e) {
          MessagePlugin.error(apiErrorMessage(e, '移除失败'))
        }
      },
    })
  }

  const toggleAdmin = (m: Contact) => {
    const makeAdmin = !m.isAdmin
    setConfirm({
      title: makeAdmin ? '设为管理员' : '取消管理员',
      body: makeAdmin
        ? `将「${m.username}」设为管理员？管理员可邀请成员、移除普通成员、修改群名与头像、设置头衔、撤回消息。`
        : `取消「${m.username}」的管理员身份？`,
      onOk: async () => {
        try {
          await api.setGroupMemberRole(group.id, m.id, makeAdmin ? 'admin' : 'member')
          MessagePlugin.success(makeAdmin ? '已设为管理员' : '已取消管理员')
          onMembersChanged()
        } catch (e) {
          MessagePlugin.error(apiErrorMessage(e, '设置失败'))
        }
      },
    })
  }

  const openTitleEdit = (m: Contact) => {
    const current =
      m.memberTitle && m.memberTitle !== '群主' && m.memberTitle !== '管理员'
        ? m.memberTitle
        : ''
    setTitleEdit({ member: m, value: current })
  }

  const saveTitle = async () => {
    if (!titleEdit) return
    setBusy(true)
    try {
      await api.setGroupMemberTitle(group.id, titleEdit.member.id, titleEdit.value.trim())
      MessagePlugin.success(titleEdit.value.trim() ? '头衔已更新' : '已清除自定义头衔')
      setTitleEdit(null)
      onMembersChanged()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '设置失败'))
    } finally {
      setBusy(false)
    }
  }

  const leave = () => {
    setConfirm({
      title: '退出群聊',
      body: '退出后将不再接收本群消息，确定退出？',
      danger: true,
      onOk: onLeave,
    })
  }

  const dissolve = () => {
    setConfirm({
      title: '解散群聊',
      body: '解散后群聊与消息不可恢复，确定解散？',
      danger: true,
      onOk: async () => {
        try {
          await api.dissolveGroup(group.id)
          MessagePlugin.success('群已解散')
          onDissolved()
        } catch (e) {
          MessagePlugin.error(apiErrorMessage(e, '解散失败'))
        }
      },
    })
  }

  const saveRename = async () => {
    try {
      await onSaveRename()
      setRenameOpen(false)
    } catch {
      /* parent shows error */
    }
  }

  return (
    <section className="im-pane im-pane--settings">
      <header className="im-chat-head">
        {showBack && (
          <button type="button" className="im-back" style={{ display: 'grid' }} onClick={onBack}>
            ‹
          </button>
        )}
        <h2 className="im-chat-head__title">群设置</h2>
      </header>

      <div className="im-settings-scroll">
        <div className="im-set-group">
          <div className="im-set-member-grid">
            {members.slice(0, 14).map((m) => (
              <div key={m.id} className="im-set-member-grid__item" title={m.username}>
                <Avatar name={m.username} src={m.avatarUrl} size="sm" />
                <span>{m.username}</span>
              </div>
            ))}
            {canManage && (
              <button
                type="button"
                className="im-set-member-grid__add"
                aria-label="邀请好友"
                onClick={() => setInviteOpen(true)}
              >
                +
              </button>
            )}
          </div>
          {canManage ? (
            <button type="button" className="im-set-cell" onClick={() => setRenameOpen(true)}>
              <span className="im-set-cell__label">群聊名称</span>
              <span className="im-set-cell__value">{group.title || '群聊'}</span>
              <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
            </button>
          ) : (
            <div className="im-set-cell im-set-cell--static">
              <span className="im-set-cell__label">群聊名称</span>
              <span className="im-set-cell__value">{group.title || '群聊'}</span>
            </div>
          )}
          {canManage && (
            <button
              type="button"
              className="im-set-cell"
              onClick={() => fileRef.current?.click()}
            >
              <span className="im-set-cell__label">群头像</span>
              <Avatar name={group.title || '群'} src={group.avatarUrl} size="sm" group />
              <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
            </button>
          )}
          {group.groupNo && (
            <div className="im-set-cell im-set-cell--static">
              <span className="im-set-cell__label">群号</span>
              <span className="im-set-cell__value">{group.groupNo}</span>
            </div>
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
              try {
                const g = await api.uploadGroupAvatar(group.id, file)
                onAvatarUpdated(g)
                MessagePlugin.success('群头像已更新')
              } catch (err) {
                MessagePlugin.error(apiErrorMessage(err, '上传失败'))
              }
            }}
          />
        </div>

        {(onTogglePin || onToggleMute || onFindHistory) && (
          <div className="im-set-group">
            {onFindHistory && (
              <button type="button" className="im-set-cell" onClick={onFindHistory}>
                <span className="im-set-cell__label">查找聊天记录</span>
                <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
              </button>
            )}
            {onTogglePin && (
              <div className="im-set-cell im-set-cell--switch">
                <span className="im-set-cell__label">置顶聊天</span>
                <Switch value={!!group.pinned} onChange={() => onTogglePin()} />
              </div>
            )}
            {onToggleMute && (
              <div className="im-set-cell im-set-cell--switch">
                <span className="im-set-cell__label">消息免打扰</span>
                <Switch value={!!group.muted} onChange={() => onToggleMute()} />
              </div>
            )}
          </div>
        )}

        <div className="im-set-group im-set-group--list">
          <div className="im-set-section-title">群成员（{memberCount}）</div>
          {members.map((m) => {
            const isOwner = group.ownerId === m.id
            return (
              <div key={m.id} className="im-member-row">
                <Avatar name={m.username} src={m.avatarUrl} size="sm" />
                <div className="im-member-row__meta">
                  <strong>
                    {m.username}
                    {m.memberTitle ? (
                      <span
                        className={
                          m.memberTitle === '群主'
                            ? 'im-role-badge'
                            : m.memberTitle === '管理员'
                              ? 'im-role-badge im-role-badge--admin'
                              : 'im-role-badge im-role-badge--custom'
                        }
                      >
                        {m.memberTitle}
                      </span>
                    ) : null}
                  </strong>
                  {m.hopeId && <div className="im-muted">IHope 号：{m.hopeId}</div>}
                </div>
                {(canManage || (group.isOwner && !isOwner) || canKick(m)) && (
                  <div className="im-member-actions">
                    {canManage && (
                      <Button size="small" variant="text" onClick={() => openTitleEdit(m)}>
                        头衔
                      </Button>
                    )}
                    {group.isOwner && !isOwner && (
                      <Button size="small" variant="text" onClick={() => toggleAdmin(m)}>
                        {m.isAdmin ? '取消管理' : '设为管理'}
                      </Button>
                    )}
                    {canKick(m) && (
                      <Button
                        size="small"
                        theme="danger"
                        variant="text"
                        onClick={() => kick(m.id, m.username)}
                      >
                        移除
                      </Button>
                    )}
                  </div>
                )}
              </div>
            )
          })}
        </div>

        <div className="im-set-group">
          <button type="button" className="im-set-cell im-set-cell--danger" onClick={leave}>
            <span className="im-set-cell__label">退出群聊</span>
          </button>
          {group.isOwner && (
            <button type="button" className="im-set-cell im-set-cell--danger" onClick={dissolve}>
              <span className="im-set-cell__label">解散群聊</span>
            </button>
          )}
        </div>
      </div>

      <Dialog
        visible={renameOpen}
        header="修改群名称"
        onClose={() => setRenameOpen(false)}
        onConfirm={saveRename}
        confirmBtn="保存"
        cancelBtn="取消"
      >
        <Input
          autofocus
          maxlength={40}
          placeholder="群名称"
          value={renameDraft}
          onChange={(v) => onRenameDraft(String(v))}
        />
      </Dialog>

      <Dialog
        visible={!!titleEdit}
        header={titleEdit ? `设置「${titleEdit.member.username}」的群头衔` : '群头衔'}
        onClose={() => setTitleEdit(null)}
        onConfirm={() => void saveTitle()}
        confirmBtn={{ content: '保存', loading: busy }}
        cancelBtn="取消"
      >
        <Input
          autofocus
          maxlength={12}
          placeholder="最多 12 字，留空清除"
          value={titleEdit?.value || ''}
          onChange={(v) =>
            setTitleEdit((prev) => (prev ? { ...prev, value: String(v) } : prev))
          }
        />
      </Dialog>

      <Dialog
        visible={inviteOpen}
        header="邀请好友入群"
        onClose={() => setInviteOpen(false)}
        onConfirm={() => void invite()}
        confirmBtn={{ content: '邀请', loading: busy }}
        cancelBtn="取消"
      >
        {inviteCandidates.length === 0 ? (
          <p className="im-muted">没有可邀请的好友（需先加好友且对方不在群内）</p>
        ) : (
          <Checkbox.Group
            value={picked}
            onChange={(v) => setPicked(v as string[])}
            options={inviteCandidates.map((f) => ({
              value: f.id,
              label: f.remark || f.username,
            }))}
          />
        )}
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
