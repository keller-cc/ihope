import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { MessagePlugin } from 'tdesign-react'
import { api, type Contact, type Conversation, type User } from '@/api'
import {
  buildMentionSendOpts,
  filterMentionOptions,
  insertMentionAt,
  mentionTriggerAt,
  type MentionOption,
  type MentionPick,
} from '@/lib/mentions'

type Args = {
  user: User
  conversation: Conversation | undefined
  draft: string
  onDraft: (v: string) => void
}

function readCaret(el: EventTarget | null): number | null {
  if (!el || !(el instanceof HTMLTextAreaElement)) return null
  return el.selectionStart ?? null
}

export function useGroupMentions({ user, conversation, draft, onDraft }: Args) {
  const enabled = conversation?.type === 'group' && !conversation.removed
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [members, setMembers] = useState<Contact[]>([])
  const [loading, setLoading] = useState(false)
  const [pending, setPending] = useState<MentionPick[]>([])
  const [pendingAll, setPendingAll] = useState(false)
  const [activeIndex, setActiveIndex] = useState(0)
  const loadingRef = useRef(false)
  const membersConvRef = useRef<string | null>(null)
  const draftRef = useRef(draft)
  const caretRef = useRef(draft.length)
  const pendingCaretRef = useRef<number | null>(null)
  draftRef.current = draft

  useEffect(() => {
    setPending([])
    setPendingAll(false)
    setOpen(false)
    setQuery('')
    setMembers([])
    setActiveIndex(0)
    membersConvRef.current = null
    loadingRef.current = false
    caretRef.current = 0
  }, [conversation?.id])

  const ensureMembers = useCallback(async () => {
    if (!conversation || conversation.type !== 'group') return
    if (membersConvRef.current === conversation.id && members.length > 0) return
    if (loadingRef.current) return
    loadingRef.current = true
    setLoading(true)
    const cid = conversation.id
    try {
      const res = await api.listGroupMembers(cid)
      if (conversation.id !== cid) return
      setMembers((res.members || []).filter((m) => m.id !== user.id))
      membersConvRef.current = cid
    } catch {
      MessagePlugin.error('加载群成员失败')
    } finally {
      loadingRef.current = false
      setLoading(false)
    }
  }, [conversation, members.length, user.id])

  const options = useMemo(
    () => (enabled ? filterMentionOptions(members, query) : []),
    [enabled, members, query],
  )

  useEffect(() => {
    setActiveIndex(0)
  }, [query, open, members])

  const syncFromCaret = useCallback(
    (text: string, caret: number) => {
      if (!enabled) {
        if (open) {
          setOpen(false)
          setQuery('')
        }
        return
      }
      const hit = mentionTriggerAt(text, caret)
      if (hit) {
        setQuery(hit.query)
        setOpen(true)
        void ensureMembers()
      } else if (open) {
        setOpen(false)
        setQuery('')
      }
    },
    [enabled, ensureMembers, open],
  )

  const closePicker = useCallback(() => {
    setOpen(false)
    setQuery('')
  }, [])

  const onDraftChange = useCallback(
    (next: string, caret?: number) => {
      const pos = caret ?? next.length
      caretRef.current = pos
      draftRef.current = next
      onDraft(next)
      syncFromCaret(next, pos)
    },
    [onDraft, syncFromCaret],
  )

  const onCaretEvent = useCallback(
    (e: { target?: EventTarget | null; e?: { target?: EventTarget | null } }) => {
      const el = e.target ?? e.e?.target ?? null
      const caret = readCaret(el)
      if (caret == null) return
      caretRef.current = caret
      syncFromCaret(draftRef.current, caret)
    },
    [syncFromCaret],
  )

  const insert = useCallback(
    (pick: MentionOption) => {
      const name = pick === 'all' ? '所有人' : pick.name
      const applied = insertMentionAt(draftRef.current, caretRef.current, name)
      if (!applied) return
      draftRef.current = applied.next
      caretRef.current = applied.caret
      pendingCaretRef.current = applied.caret
      onDraft(applied.next)
      if (pick === 'all') setPendingAll(true)
      else {
        setPending((prev) =>
          prev.some((p) => p.id === pick.id) ? prev : [...prev, pick],
        )
      }
      closePicker()
    },
    [closePicker, onDraft],
  )

  const consumePendingCaret = useCallback(() => {
    const c = pendingCaretRef.current
    pendingCaretRef.current = null
    return c
  }, [])

  const sendOpts = useCallback(() => {
    if (!enabled) return undefined
    return buildMentionSendOpts(draftRef.current, pending, pendingAll)
  }, [enabled, pending, pendingAll])

  const clearPending = useCallback(() => {
    setPending([])
    setPendingAll(false)
    closePicker()
  }, [closePicker])

  const moveActive = useCallback(
    (delta: number) => {
      if (options.length === 0) return
      setActiveIndex((i) => (i + delta + options.length) % options.length)
    },
    [options.length],
  )

  const confirmActive = useCallback(() => {
    if (options.length === 0) return false
    const pick = options[Math.min(activeIndex, options.length - 1)]
    insert(pick)
    return true
  }, [activeIndex, insert, options])

  return {
    enabled,
    open,
    loading,
    options,
    activeIndex,
    closePicker,
    onDraftChange,
    onCaretEvent,
    insert,
    sendOpts,
    clearPending,
    moveActive,
    confirmActive,
    consumePendingCaret,
  }
}
