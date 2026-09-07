import { useCallback, useEffect, useMemo, useState } from 'react'
import { Button, Checkbox, Input, Loading, MessagePlugin } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  type Contact,
  type Conversation,
  type Message,
  type MessageDay,
} from '@/api'
import {
  formatFileSize,
  formatMessageTimeDivider,
  formatVoiceDuration,
  parseFileBody,
  parseImageBody,
  parseVoiceBody,
} from '@/lib/chatFormat'
import { Avatar } from '@/components/Avatar'

export type HistoryTab = 'all' | 'media' | 'files'

export type HistoryCache = {
  tab: HistoryTab
  query: string
  day?: string
  senderIds?: string[]
}

/** 筛选抽屉内页：菜单 / 日期 / 群成员 */
type FilterView = 'menu' | 'date' | 'members'

type Props = {
  conversation: Conversation
  members?: Contact[]
  cache: HistoryCache
  onCacheChange: (c: HistoryCache) => void
  onJump: (messageId: string) => void
  onClose: () => void
}

export function defaultHistoryCache(): HistoryCache {
  return { tab: 'all', query: '', senderIds: [] }
}

function FilterFunnelIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden fill="none">
      <path
        d="M4 5.5h16l-6.2 7.4v4.6L10.2 19v-6.1L4 5.5z"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export function ChatHistoryPanel({
  conversation,
  members = [],
  cache,
  onCacheChange,
  onJump,
  onClose,
}: Props) {
  const isGroup = conversation.type === 'group'
  const senderIds = cache.senderIds || []
  const hasFilters = Boolean(cache.day || senderIds.length)
  const searching = cache.query.trim().length > 0
  const [filterView, setFilterView] = useState<FilterView | null>(null)

  const patch = (p: Partial<HistoryCache>) => onCacheChange({ ...cache, ...p })

  const memberLabel = useMemo(() => {
    if (!senderIds.length) return '不限'
    if (senderIds.length === 1) {
      const m = members.find((x) => x.id === senderIds[0])
      return m ? m.remark?.trim() || m.username : '1人'
    }
    return `已选 ${senderIds.length} 人`
  }, [senderIds, members])

  const tabs: { id: HistoryTab; label: string }[] = [
    { id: 'all', label: '全部' },
    { id: 'media', label: '图片与视频' },
    { id: 'files', label: '文件' },
  ]

  const closeFilter = () => setFilterView(null)

  return (
    <section className="im-pane im-pane--settings im-history">
      <header className="im-chat-head">
        <button type="button" className="im-back" style={{ display: 'grid' }} onClick={onClose}>
          ‹
        </button>
        <h2 className="im-chat-head__title">查找聊天记录</h2>
      </header>

      <div className="im-history-toolbar">
        <div className="im-history-searchbar">
          <span className="im-history-searchbar__ico" aria-hidden>
            ⌕
          </span>
          <Input
            className="im-history-searchbar__input"
            borderless
            value={cache.query}
            placeholder="搜索"
            clearable
            onChange={(v) => patch({ query: String(v) })}
          />
        </div>

        <div className="im-history-tabs-row">
          <nav className="im-history-tabs" aria-label="分类">
            {tabs.map((t) => (
              <button
                key={t.id}
                type="button"
                className={cache.tab === t.id ? 'im-history-tab im-history-tab--on' : 'im-history-tab'}
                onClick={() => patch({ tab: t.id })}
              >
                {t.label}
              </button>
            ))}
          </nav>
          <button
            type="button"
            className={
              hasFilters || filterView
                ? 'im-history-filter-btn is-on'
                : 'im-history-filter-btn'
            }
            title="筛选"
            aria-label="筛选"
            aria-expanded={filterView != null}
            onClick={() => setFilterView(filterView ? null : 'menu')}
          >
            <FilterFunnelIcon />
            {hasFilters && <span className="im-history-filter-btn__dot" />}
          </button>
        </div>
      </div>

      <div className="im-history-body">
        {searching ? (
          <SearchResults
            conversationId={conversation.id}
            query={cache.query}
            day={cache.day}
            senderIds={senderIds}
            onJump={onJump}
          />
        ) : cache.tab === 'media' ? (
          <MediaGrid
            conversationId={conversation.id}
            day={cache.day}
            senderIds={senderIds}
            onJump={onJump}
          />
        ) : cache.tab === 'files' ? (
          <FileList
            conversationId={conversation.id}
            day={cache.day}
            senderIds={senderIds}
            onJump={onJump}
          />
        ) : hasFilters ? (
          <FilteredMessages
            conversationId={conversation.id}
            day={cache.day}
            senderIds={senderIds}
            onJump={onJump}
          />
        ) : (
          <p className="im-history-hint">输入关键词搜索，或点筛选按日期 / 成员查找</p>
        )}

        {filterView && (
          <div className="im-history-filter-layer">
            <button
              type="button"
              className="im-history-filter-mask"
              aria-label="关闭筛选"
              onClick={closeFilter}
            />
            <aside className="im-history-filter-drawer" role="dialog" aria-label="筛选">
              <header className="im-history-filter-drawer__head">
                {filterView !== 'menu' ? (
                  <button
                    type="button"
                    className="im-history-filter-drawer__back"
                    onClick={() => setFilterView('menu')}
                  >
                    ‹
                  </button>
                ) : (
                  <span className="im-history-filter-drawer__back-spacer" />
                )}
                <h3>
                  {filterView === 'date'
                    ? '选择日期'
                    : filterView === 'members'
                      ? '选择群成员'
                      : '筛选'}
                </h3>
                <button
                  type="button"
                  className="im-history-filter-drawer__close"
                  onClick={closeFilter}
                >
                  ×
                </button>
              </header>

              <div className="im-history-filter-drawer__body">
                {filterView === 'menu' && (
                  <div className="im-history-filter-menu">
                    <button
                      type="button"
                      className="im-history-filter-menu__row"
                      onClick={() => setFilterView('date')}
                    >
                      <span>日期</span>
                      <span className="im-history-filter-menu__val">
                        {cache.day || '不限'}
                        <span aria-hidden>›</span>
                      </span>
                    </button>
                    {isGroup && (
                      <button
                        type="button"
                        className="im-history-filter-menu__row"
                        onClick={() => setFilterView('members')}
                      >
                        <span>群成员</span>
                        <span className="im-history-filter-menu__val">
                          {memberLabel}
                          <span aria-hidden>›</span>
                        </span>
                      </button>
                    )}
                    {hasFilters && (
                      <button
                        type="button"
                        className="im-history-filter-menu__reset"
                        onClick={() => {
                          patch({ day: undefined, senderIds: [] })
                          closeFilter()
                        }}
                      >
                        重置筛选
                      </button>
                    )}
                  </div>
                )}
                {filterView === 'date' && (
                  <DatePicker
                    conversationId={conversation.id}
                    selected={cache.day}
                    onPick={(day) => {
                      patch({ day })
                      closeFilter()
                    }}
                    onCancel={() => setFilterView('menu')}
                  />
                )}
                {filterView === 'members' && (
                  <MemberMultiSelect
                    members={members}
                    selected={senderIds}
                    onConfirm={(ids) => {
                      patch({ senderIds: ids })
                      closeFilter()
                    }}
                    onCancel={() => setFilterView('menu')}
                  />
                )}
              </div>
            </aside>
          </div>
        )}
      </div>
    </section>
  )
}

