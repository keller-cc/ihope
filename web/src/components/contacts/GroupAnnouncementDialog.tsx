import { useEffect, useRef, useState } from 'react'
import { ChevronRightIcon, DeleteIcon, Edit1Icon } from 'tdesign-icons-react'
import { Button, Dialog, MessagePlugin, Textarea } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  type Conversation,
  type GroupAnnouncement,
} from '@/api'

type Mode = 'list' | 'create' | 'edit'

type Props = {
  visible: boolean
  group: Conversation
  canManage: boolean
  initialId?: string | null
  onClose: () => void
  onChanged: (groupPatch?: Partial<Conversation>) => void
}

function nextPending(items: GroupAnnouncement[]) {
  return items.find((x) => !x.acked) || null
}

export function GroupAnnouncementDialog({
  visible,
  group,
  canManage,
  initialId,
  onClose,
  onChanged,
}: Props) {
  const [mode, setMode] = useState<Mode>('list')
  const [list, setList] = useState<GroupAnnouncement[]>([])
  const [current, setCurrent] = useState<GroupAnnouncement | null>(null)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const ackingRef = useRef<string | null>(null)

  const load = async () => {
    try {
      const res = await api.listAnnouncements(group.id)
      setList(res.announcements || [])
      return res.announcements || []
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '加载公告失败'))
      return [] as GroupAnnouncement[]
    }
  }

  const markRead = async (a: GroupAnnouncement) => {
    if (a.acked || ackingRef.current === a.id) return
    ackingRef.current = a.id
    try {
      await api.ackAnnouncement(group.id, a.id)
      const items = await load()
      onChanged({
        pendingAnnouncement: nextPending(items),
        announcement: items[0]?.body || '',
        announcementCount: items.length,
      })
    } catch {
      /* ignore */
    } finally {
      if (ackingRef.current === a.id) ackingRef.current = null
    }
  }

  useEffect(() => {
    if (!visible) return
    setMode('list')
    setCurrent(null)
    setDraft('')
    setExpandedId(null)
    void (async () => {
      const items = await load()
      if (initialId) {
        const hit = items.find((a) => a.id === initialId)
        if (hit) {
          setExpandedId(hit.id)
          void markRead(hit)
        }
      }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, group.id, initialId])

  const openCreate = () => {
    setDraft('')
    setMode('create')
  }

  const openEdit = (a: GroupAnnouncement) => {
    setCurrent(a)
    setDraft(a.body)
    setMode('edit')
  }

  const toggleExpand = (a: GroupAnnouncement) => {
    const next = expandedId === a.id ? null : a.id
    setExpandedId(next)
    if (next) void markRead(a)
  }

  const publish = async () => {
    if (!draft.trim()) {
      MessagePlugin.warning('请填写公告内容')
      return
    }
    setBusy(true)
    try {
      if (mode === 'edit' && current) {
        const a = await api.updateAnnouncement(group.id, current.id, draft.trim())
        MessagePlugin.success('公告已更新')
        await load()
        setExpandedId(a.id)
        setMode('list')
        onChanged({ announcement: a.body })
      } else {
        const a = await api.createAnnouncement(group.id, draft.trim(), false)
        MessagePlugin.success('公告已发布')
        const items = await load()
        onChanged({
          announcement: a.body,
          announcementCount: items.length,
          pendingAnnouncement: null,
        })
        setExpandedId(a.id)
        setMode('list')
      }
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '发布失败'))
    } finally {
      setBusy(false)
    }
  }

  const remove = async (a: GroupAnnouncement) => {
    setBusy(true)
    try {
      await api.deleteAnnouncement(group.id, a.id)
      MessagePlugin.success('已删除公告')
      const items = await load()
      if (expandedId === a.id) setExpandedId(null)
      if (current?.id === a.id) setCurrent(null)
      onChanged({
        announcement: items[0]?.body || '',
        announcementCount: items.length,
        pendingAnnouncement: nextPending(items),
      })
      setMode('list')
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '删除失败'))
    } finally {
      setBusy(false)
    }
  }

  const confirmRemove = (a: GroupAnnouncement) => {
    if (window.confirm('确定删除这条群公告？')) void remove(a)
  }

  const header =
    mode === 'create' ? '发布群公告' : mode === 'edit' ? '编辑群公告' : '群公告'

  const footer =
    mode === 'list'
      ? canManage
        ? (
            <Button theme="primary" onClick={openCreate}>
              发布公告
            </Button>
          )
        : null
      : (
          <>
            <Button theme="default" onClick={() => setMode('list')}>
              取消
            </Button>
            <Button theme="primary" loading={busy} onClick={() => void publish()}>
              {mode === 'edit' ? '完成' : '发布'}
            </Button>
          </>
        )

  return (
    <Dialog
      visible={visible}
      header={header}
      onClose={onClose}
      width={460}
      className="im-ann-dialog"
      footer={footer}
      closeBtn
    >
      {mode === 'list' && (
        <div className="im-ann-list">
          {list.length === 0 ? (
            <p className="im-empty-hint">暂无群公告{canManage ? '，点击下方发布' : ''}</p>
          ) : (
            list.map((a) => {
              const open = expandedId === a.id
              return (
                <div
                  key={a.id}
                  className={`im-ann-list__row${open ? ' is-expanded' : ''}`}
                >
                  <button
                    type="button"
                    className="im-ann-list__main"
                    onClick={() => toggleExpand(a)}
                    aria-expanded={open}
                  >
                    <strong className={`im-ann-list__text${open ? ' is-open' : ''}`}>
                      {a.body}
                    </strong>
                    <span className="im-muted">
                      {a.authorName || '管理员'} · {new Date(a.createdAt).toLocaleString()}
                      {canManage ? ` · 已读 ${a.ackCount || 0}` : ''}
                    </span>
                  </button>
                  <ChevronRightIcon
                    size="16px"
                    className={`im-ann-list__chevron${open ? ' is-open' : ''}`}
                  />
                  {canManage && (
                    <div className="im-ann-list__actions">
                      <button
                        type="button"
                        className="im-ann-list__icon"
                        title="编辑"
                        aria-label="编辑公告"
                        onClick={() => openEdit(a)}
                      >
                        <Edit1Icon size="18px" />
                      </button>
                      <button
                        type="button"
                        className="im-ann-list__icon im-ann-list__icon--danger"
                        title="删除"
                        aria-label="删除公告"
                        disabled={busy}
                        onClick={() => confirmRemove(a)}
                      >
                        <DeleteIcon size="18px" />
                      </button>
                    </div>
                  )}
                </div>
              )
            })
          )}
        </div>
      )}

      {(mode === 'create' || mode === 'edit') && (
        <div className="im-announce-edit">
          <Textarea
            autofocus
            maxlength={1000}
            placeholder="填写群公告内容，发布后全员可见"
            value={draft}
            onChange={(v) => setDraft(String(v))}
            autosize={{ minRows: 8, maxRows: 16 }}
          />
        </div>
      )}
    </Dialog>
  )
}
