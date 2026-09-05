import { useCallback, useEffect, useState } from 'react'
import {
  CalendarIcon,
  FolderOpenIcon,
  ImageIcon,
  SearchIcon,
  UsergroupIcon,
} from 'tdesign-icons-react'
import { Button, Input, Loading, MessagePlugin } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  type Contact,
  type Conversation,
  type Message,
  type MessageDay,
} from '../../api'
import {
  formatFileSize,
  formatMessageTimeDivider,
  parseFileBody,
  parseImageBody,
} from '../../lib/chatFormat'
import { Avatar } from '../Avatar'

export type HistoryView =
  | 'hub'
  | 'search'
  | 'media'
  | 'files'
  | 'days'
  | 'day'
  | 'members'
  | 'member'

export type HistoryCache = {
  view: HistoryView
  query: string
  day?: string
  senderId?: string
  senderName?: string
}

type Props = {
  conversation: Conversation
  members?: Contact[]
  cache: HistoryCache
  onCacheChange: (c: HistoryCache) => void
  onJump: (messageId: string) => void
  onClose: () => void
}

const emptyCache = (): HistoryCache => ({ view: 'hub', query: '' })

export function defaultHistoryCache(): HistoryCache {
  return emptyCache()
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
  const setView = (view: HistoryView, patch?: Partial<HistoryCache>) => {
    onCacheChange({ ...cache, view, ...patch })
  }

  const title =
    cache.view === 'hub' || cache.view === 'search'
      ? '查找聊天记录'
      : cache.view === 'media'
        ? '图片与视频'
        : cache.view === 'files'
          ? '文件'
          : cache.view === 'days' || cache.view === 'day'
            ? '按日期查找'
            : cache.view === 'members' || cache.view === 'member'
              ? '按群成员查找'
              : '查找聊天记录'

  const canBack = cache.view !== 'hub'

  return (
    <section className="im-pane im-pane--settings">
      <header className="im-chat-head">
        <button
          type="button"
          className="im-back"
          style={{ display: 'grid' }}
          onClick={() => {
            if (!canBack) {
              onClose()
              return
            }
            if (cache.view === 'day') setView('days')
            else if (cache.view === 'member') setView('members')
            else if (cache.view === 'search') {
              onCacheChange({ ...cache, view: 'hub', query: '' })
            } else setView('hub')
          }}
        >
          ‹
        </button>
        <h2 className="im-chat-head__title">{title}</h2>
      </header>

      <div className="im-history-body">
        {(cache.view === 'hub' || cache.view === 'search') && (
          <div className="im-history-hub">
            <form
              className="im-history-qq-search"
              onSubmit={(e) => {
                e.preventDefault()
                const q = cache.query.trim()
                if (!q) return
                setView('search', { query: cache.query })
              }}
            >
              <SearchIcon size="18px" className="im-history-qq-search__ico" />
              <Input
                className="im-history-qq-search__input"
                borderless
                value={cache.query}
                placeholder="搜索"
                clearable
                onChange={(v) => {
                  const query = String(v)
                  onCacheChange({
                    ...cache,
                    query,
                    view: query.trim() ? 'search' : 'hub',
                  })
                }}
                onFocus={() => {
                  if (cache.query.trim()) setView('search')
                }}
              />
            </form>

            {cache.view === 'hub' && (
              <div className="im-history-qq-cats" role="navigation" aria-label="分类查找">
                <button type="button" className="im-history-qq-cat" onClick={() => setView('days')}>
                  <span className="im-history-qq-cat__ico im-history-qq-cat__ico--date">
                    <CalendarIcon size="22px" />
                  </span>
                  <em>日期</em>
                </button>
                <button type="button" className="im-history-qq-cat" onClick={() => setView('media')}>
                  <span className="im-history-qq-cat__ico im-history-qq-cat__ico--img">
                    <ImageIcon size="22px" />
                  </span>
                  <em>图片与视频</em>
                </button>
                <button type="button" className="im-history-qq-cat" onClick={() => setView('files')}>
                  <span className="im-history-qq-cat__ico im-history-qq-cat__ico--file">
                    <FolderOpenIcon size="22px" />
                  </span>
                  <em>文件</em>
                </button>
                {isGroup && (
                  <button
                    type="button"
                    className="im-history-qq-cat"
                    onClick={() => setView('members')}
                  >
                    <span className="im-history-qq-cat__ico im-history-qq-cat__ico--member">
                      <UsergroupIcon size="22px" />
                    </span>
                    <em>群成员</em>
                  </button>
                )}
              </div>
            )}

            {cache.view === 'search' && (
              <SearchResults
                conversationId={conversation.id}
                query={cache.query}
                onQuery={(query) =>
                  onCacheChange({
                    ...cache,
                    query,
                    view: query.trim() ? 'search' : 'hub',
                  })
                }
                onJump={onJump}
                embedded
              />
            )}
          </div>
        )}

        {cache.view === 'media' && (
          <MediaGrid conversationId={conversation.id} onJump={onJump} />
        )}
        {cache.view === 'files' && (
          <FileList conversationId={conversation.id} onJump={onJump} />
        )}
        {cache.view === 'days' && (
          <DaysList
            conversationId={conversation.id}
            onPick={(day) => setView('day', { day })}
          />
        )}
        {cache.view === 'day' && cache.day && (
          <FilteredMessages
            conversationId={conversation.id}
            day={cache.day}
            onJump={onJump}
          />
        )}
        {cache.view === 'members' && (
          <MembersList
            members={members}
            onPick={(m) =>
              setView('member', { senderId: m.id, senderName: m.remark || m.username })
            }
          />
        )}
        {cache.view === 'member' && cache.senderId && (
          <FilteredMessages
            conversationId={conversation.id}
            senderId={cache.senderId}
            titleHint={cache.senderName}
            onJump={onJump}
          />
        )}
      </div>
    </section>
  )
}