function SearchResults({
  conversationId,
  query,
  day,
  senderIds,
  onJump,
}: {
  conversationId: string
  query: string
  day?: string
  senderIds: string[]
  onJump: (id: string) => void
}) {
  const [busy, setBusy] = useState(false)
  const [list, setList] = useState<Message[]>([])
  const [hasMore, setHasMore] = useState(false)

  const run = useCallback(
    async (q: string, before?: string, append = false) => {
      const trimmed = q.trim()
      if (!trimmed) {
        setList([])
        setHasMore(false)
        return
      }
      setBusy(true)
      try {
        const res = await api.searchMessages(conversationId, trimmed, before, {
          day,
          senderIds: senderIds.length ? senderIds : undefined,
        })
        setList((prev) => (append ? [...prev, ...res.messages] : res.messages))
        setHasMore(res.hasMore)
      } catch (e) {
        MessagePlugin.error(apiErrorMessage(e, '搜索失败'))
      } finally {
        setBusy(false)
      }
    },
    [conversationId, day, senderIds],
  )

  useEffect(() => {
    const t = window.setTimeout(() => void run(query), 280)
    return () => window.clearTimeout(t)
  }, [query, run])

  if (busy && !list.length) return <Loading />
  if (!list.length) return <p className="im-history-empty">无搜索结果</p>

  return (
    <div className="im-history-results">
      {list.map((m) => (
        <ResultRow key={m.id} m={m} query={query} onJump={onJump} />
      ))}
      {hasMore && (
        <Button
          variant="text"
          block
          loading={busy}
          onClick={() => {
            const last = list[list.length - 1]
            if (last) void run(query, last.createdAt, true)
          }}
        >
          加载更多
        </Button>
      )}
    </div>
  )
}

