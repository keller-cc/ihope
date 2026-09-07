import { useEffect, useMemo, useRef, useState } from 'react'
import { ChevronRightIcon } from 'tdesign-icons-react'
import { Button, Dialog, Input, MessagePlugin, Radio, Switch } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  type Contact,
  type Conversation,
  type GroupJoinRequest,
} from '@/api'
import { Avatar } from '@/components/Avatar'
import { useIsMobile } from '@/hooks/useIsMobile'
import { GroupAnnouncementDialog } from './GroupAnnouncementDialog'

const JOIN_MODE_OPTIONS = [
  { value: 'anyone', label: '允许任何人加入', desc: '通过群号即可直接入群' },
  { value: 'verify', label: '需要验证信息', desc: '申请后需群主/管理员同意' },
  { value: 'deny', label: '不允许任何人加入', desc: '仅群主/管理员可邀请入群' },
] as const

function joinModeLabel(mode?: string) {
  return JOIN_MODE_OPTIONS.find((o) => o.value === mode)?.label || '需要验证信息'
}

function resolveJoinMode(group: Conversation): 'anyone' | 'verify' | 'deny' {
  if (group.joinMode === 'anyone' || group.joinMode === 'verify' || group.joinMode === 'deny') {
    return group.joinMode
  }
  return group.inviteRequiresApproval ? 'verify' : 'anyone'
}