function SearchResults({
  conversationId,
  query,
  onQuery,
  onJump,
  embedded,
}: {
  conversationId: string
  query: string
  onQuery: (q: string) => void
  onJump: (id: string) => void
  embedded?: boolean
}) {
  const [busy, setBusy] = useState(false)
  const [list, setList] = useState<Message[]>([])
  const [hasMore, setHasMore] = useState(false)
  const [searched, setSearched] = useState(false)

  const run = useCallback(
    async (q: string, before?: string, append = false) => {
      const trimmed = q.trim()
      if (!trimmed) {
        setList([])
        setHasMore(false)
        setSearched(false)
        return
      }
      setBusy(true)
      try {
        const res = await api.searchMessages(conversationId, trimmed, before)
        setList((prev) => (append ? [...prev, ...res.messages] : res.messages))
        setHasMore(res.hasMore)
        setSearched(true)
      } catch (e) {
        MessagePlugin.error(apiErrorMessage(e, '搜索失败'))
      } finally {
        setBusy(false)
      }
    },
    [conversationId],
  )

  useEffect(() => {
    const t = window.setTimeout(() => {
      void run(query)
    }, 280)
    return () => window.clearTimeout(t)
  }, [query, conversationId, run])

  return (
    <div className={embedded ? 'im-history-search im-history-search--embed' : 'im-history-search'}>
      {!embedded && (
        <form
          className="im-history-search__bar"
          onSubmit={(e) => {
            e.preventDefault()
            void run(query)
          }}
        >
          <Input
            value={query}
            placeholder="搜索"
            clearable
            onChange={(v) => onQuery(String(v))}
          />
          <Button theme="primary" loading={busy} type="submit">
            搜索
          </Button>
        </form>
      )}
      {busy && !list.length ? (
        <div className="im-history-empty">
          <Loading />
        </div>
      ) : searched && !list.length ? (
        <p className="im-history-empty">无搜索结果</p>
      ) : !searched && !query.trim() ? (
        <p className="im-history-empty">输入关键词搜索聊天内容</p>
      ) : (
        <div className="im-history-results">
          {list.map((m) => (
            <button
              key={m.id}
              type="button"
              className="im-history-result im-history-result--qq"
              onClick={() => onJump(m.id)}
            >
              <Avatar name={m.senderUsername || '?'} src={m.senderAvatarUrl} size="sm" />
              <span className="im-history-result__main">
                <span className="im-history-result__top">
                  <strong>{m.senderUsername || '成员'}</strong>
                  <span>{formatMessageTimeDivider(m.createdAt)}</span>
                </span>
                <span className="im-history-result__body">
                  {m.type === 'image'
                    ? '[图片]'
                    : m.type === 'file'
                      ? `[文件] ${parseFileBody(m.body)?.name || ''}`
                      : m.type === 'forward'
                        ? '[聊天记录]'
                        : highlight(m.body, query)}
                </span>
              </span>
            </button>
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
      )}
    </div>
  )
}

function highlight(text: string, q: string) {
  const query = q.trim()
  if (!query) return text
  const lower = text.toLowerCase()
  const qi = lower.indexOf(query.toLowerCase())
  if (qi < 0) return text
  return (
    <>
      {text.slice(0, qi)}
      <em className="im-history-hit">{text.slice(qi, qi + query.length)}</em>
      {text.slice(qi + query.length)}
    </>
  )
}

function MediaGrid({
  conversationId,
  onJump,
}: {
  conversationId: string
  onJump: (id: string) => void
}) {
  const [list, setList] = useState<Message[]>([])
  const [hasMore, setHasMore] = useState(false)
  const [busy, setBusy] = useState(true)

  const load = useCallback(
    async (before?: string, append = false) => {
      setBusy(true)
      try {
        const res = await api.searchMessages(conversationId, undefined, before, {
          type: 'image',
        })
        setList((prev) => (append ? [...prev, ...res.messages] : res.messages))
        setHasMore(res.hasMore)
      } catch (e) {
        MessagePlugin.error(apiErrorMessage(e, '加载失败'))
      } finally {
        setBusy(false)
      }
    },
    [conversationId],
  )

  useEffect(() => {
    void load()
  }, [load])

  if (busy && !list.length) return <Loading />
  if (!list.length)
    return (
      <p className="im-history-empty">暂无图片</p>
    )
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
  onJump,
}: {
  conversationId: string
  onJump: (id: string) => void
}) {
  const [list, setList] = useState<Message[]>([])
  const [hasMore, setHasMore] = useState(false)
  const [busy, setBusy] = useState(true)

  const load = useCallback(
    async (before?: string, append = false) => {
      setBusy(true)
      try {
        const res = await api.searchMessages(conversationId, undefined, before, {
          type: 'file',
        })
        setList((prev) => (append ? [...prev, ...res.messages] : res.messages))
        setHasMore(res.hasMore)
      } catch (e) {
        MessagePlugin.error(apiErrorMessage(e, '加载失败'))
      } finally {
        setBusy(false)
      }
    },
    [conversationId],
  )

  useEffect(() => {
    void load()
  }, [load])

  if (busy && !list.length) return <Loading />
  if (!list.length)
    return (
      <p className="im-history-empty">暂无文件</p>
    )
  return (
    <div className="im-history-results">
      {list.map((m) => {
        const f = parseFileBody(m.body)
        return (
          <button
            key={m.id}
            type="button"
            className="im-history-result im-history-result--qq"
            onClick={() => onJump(m.id)}
          >
            <Avatar name={m.senderUsername || '?'} src={m.senderAvatarUrl} size="sm" />
            <span className="im-history-result__main">
              <span className="im-history-result__top">
                <strong>{m.senderUsername || '成员'}</strong>
                <span>{formatMessageTimeDivider(m.createdAt)}</span>
              </span>
              <span className="im-history-result__body">
                {f?.name || '文件'}
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

function DaysList({
  conversationId,
  onPick,
}: {
  conversationId: string
  onPick: (day: string) => void
}) {
  const [days, setDays] = useState<MessageDay[]>([])
  const [busy, setBusy] = useState(true)

  useEffect(() => {
    void api
      .listMessageDays(conversationId)
      .then((r) => setDays(r.days))
      .catch((e) => MessagePlugin.error(apiErrorMessage(e, '加载失败')))
      .finally(() => setBusy(false))
  }, [conversationId])

  if (busy) return <Loading />
  if (!days.length)
    return (
      <p className="im-history-empty">暂无记录</p>
    )
  return (
    <div className="im-history-results">
      {days.map((d) => (
        <button
          key={d.day}
          type="button"
          className="im-history-result"
          onClick={() => onPick(d.day)}
        >
          <div className="im-history-result__top">
            <strong>{d.day}</strong>
            <span>{d.count} 条</span>
          </div>
        </button>
      ))}
    </div>
  )
}

function MembersList({
  members,
  onPick,
}: {
  members: Contact[]
  onPick: (m: Contact) => void
}) {
  if (!members.length)
    return (
      <p className="im-history-empty">暂无成员</p>
    )
  return (
    <div className="im-history-results">
      {members.map((m) => (
        <button
          key={m.id}
          type="button"
          className="im-history-result im-history-result--member"
          onClick={() => onPick(m)}
        >
          <Avatar name={m.username} src={m.avatarUrl} size="sm" />
          <span>{m.remark?.trim() || m.username}</span>
        </button>
      ))}
    </div>
  )
}

function FilteredMessages({
  conversationId,
  day,
  senderId,
  titleHint,
  onJump,
}: {
  conversationId: string
  day?: string
  senderId?: string
  titleHint?: string
  onJump: (id: string) => void
}) {
  const [list, setList] = useState<Message[]>([])
  const [hasMore, setHasMore] = useState(false)
  const [busy, setBusy] = useState(true)

  const load = useCallback(
    async (before?: string, append = false) => {
      setBusy(true)
      try {
        const res = await api.searchMessages(conversationId, undefined, before, {
          day,
          senderId,
        })
        setList((prev) => (append ? [...prev, ...res.messages] : res.messages))
        setHasMore(res.hasMore)
      } catch (e) {
        MessagePlugin.error(apiErrorMessage(e, '加载失败'))
      } finally {
        setBusy(false)
      }
    },
    [conversationId, day, senderId],
  )

  useEffect(() => {
    void load()
  }, [load])

  if (busy && !list.length) return <Loading />
  if (!list.length)
    return (
      <p className="im-history-empty">
        {titleHint ? `暂无「${titleHint}」的消息` : '暂无消息'}
      </p>
    )
  return (
    <div className="im-history-results">
      {list.map((m) => (
        <button
          key={m.id}
          type="button"
          className="im-history-result im-history-result--qq"
          onClick={() => onJump(m.id)}
        >
          <Avatar name={m.senderUsername || '?'} src={m.senderAvatarUrl} size="sm" />
          <span className="im-history-result__main">
            <span className="im-history-result__top">
              <strong>{m.senderUsername || '成员'}</strong>
              <span>{formatMessageTimeDivider(m.createdAt)}</span>
            </span>
            <span className="im-history-result__body">
              {m.type === 'image'
                ? '[图片]'
                : m.type === 'file'
                  ? `[文件] ${parseFileBody(m.body)?.name || ''}`
                  : m.type === 'forward'
                    ? '[聊天记录]'
                    : m.body}
            </span>
          </span>
        </button>
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