function ResultRow({
  m,
  query,
  onJump,
}: {
  m: Message
  query?: string
  onJump: (id: string) => void
}) {
  const voice = m.type === 'voice' ? parseVoiceBody(m.body) : null
  const body =
    m.type === 'image'
      ? '[图片]'
      : m.type === 'file'
        ? `[文件] ${parseFileBody(m.body)?.name || ''}`
        : voice
          ? `[语音] ${formatVoiceDuration(voice.duration)}`
          : m.type === 'forward'
            ? '[聊天记录]'
            : m.body

  return (
    <button type="button" className="im-history-row" onClick={() => onJump(m.id)}>
      <Avatar name={m.senderUsername || '?'} src={m.senderAvatarUrl} size="sm" />
      <span className="im-history-row__main">
        <span className="im-history-row__top">
          <strong>{m.senderUsername || '成员'}</strong>
          <time>{formatMessageTimeDivider(m.createdAt)}</time>
        </span>
        <span className="im-history-row__body">
          {query && m.type === 'text' ? highlight(body, query) : body}
        </span>
      </span>
    </button>
  )
}

function highlight(text: string, query: string) {
  const q = query.trim()
  if (!q) return text
  const i = text.toLowerCase().indexOf(q.toLowerCase())
  if (i < 0) return text
  return (
    <>
      {text.slice(0, i)}
      <em className="im-history-hit">{text.slice(i, i + q.length)}</em>
      {text.slice(i + q.length)}
    </>
  )
}

function MediaGrid({
  conversationId,
  day,
  senderIds,
  onJump,
}: {
  conversationId: string
  day?: string
  senderIds: string[]
  onJump: (id: string) => void
}) {
  const [list, setList] = useState<Message[]>([])
  const [hasMore, setHasMore] = useState(false)
  const [busy, setBusy] = useState(true)

  const load = useCallback(
    async (before?: string, append = false) => {
      setBusy(true)
      try {
        const res = await api.listMessages(conversationId, {
          before,
          type: 'image',
          day,
          senderIds: senderIds.length ? senderIds : undefined,
        })
        setList((prev) => (append ? [...prev, ...res.messages] : res.messages))
        setHasMore(res.hasMore)
      } catch (e) {
        MessagePlugin.error(apiErrorMessage(e, '加载失败'))
      } finally {
        setBusy(false)
      }
    },
    [conversationId, day, senderIds],
  )

  useEffect(() => {
    void load()
  }, [load])

  if (busy && !list.length) return <Loading />
  if (!list.length) return <p className="im-history-empty">暂无图片</p>

  return (
    <div className="im-history-media">
      <div className="im-history-media__grid">
        {list.map((m) => {
          const img = parseImageBody(m.body)
          if (!img) return null
          return (
            <button
              key={m.id}
              type="button"
              className="im-history-media__item"
              onClick={() => onJump(m.id)}
            >
              <img src={img.thumbUrl} alt="" loading="lazy" />
            </button>
          )
        })}
      </div>
      {hasMore && (
        <Button
          variant="text"
          block
          loading={busy}
          onClick={() => {
            const last = list[list.length - 1]
            if (last) void load(last.createdAt, true)
          }}
        >
          加载更多
        </Button>
      )}
    </div>
  )
}

function FileList({
  conversationId,
  day,
  senderIds,
  onJump,
}: {
  conversationId: string
  day?: string
  senderIds: string[]
  onJump: (id: string) => void
}) {
  const [list, setList] = useState<Message[]>([])
  const [hasMore, setHasMore] = useState(false)
  const [busy, setBusy] = useState(true)

  const load = useCallback(
    async (before?: string, append = false) => {
      setBusy(true)
      try {
        const res = await api.listMessages(conversationId, {
          before,
          type: 'file',
          day,
          senderIds: senderIds.length ? senderIds : undefined,
        })
        setList((prev) => (append ? [...prev, ...res.messages] : res.messages))
        setHasMore(res.hasMore)
      } catch (e) {
        MessagePlugin.error(apiErrorMessage(e, '加载失败'))
      } finally {
        setBusy(false)
      }
    },
    [conversationId, day, senderIds],
  )

  useEffect(() => {
    void load()
  }, [load])

  if (busy && !list.length) return <Loading />
  if (!list.length) return <p className="im-history-empty">暂无文件</p>

  return (
    <div className="im-history-results">
      {list.map((m) => {
        const f = parseFileBody(m.body)
        return (
          <button
            key={m.id}
            type="button"
            className="im-history-row"
            onClick={() => onJump(m.id)}
          >
            <Avatar name={m.senderUsername || '?'} src={m.senderAvatarUrl} size="sm" />
            <span className="im-history-row__main">
              <span className="im-history-row__top">
                <strong>{f?.name || '文件'}</strong>
                <time>{formatMessageTimeDivider(m.createdAt)}</time>
              </span>
              <span className="im-history-row__body">
                {m.senderUsername || ''}
                {f?.size != null ? ` · ${formatFileSize(f.size)}` : ''}
              </span>
            </span>
          </button>
        )
      })}
      {hasMore && (
        <Button
          variant="text"
          block
          loading={busy}
          onClick={() => {
            const last = list[list.length - 1]
            if (last) void load(last.createdAt, true)
          }}
        >
          加载更多
        </Button>
      )}
    </div>
  )
}