type Props = {
  group: Conversation
  members: Contact[]
  friends: Contact[]
  renameDraft: string
  onRenameDraft: (v: string) => void
  onSaveRename: () => void | Promise<void>
  onAvatarUpdated: (g: Conversation) => void
  onGroupUpdated: (g: Conversation) => void
  onMembersChanged: () => void
  onSelectMember: (m: Contact) => void
  onTogglePin?: () => void
  onToggleMute?: () => void
  onFindHistory?: () => void
  onEnterChat?: () => void
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
  onGroupUpdated,
  onMembersChanged,
  onSelectMember,
  onTogglePin,
  onToggleMute,
  onFindHistory,
  onEnterChat,
  onLeave,
  onDissolved,
  onBack,
  showBack,
}: Props) {
  const isMobile = useIsMobile()
  const fileRef = useRef<HTMLInputElement>(null)
  const [inviteOpen, setInviteOpen] = useState(false)
  const [renameOpen, setRenameOpen] = useState(false)
  const [announceOpen, setAnnounceOpen] = useState(false)
  const [joinModeOpen, setJoinModeOpen] = useState(false)
  const [joinModeDraft, setJoinModeDraft] = useState<'anyone' | 'verify' | 'deny'>('verify')
  const [confirm, setConfirm] = useState<{
    title: string
    body: string
    danger?: boolean
    onOk: () => void
  } | null>(null)
  const [picked, setPicked] = useState<string[]>([])
  const [busy, setBusy] = useState(false)
  const [joinReqs, setJoinReqs] = useState<GroupJoinRequest[]>([])
  const [reqBusyId, setReqBusyId] = useState<string | null>(null)
  const [titleTarget, setTitleTarget] = useState<Contact | null>(null)
  const [titleDraft, setTitleDraft] = useState('')
  const [memberBusyId, setMemberBusyId] = useState<string | null>(null)

  const canManage = !!(group.isOwner || group.isAdmin)
  const canInvite = canManage || resolveJoinMode(group) !== 'deny'
  const memberCount = group.memberCount || members.length || 0
  const announcementPreview = (group.announcement || '').trim()
  const announcementCount = group.announcementCount || 0
  /** PC list shortcuts; mobile uses detail page (one row per action). */
  const showListQuick = canManage && !isMobile

  const canKickMember = (m: Contact) =>
    m.id !== group.ownerId && (group.isOwner || (group.isAdmin && !m.isAdmin))

  const openTitleEdit = (m: Contact) => {
    const current =
      m.memberTitle && m.memberTitle !== '群主' && m.memberTitle !== '管理员'
        ? m.memberTitle
        : ''
    setTitleDraft(current)
    setTitleTarget(m)
  }

  const saveMemberTitle = async () => {
    if (!titleTarget) return
    setMemberBusyId(titleTarget.id)
    try {
      await api.setGroupMemberTitle(group.id, titleTarget.id, titleDraft.trim())
      MessagePlugin.success(titleDraft.trim() ? '头衔已更新' : '已清除自定义头衔')
      setTitleTarget(null)
      onMembersChanged()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '设置失败'))
    } finally {
      setMemberBusyId(null)
    }
  }

  const toggleMemberAdmin = (m: Contact) => {
    const makeAdmin = !m.isAdmin
    const name = m.remark?.trim() || m.username
    setConfirm({
      title: makeAdmin ? '设为管理员' : '取消管理员',
      body: makeAdmin ? `将「${name}」设为管理员？` : `取消「${name}」的管理员身份？`,
      onOk: async () => {
        setMemberBusyId(m.id)
        try {
          await api.setGroupMemberRole(group.id, m.id, makeAdmin ? 'admin' : 'member')
          MessagePlugin.success(makeAdmin ? '已设为管理员' : '已取消管理员')
          onMembersChanged()
        } catch (e) {
          MessagePlugin.error(apiErrorMessage(e, '设置失败'))
        } finally {
          setMemberBusyId(null)
        }
      },
    })
  }

  const kickMember = (m: Contact) => {
    const name = m.remark?.trim() || m.username
    setConfirm({
      title: '移出群聊',
      body: `将「${name}」移出本群？`,
      danger: true,
      onOk: async () => {
        setMemberBusyId(m.id)
        try {
          await api.kickGroupMember(group.id, m.id)
          MessagePlugin.success('已移除')
          onMembersChanged()
        } catch (e) {
          MessagePlugin.error(apiErrorMessage(e, '移除失败'))
        } finally {
          setMemberBusyId(null)
        }
      },
    })
  }

  const loadJoinRequests = async () => {
    if (!canManage) {
      setJoinReqs([])
      return
    }
    try {
      const { requests } = await api.listGroupJoinRequests(group.id)
      setJoinReqs(requests)
    } catch {
      setJoinReqs([])
    }
  }

  useEffect(() => {
    void loadJoinRequests()
    // eslint-disable-next-line react-hooks/exhaustive-deps -- reload when group/manage role changes
  }, [group.id, canManage])

  const inviteCandidates = useMemo(() => {
    const inGroup = new Set(members.map((m) => m.id))
    return friends.filter((f) => !inGroup.has(f.id))
  }, [friends, members])

  const invite = async () => {
    if (!picked.length) {
      MessagePlugin.warning('请选择要邀请的好友')
      return
    }
    setBusy(true)
    try {
      const res = await api.inviteGroupMembers(group.id, picked)
      if (res.pending > 0 && res.added === 0) {
        MessagePlugin.success('已发送邀请，等待管理员同意')
      } else if (res.pending > 0) {
        MessagePlugin.success(`已邀请 ${res.added} 人，另有 ${res.pending} 人待管理员同意`)
      } else {
        MessagePlugin.success(res.added > 1 ? `已邀请 ${res.added} 人` : '已邀请')
      }
      setInviteOpen(false)
      setPicked([])
      if (res.added > 0) onMembersChanged()
      else if (canManage) void loadJoinRequests()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '邀请失败'))
    } finally {
      setBusy(false)
    }
  }

  const openJoinModeEdit = () => {
    setJoinModeDraft(resolveJoinMode(group))
    setJoinModeOpen(true)
  }

  const saveJoinMode = async () => {
    setBusy(true)
    try {
      const g = await api.patchGroup(group.id, { joinMode: joinModeDraft })
      onGroupUpdated({ ...group, ...g })
      setJoinModeOpen(false)
      MessagePlugin.success('加群方式已更新')
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '设置失败'))
    } finally {
      setBusy(false)
    }
  }

  const openAnnounceView = () => {
    setAnnounceOpen(true)
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

  const acceptJoin = async (req: GroupJoinRequest) => {
    setReqBusyId(req.id)
    try {
      await api.acceptGroupJoinRequest(group.id, req.id)
      MessagePlugin.success(`已同意 ${req.fromUser?.username || '用户'} 入群`)
      setJoinReqs((list) => list.filter((r) => r.id !== req.id))
      onMembersChanged()
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '操作失败'))
    } finally {
      setReqBusyId(null)
    }
  }

  const rejectJoin = async (req: GroupJoinRequest) => {
    setReqBusyId(req.id)
    try {
      await api.rejectGroupJoinRequest(group.id, req.id)
      MessagePlugin.success('已拒绝')
      setJoinReqs((list) => list.filter((r) => r.id !== req.id))
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '操作失败'))
    } finally {
      setReqBusyId(null)
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
          <button
            type="button"
            className="im-set-cell im-set-cell--announce"
            onClick={openAnnounceView}
          >
            <span className="im-set-cell__label">群公告</span>
            <span className="im-set-cell__value im-set-cell__value--wrap">
              {announcementPreview
                ? announcementCount > 1
                  ? `${announcementPreview}（共 ${announcementCount} 条）`
                  : announcementPreview
                : canManage
                  ? '未设置，点击新增'
                  : '暂无公告'}
            </span>
            <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
          </button>
          {canManage && (
            <button type="button" className="im-set-cell" onClick={openJoinModeEdit}>
              <span className="im-set-cell__label">加群方式</span>
              <span className="im-set-cell__value">{joinModeLabel(resolveJoinMode(group))}</span>
              <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
            </button>
          )}
          {!canManage && (
            <div className="im-set-cell im-set-cell--static">
              <span className="im-set-cell__label">加群方式</span>
              <span className="im-set-cell__value">{joinModeLabel(resolveJoinMode(group))}</span>
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

        <div className="im-set-group">
          <div className="im-set-section-title">群成员（{memberCount}）</div>
          <div className="im-set-member-grid">
            {members.map((m) => (
              <button
                key={m.id}
                type="button"
                className="im-set-member-grid__item"
                title={m.remark?.trim() || m.username}
                onClick={() => onSelectMember(m)}
              >
                <Avatar name={m.username} src={m.avatarUrl} size="sm" />
                <span>{m.remark?.trim() || m.username}</span>
                {m.memberTitle ? (
                  <em
                    className={
                      m.memberTitle === '群主'
                        ? 'im-grid-role'
                        : m.memberTitle === '管理员'
                          ? 'im-grid-role im-grid-role--admin'
                          : 'im-grid-role im-grid-role--custom'
                    }
                  >
                    {m.memberTitle}
                  </em>
                ) : null}
              </button>
            ))}
            {canInvite && (
              <button
                type="button"
                className="im-set-member-grid__item"
                title="邀请好友"
                onClick={() => setInviteOpen(true)}
              >
                <span className="im-set-member-grid__add" aria-hidden>
                  <i />
                  <i />
                </span>
                <span>邀请</span>
              </button>
            )}
          </div>
        </div>

        {canManage && (
          <div className="im-set-group im-set-group--list">
            <div className="im-set-section-title">入群申请（{joinReqs.length}）</div>
            <div className="im-set-scroll-box">
              {joinReqs.length === 0 ? (
                <p className="im-empty-hint im-empty-hint--inset">暂无待处理申请</p>
              ) : (
                joinReqs.map((r) => (
                  <div key={r.id} className="im-request-row">
                    <Avatar
                      name={r.fromUser?.username || '?'}
                      src={r.fromUser?.avatarUrl}
                      size="sm"
                    />
                    <div className="im-list-item__body">
                      <div className="im-list-item__title">{r.fromUser?.username || '用户'}</div>
                      <div className="im-list-item__preview">
                        {r.invitedBy?.username
                          ? `${r.invitedBy.username} 邀请入群`
                          : r.message?.trim() || '申请加入本群'}
                      </div>
                      <div className="im-muted">来自群「{group.title || '群聊'}」</div>
                    </div>
                    <Button
                      size="small"
                      theme="primary"
                      loading={reqBusyId === r.id}
                      onClick={() => void acceptJoin(r)}
                    >
                      同意
                    </Button>
                    <Button
                      size="small"
                      variant="outline"
                      disabled={reqBusyId === r.id}
                      onClick={() => void rejectJoin(r)}
                    >
                      拒绝
                    </Button>
                  </div>
                ))
              )}
            </div>
          </div>
        )}

        {canManage && (
          <div className="im-set-group im-set-group--list">
            <div className="im-set-section-title">群成员管理（{memberCount}）</div>
            <div className="im-set-scroll-box im-set-scroll-box--tall">
              {members.map((m) => {
                const name = m.remark?.trim() || m.username
                const isOwnerMember = m.id === group.ownerId
                const showKick = canKickMember(m)
                const showAdmin = !!group.isOwner && !isOwnerMember
                const showTitle = !isOwnerMember
                const busyRow = memberBusyId === m.id
                const hasQuick =
                  showListQuick && (showTitle || showAdmin || showKick)

                if (!hasQuick) {
                  return (
                    <button
                      key={m.id}
                      type="button"
                      className="im-member-row im-member-row--btn"
                      onClick={() => onSelectMember(m)}
                    >
                      <Avatar name={name} src={m.avatarUrl} size="sm" />
                      <div className="im-member-row__meta">
                        <strong>
                          {name}
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
                        {m.isFriend ? (
                          <div className="im-muted">好友</div>
                        ) : m.hopeId ? (
                          <div className="im-muted">IHope 号：{m.hopeId}</div>
                        ) : null}
                      </div>
                      <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
                    </button>
                  )
                }

                return (
                  <div key={m.id} className="im-member-row im-member-row--manage">
                    <button
                      type="button"
                      className="im-member-row__main"
                      onClick={() => onSelectMember(m)}
                    >
                      <Avatar name={name} src={m.avatarUrl} size="sm" />
                      <div className="im-member-row__meta">
                        <strong>
                          {name}
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
                        {m.isFriend ? (
                          <div className="im-muted">好友</div>
                        ) : m.hopeId ? (
                          <div className="im-muted">IHope 号：{m.hopeId}</div>
                        ) : null}
                      </div>
                    </button>
                    <div className="im-member-row__quick">
                      {showTitle && (
                        <Button
                          size="small"
                          variant="outline"
                          disabled={busyRow}
                          onClick={() => openTitleEdit(m)}
                        >
                          头衔
                        </Button>
                      )}
                      {showAdmin && (
                        <Button
                          size="small"
                          variant="outline"
                          disabled={busyRow}
                          onClick={() => toggleMemberAdmin(m)}
                        >
                          {m.isAdmin ? '取消管理' : '设管理'}
                        </Button>
                      )}
                      {showKick && (
                        <Button
                          size="small"
                          theme="danger"
                          variant="outline"
                          disabled={busyRow}
                          onClick={() => kickMember(m)}
                        >
                          移出
                        </Button>
                      )}
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        )}

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

        {onEnterChat && (
          <div className="im-set-actions">
            <Button theme="primary" block onClick={onEnterChat}>
              发消息
            </Button>
          </div>
        )}
      </div>

      <GroupAnnouncementDialog
        visible={announceOpen}
        group={group}
        canManage={canManage}
        onClose={() => setAnnounceOpen(false)}
        onChanged={(patch) => {
          if (patch) onGroupUpdated({ ...group, ...patch })
          else
            void api.listAnnouncements(group.id, { limit: 1 }).then((res) => {
              onGroupUpdated({
                ...group,
                announcement: res.announcements[0]?.body || '',
                announcementCount: res.total ?? res.announcements.length,
                pendingAnnouncement: res.pending ?? null,
              })
            })
        }}
      />

      <Dialog
        visible={joinModeOpen}
        header="加群方式"
        onClose={() => setJoinModeOpen(false)}
        onConfirm={() => void saveJoinMode()}
        confirmBtn={{ content: '确定', loading: busy }}
        cancelBtn="取消"
        width={420}
      >
        <Radio.Group
          value={joinModeDraft}
          onChange={(v) => setJoinModeDraft(v as 'anyone' | 'verify' | 'deny')}
          className="im-join-mode-group"
        >
          {JOIN_MODE_OPTIONS.map((o) => (
            <Radio key={o.value} value={o.value} allowUncheck={false}>
              <div className="im-join-mode-option">
                <strong>{o.label}</strong>
                <span className="im-muted">{o.desc}</span>
              </div>
            </Radio>
          ))}
        </Radio.Group>
      </Dialog>

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
        visible={!!titleTarget}
        header={`设置「${titleTarget?.remark?.trim() || titleTarget?.username || ''}」的群头衔`}
        onClose={() => setTitleTarget(null)}
        onConfirm={() => void saveMemberTitle()}
        confirmBtn={{
          content: '保存',
          loading: !!titleTarget && memberBusyId === titleTarget.id,
        }}
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
        visible={inviteOpen}
        header={`邀请好友加入「${group.title || '群聊'}」`}
        onClose={() => {
          setInviteOpen(false)
          setPicked([])
        }}
        onConfirm={() => void invite()}
        confirmBtn={{
          content: picked.length ? `邀请（${picked.length}）` : '邀请',
          loading: busy,
          disabled: !picked.length,
        }}
        cancelBtn="取消"
        width={420}
      >
        {inviteCandidates.length === 0 ? (
          <p className="im-muted">没有可邀请的好友（需先加好友且对方不在群内）</p>
        ) : (
          <div className="im-invite-pick">
            <p className="im-muted im-invite-pick__hint">
              邀请加入群「{group.title || '群聊'}」
              {group.groupNo ? `（${group.groupNo}）` : ''}
            </p>
            {resolveJoinMode(group) === 'verify' && !canManage && (
              <p className="im-muted im-invite-pick__hint">本群需要验证信息，邀请后需管理员同意</p>
            )}
            {resolveJoinMode(group) === 'deny' && !canManage && (
              <p className="im-muted im-invite-pick__hint">本群不允许加入，仅群主/管理员可邀请</p>
            )}
            {inviteCandidates.map((f) => {
              const name = f.remark?.trim() || f.username
              const selected = picked.includes(f.id)
              return (
                <button
                  key={f.id}
                  type="button"
                  className={selected ? 'im-invite-pick__row is-selected' : 'im-invite-pick__row'}
                  onClick={() =>
                    setPicked((prev) =>
                      prev.includes(f.id) ? prev.filter((x) => x !== f.id) : [...prev, f.id],
                    )
                  }
                >
                  <Avatar name={name} src={f.avatarUrl} size="sm" />
                  <span className="im-invite-pick__meta">
                    <strong>{name}</strong>
                    {f.remark?.trim() ? (
                      <span className="im-muted">昵称：{f.username}</span>
                    ) : f.hopeId ? (
                      <span className="im-muted">IHope 号：{f.hopeId}</span>
                    ) : null}
                  </span>
                  <span
                    className={selected ? 'im-invite-pick__check is-on' : 'im-invite-pick__check'}
                  />
                </button>
              )
            })}
          </div>
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
