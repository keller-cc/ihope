import { useCallback, useEffect, useRef, useState } from 'react'
import { ChevronRightIcon, DeleteIcon, Edit1Icon } from 'tdesign-icons-react'
import { Button, Dialog, MessagePlugin, Textarea } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  type Conversation,
  type GroupAnnouncement,
} from '@/api'

const PAGE_SIZE = 20

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
  const [hasMore, setHasMore] = useState(false)
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [loadingMore, setLoadingMore] = useState(false)
  const [current, setCurrent] = useState<GroupAnnouncement | null>(null)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const ackingRef = useRef<string | null>(null)
  const listRef = useRef<HTMLDivElement | null>(null)
  const loadGen = useRef(0)

  const applyPage = useCallback(
    (
      items: GroupAnnouncement[],
      pageHasMore: boolean,
      pageTotal: number,
      append: boolean,
    ) => {
      setList((prev) => (append ? [...prev, ...items] : items))
      setHasMore(pageHasMore)
      setTotal(pageTotal)
    },
    [],
  )

  const loadFirst = useCallback(async () => {
    const gen = ++loadGen.current
    setLoading(true)
    try {
      const res = await api.listAnnouncements(group.id, { limit: PAGE_SIZE })
      if (gen !== loadGen.current) {
        return { items: [] as GroupAnnouncement[], total: 0 }
      }
      const items = res.announcements || []
      const pageTotal = res.total ?? items.length
      applyPage(items, !!res.hasMore, pageTotal, false)
      return { items, total: pageTotal }
    } catch (e) {
      if (gen === loadGen.current) {
        MessagePlugin.error(apiErrorMessage(e, '加载公告失败'))
        applyPage([], false, 0, false)
      }
      return { items: [] as GroupAnnouncement[], total: 0 }
    } finally {
      if (gen === loadGen.current) setLoading(false)
    }
  }, [applyPage, group.id])

  const loadMore = useCallback(async () => {
    if (!hasMore || loadingMore || loading) return
    const last = list[list.length - 1]
    if (!last) return
    setLoadingMore(true)
    const gen = loadGen.current
    try {
      const res = await api.listAnnouncements(group.id, {
        limit: PAGE_SIZE,
        before: last.createdAt,
      })
      if (gen !== loadGen.current) return
      applyPage(res.announcements || [], !!res.hasMore, res.total ?? total, true)
    } catch (e) {
      if (gen === loadGen.current) {
        MessagePlugin.error(apiErrorMessage(e, '加载更多失败'))
      }
    } finally {
      if (gen === loadGen.current) setLoadingMore(false)
    }
  }, [applyPage, group.id, hasMore, list, loading, loadingMore, total])

  const onListScroll = () => {
    const el = listRef.current
    if (!el || !hasMore || loadingMore) return
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 48) {
      void loadMore()
    }
  }

  useEffect(() => {
    if (!visible || mode !== 'list' || !hasMore || loading || loadingMore) return
    const el = listRef.current
    if (!el) return
    if (el.scrollHeight <= el.clientHeight + 8) {
      void loadMore()
    }
  }, [visible, mode, hasMore, loading, loadingMore, list.length, loadMore])

  const markRead = async (a: GroupAnnouncement) => {
    if (a.acked || ackingRef.current === a.id) return
    ackingRef.current = a.id
    try {
      const res = await api.ackAnnouncement(group.id, a.id)
      setList((prev) =>
        prev.map((x) => (x.id === a.id ? { ...x, acked: true, ackCount: (x.ackCount || 0) + 1 } : x)),
      )
      onChanged({
        pendingAnnouncement: res.nextPending ?? null,
        announcement: list[0]?.body || a.body,
        announcementCount: total || group.announcementCount,
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
    setHasMore(false)
    setTotal(0)
    void (async () => {
      const { items } = await loadFirst()
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
        setList((prev) => prev.map((x) => (x.id === a.id ? { ...x, ...a } : x)))
        setExpandedId(a.id)
        setMode('list')
        onChanged({ announcement: a.body })
      } else {
        const a = await api.createAnnouncement(group.id, draft.trim(), false)
        MessagePlugin.success('公告已发布')
        const { items, total: pageTotal } = await loadFirst()
        onChanged({
          announcement: a.body,
          announcementCount: pageTotal,
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
      if (expandedId === a.id) setExpandedId(null)
      if (current?.id === a.id) setCurrent(null)
      const { items, total: pageTotal } = await loadFirst()
      onChanged({
        announcement: items[0]?.body || '',
        announcementCount: pageTotal,
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
    mode === 'create' ? '新增群公告' : mode === 'edit' ? '编辑群公告' : '群公告'

  const footer =
    mode === 'list'
      ? canManage
        ? (
            <Button theme="primary" onClick={openCreate}>
              新增公告
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
        <div className="im-ann-list" ref={listRef} onScroll={onListScroll}>
          {loading && list.length === 0 ? (
            <p className="im-empty-hint">加载中…</p>
          ) : list.length === 0 ? (
            <p className="im-empty-hint">
              暂无群公告{canManage ? '，点击下方新增' : ''}
            </p>
          ) : (
            <>
              {list.map((a) => {
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
                        {a.authorName || '管理员'} ·{' '}
                        {new Date(a.createdAt).toLocaleString()}
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
              })}
              {loadingMore && <p className="im-ann-list__more">加载中…</p>}
              {!hasMore && list.length > 0 && total > PAGE_SIZE && (
                <p className="im-ann-list__more im-muted">没有更多了</p>
              )}
            </>
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
