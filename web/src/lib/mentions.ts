/** Pure helpers for group @ mentions (composer). */

export type MentionPick = { id: string; name: string }

export type MentionOption = MentionPick | 'all'

export type MentionTrigger = {
  query: string
  /** Index of `@` in draft. */
  start: number
}

/** `@query` immediately before caret — no leading-space requirement. */
export function mentionTriggerAt(draft: string, caret: number): MentionTrigger | null {
  const pos = Math.max(0, Math.min(caret, draft.length))
  const before = draft.slice(0, pos)
  const m = before.match(/@([^\s@]*)$/)
  if (!m) return null
  return { query: m[1], start: before.length - m[0].length }
}

/** End-of-text trigger (caret = length). */
export function mentionTrigger(draft: string): MentionTrigger | null {
  return mentionTriggerAt(draft, draft.length)
}

/** Replace `@query` before caret with `@name `. */
export function insertMentionAt(
  draft: string,
  caret: number,
  name: string,
): { next: string; caret: number } | null {
  const hit = mentionTriggerAt(draft, caret)
  if (!hit) return null
  const after = draft.slice(caret)
  const token = `@${name} `
  const next = draft.slice(0, hit.start) + token + after
  return { next, caret: hit.start + token.length }
}

/** True if draft still contains a standalone `@name` token. */
export function draftHasMentionToken(draft: string, name: string): boolean {
  if (!name) return false
  const re = new RegExp(`@${escapeRegExp(name)}(?=$|[\\s\\n])`)
  return re.test(draft)
}

export function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

export function buildMentionSendOpts(
  draft: string,
  pending: MentionPick[],
  pendingAll: boolean,
): { mentionUserIds: string[]; mentionAll: boolean } | undefined {
  const mentionAll = pendingAll && draftHasMentionToken(draft, '所有人')
  const mentionUserIds = pending
    .filter((p) => draftHasMentionToken(draft, p.name))
    .map((p) => p.id)
  if (!mentionAll && mentionUserIds.length === 0) return undefined
  return { mentionUserIds, mentionAll }
}

export function filterMentionOptions(
  members: { id: string; username?: string; remark?: string }[],
  query: string,
): MentionOption[] {
  const q = query.trim().toLowerCase()
  const out: MentionOption[] = []
  if (!q || '所有人'.includes(q) || 'all'.startsWith(q)) {
    out.push('all')
  }
  for (const m of members) {
    const name = (m.username || '').trim()
    if (!name) continue
    const remark = (m.remark || '').trim()
    if (q && !`${name} ${remark}`.toLowerCase().includes(q)) continue
    out.push({ id: m.id, name })
  }
  return out
}