function DatePicker({
  conversationId,
  selected,
  onPick,
  onCancel,
}: {
  conversationId: string
  selected?: string
  onPick: (day: string) => void
  onCancel: () => void
}) {
  const now = new Date()
  const [days, setDays] = useState<MessageDay[]>([])
  const [busy, setBusy] = useState(true)
  const [year, setYear] = useState(() =>
    selected ? Number(selected.slice(0, 4)) : now.getFullYear(),
  )
  const [month, setMonth] = useState(() =>
    selected ? Number(selected.slice(5, 7)) : now.getMonth() + 1,
  )
  const [picker, setPicker] = useState<null | 'year' | 'month'>(null)
  const [yearPage, setYearPage] = useState(() => Math.floor(year / 12) * 12)

  useEffect(() => {
    void api
      .listMessageDays(conversationId)
      .then((r) => setDays(r.days))
      .catch((e) => MessagePlugin.error(apiErrorMessage(e, '加载失败')))
      .finally(() => setBusy(false))
  }, [conversationId])

  const countByDay = useMemo(() => {
    const map = new Map<string, number>()
    for (const d of days) map.set(d.day, d.count)
    return map
  }, [days])

  if (busy) return <Loading />

  const first = new Date(year, month - 1, 1)
  const startPad = (first.getDay() + 6) % 7
  const daysInMonth = new Date(year, month, 0).getDate()
  const cells: (number | null)[] = []
  for (let i = 0; i < startPad; i++) cells.push(null)
  for (let d = 1; d <= daysInMonth; d++) cells.push(d)
  const todayKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`

  if (picker === 'year') {
    const years = Array.from({ length: 12 }, (_, i) => yearPage + i)
    return (
      <div className="im-history-cal">
        <div className="im-history-cal__head">
          <button type="button" className="im-history-cal__nav" onClick={() => setYearPage((p) => p - 12)}>
            ‹
          </button>
          <strong>
            {yearPage} – {yearPage + 11}
          </strong>
          <button type="button" className="im-history-cal__nav" onClick={() => setYearPage((p) => p + 12)}>
            ›
          </button>
        </div>
        <div className="im-history-cal__pick-grid">
          {years.map((y) => (
            <button
              key={y}
              type="button"
              className={y === year ? 'im-history-cal__pick is-on' : 'im-history-cal__pick'}
              onClick={() => {
                setYear(y)
                setPicker('month')
              }}
            >
              {y}
            </button>
          ))}
        </div>
        <button type="button" className="im-history-cal__cancel" onClick={() => setPicker(null)}>
          返回
        </button>
      </div>
    )
  }

  if (picker === 'month') {
    return (
      <div className="im-history-cal">
        <div className="im-history-cal__head">
          <button
            type="button"
            className="im-history-cal__nav"
            onClick={() => {
              setYearPage(Math.floor(year / 12) * 12)
              setPicker('year')
            }}
          >
            ‹
          </button>
          <button
            type="button"
            className="im-history-cal__title"
            onClick={() => {
              setYearPage(Math.floor(year / 12) * 12)
              setPicker('year')
            }}
          >
            {year}年
          </button>
          <span className="im-history-cal__nav" />
        </div>
        <div className="im-history-cal__pick-grid">
          {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => (
            <button
              key={m}
              type="button"
              className={m === month ? 'im-history-cal__pick is-on' : 'im-history-cal__pick'}
              onClick={() => {
                setMonth(m)
                setPicker(null)
              }}
            >
              {m}月
            </button>
          ))}
        </div>
        <button type="button" className="im-history-cal__cancel" onClick={() => setPicker(null)}>
          返回
        </button>
      </div>
    )
  }

  return (
    <div className="im-history-cal">
      <div className="im-history-cal__head">
        <button
          type="button"
          className="im-history-cal__nav"
          onClick={() => {
            if (month === 1) {
              setYear((y) => y - 1)
              setMonth(12)
            } else setMonth((m) => m - 1)
          }}
        >
          ‹
        </button>
        <div className="im-history-cal__titles">
          <button
            type="button"
            className="im-history-cal__title"
            onClick={() => {
              setYearPage(Math.floor(year / 12) * 12)
              setPicker('year')
            }}
          >
            {year}年
          </button>
          <button type="button" className="im-history-cal__title" onClick={() => setPicker('month')}>
            {month}月
          </button>
        </div>
        <button
          type="button"
          className="im-history-cal__nav"
          onClick={() => {
            if (month === 12) {
              setYear((y) => y + 1)
              setMonth(1)
            } else setMonth((m) => m + 1)
          }}
        >
          ›
        </button>
      </div>
      <div className="im-history-cal__week">
        {['一', '二', '三', '四', '五', '六', '日'].map((w) => (
          <span key={w}>{w}</span>
        ))}
      </div>
      <div className="im-history-cal__grid">
        {cells.map((d, i) => {
          if (d == null) return <span key={`e${i}`} className="im-history-cal__cell" />
          const key = `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`
          const count = countByDay.get(key) || 0
          return (
            <button
              key={key}
              type="button"
              disabled={!count}
              className={[
                'im-history-cal__cell',
                'im-history-cal__day',
                count ? 'im-history-cal__day--has' : '',
                key === todayKey ? 'im-history-cal__day--today' : '',
                key === selected ? 'im-history-cal__day--sel' : '',
              ]
                .filter(Boolean)
                .join(' ')}
              onClick={() => onPick(key)}
              title={count ? `${count} 条` : undefined}
            >
              {d}
            </button>
          )
        })}
      </div>
      <button type="button" className="im-history-cal__cancel" onClick={onCancel}>
        取消
      </button>
    </div>
  )
}

function MemberMultiSelect({
  members,
  selected,
  onConfirm,
  onCancel,
}: {
  members: Contact[]
  selected: string[]
  onConfirm: (ids: string[]) => void
  onCancel: () => void
}) {
  const [ids, setIds] = useState<string[]>(selected)

  if (!members.length) return <p className="im-history-empty">暂无成员</p>

  const toggle = (id: string) => {
    setIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]))
  }

  return (
    <div className="im-history-member-pick">
      <div className="im-history-results">
        {members.map((m) => {
          const on = ids.includes(m.id)
          return (
            <button
              key={m.id}
              type="button"
              className="im-history-row im-history-row--member"
              onClick={() => toggle(m.id)}
            >
              <Checkbox checked={on} />
              <Avatar name={m.username} src={m.avatarUrl} size="sm" />
              <span className="im-history-row__main">
                <span className="im-history-row__top">
                  <strong>{m.remark?.trim() || m.username}</strong>
                </span>
              </span>
            </button>
          )
        })}
      </div>
      <div className="im-history-member-pick__bar">
        <Button variant="text" onClick={onCancel}>
          取消
        </Button>
        <Button theme="primary" onClick={() => onConfirm(ids)}>
          完成{ids.length ? `（${ids.length}）` : ''}
        </Button>
      </div>
    </div>
  )
}

function FilteredMessages({
  conversationId,
  day,
  senderIds,
  onJump,
}: {
  conversationId: string
  day?: string
  senderIds: string[]
  onJump: (id: string) => void
}) {
  const [list, setList] = useState<Message[]>([])
  const [hasMore, setHasMore] = useState(false)
  const [busy, setBusy] = useState(true)

  const load = useCallback(
    async (before?: string, append = false) => {
      setBusy(true)
      try {
        const res = await api.listMessages(conversationId, {
          before,
          day,
          senderIds: senderIds.length ? senderIds : undefined,
        })
        setList((prev) => (append ? [...prev, ...res.messages] : res.messages))
        setHasMore(res.hasMore)
      } catch (e) {
        MessagePlugin.error(apiErrorMessage(e, '加载失败'))
      } finally {
        setBusy(false)
      }
    },
    [conversationId, day, senderIds],
  )

  useEffect(() => {
    void load()
  }, [load])

  if (busy && !list.length) return <Loading />
  if (!list.length) return <p className="im-history-empty">暂无消息</p>

  return (
    <div className="im-history-results">
      {list.map((m) => (
        <ResultRow key={m.id} m={m} onJump={onJump} />
      ))}
      {hasMore && (
        <Button
          variant="text"
          block
          loading={busy}
          onClick={() => {
            const last = list[list.length - 1]
            if (last) void load(last.createdAt, true)
          }}
        >
          加载更多
        </Button>
      )}
    </div>
  )
}
