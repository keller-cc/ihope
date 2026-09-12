import { useEffect, useMemo, useRef, useState } from 'react'
import type { ManilaMatch } from '@/api'
import { meepleSrc } from './assets'
import {
  FX_PAY_MS,
  payoutOriginEl,
  railCashEl,
  rectCenter,
  type FlyPay,
} from './ManilaFx'
import { WARE_LABEL } from './rulesContent'

export type SettleLine = NonNullable<ManilaMatch['settlement']>[number]

const STEP_MS = 2100
const INTRO_MS = 600

const KIND_LABEL: Record<string, string> = {
  cargo: '进港分成',
  port: '港口收入',
  yard: '船坞收入',
  insurance: '保险赔付',
}

type Props = {
  match: ManilaMatch
  occupiedMap: Map<string, string>
  ready: boolean
  onFly: (flight: FlyPay) => void
}

/**
 * Full-screen settle: one ledger line at a time + everyone sees all players' running totals.
 */
export function ManilaSettlePanel({ match, occupiedMap, ready, onFly }: Props) {
  const lines = match.settlement || []
  const [step, setStep] = useState(-1) // -1 intro, 0..n-1 lines, n outro
  const key = `${match.voyage}:${lines.map((l) => `${l.userId}:${l.amount}:${l.slotId}`).join('|')}`
  const startedKey = useRef('')
  const flown = useRef(new Set<number>())

  useEffect(() => {
    if (!ready || match.phase !== 'settle') return
    if (!lines.length) {
      setStep(0)
      return
    }
    if (startedKey.current === key) return
    startedKey.current = key
    flown.current = new Set()
    setStep(-1)

    const timers: number[] = []
    timers.push(window.setTimeout(() => setStep(0), INTRO_MS))
    for (let i = 0; i < lines.length; i++) {
      timers.push(window.setTimeout(() => setStep(i), INTRO_MS + i * STEP_MS))
    }
    timers.push(
      window.setTimeout(() => setStep(lines.length), INTRO_MS + lines.length * STEP_MS),
    )
    return () => {
      timers.forEach((t) => window.clearTimeout(t))
    }
  }, [ready, match.phase, key, lines.length])

  // Fly money for the active line
  useEffect(() => {
    if (step < 0 || step >= lines.length) return
    if (flown.current.has(step)) return
    flown.current.add(step)
    const line = lines[step]!
    if (!line.amount) return
    const fromEl = payoutOriginEl(line.userId, occupiedMap, line.slotId)
    const from = rectCenter(fromEl)
    const to = rectCenter(railCashEl(line.userId))
    if (!from || !to) return
    onFly({
      id: `settle-step-${match.voyage}-${step}`,
      amount: line.amount,
      from,
      to,
      durationMs: Math.min(FX_PAY_MS, STEP_MS - 400),
      label: line.label,
    })
  }, [step, lines, occupiedMap, onFly, match.voyage])

  const totals = useMemo(() => {
    const map = new Map<string, number>()
    const revealUntil = step < 0 ? -1 : Math.min(step, lines.length - 1)
    for (let i = 0; i <= revealUntil; i++) {
      const line = lines[i]
      if (!line) continue
      map.set(line.userId, (map.get(line.userId) || 0) + line.amount)
    }
    // During outro, show full totals
    if (step >= lines.length) {
      map.clear()
      for (const line of lines) {
        map.set(line.userId, (map.get(line.userId) || 0) + line.amount)
      }
    }
    return map
  }, [lines, step])

  const current = step >= 0 && step < lines.length ? lines[step] : null
  const playerName = (uid: string) =>
    match.players.find((p) => p.userId === uid)?.username || '—'

  if (match.phase !== 'settle' || !ready) return null

  const phaseLabel =
    step < 0
      ? '航次结算'
      : step >= lines.length
        ? '结算完成'
        : `结算 ${step + 1}/${lines.length}`

  return (
    <div className="manila-settle" role="dialog" aria-label="航次结算">
      <div className="manila-settle__panel">
        <header className="manila-settle__head">
          <p className="manila-settle__eyebrow">第 {match.voyage} 航次</p>
          <h2>{phaseLabel}</h2>
          {current ? (
            <p className="manila-settle__current">
              <strong className={current.amount >= 0 ? 'is-gain' : 'is-loss'}>
                {current.amount >= 0 ? `+${current.amount}` : current.amount}₱
              </strong>
              <span>
                {playerName(current.userId)} ·{' '}
                {current.label ||
                  KIND_LABEL[current.kind] ||
                  current.kind ||
                  '收益'}
              </span>
            </p>
          ) : step >= lines.length ? (
            <p className="manila-settle__current manila-settle__current--done">
              各人净收益如下，即将进入下一航次
            </p>
          ) : (
            <p className="manila-settle__current">正在汇总港口、船坞与保险…</p>
          )}
        </header>

        <ul className="manila-settle__players">
          {[...match.players]
            .sort((a, b) => a.seat - b.seat)
            .map((p) => {
              const delta = totals.get(p.userId) || 0
              const isActive = current?.userId === p.userId
                  const shownLines =
                    step < 0
                      ? []
                      : lines
                          .slice(0, step >= lines.length ? lines.length : step + 1)
                          .filter((l) => l.userId === p.userId)
              return (
                <li
                  key={p.userId}
                  className={`manila-settle__player${isActive ? ' is-active' : ''}${
                    delta > 0 ? ' is-up' : delta < 0 ? ' is-down' : ''
                  }`}
                >
                  <div className="manila-settle__player-top">
                    <img src={meepleSrc(p.seat)} alt="" draggable={false} />
                    <div>
                      <strong>{p.username}</strong>
                      <span>座位 {p.seat + 1}</span>
                    </div>
                    <em
                      className={`manila-settle__delta${
                        delta > 0 ? ' is-gain' : delta < 0 ? ' is-loss' : ''
                      }`}
                    >
                      {delta > 0 ? `+${delta}` : delta < 0 ? `${delta}` : '0'}₱
                    </em>
                  </div>
                  {shownLines.length > 0 ? (
                    <ul className="manila-settle__bits">
                      {shownLines.map((l, i) => (
                        <li
                          key={`${l.slotId}-${i}-${l.amount}`}
                          className={l.amount >= 0 ? 'is-gain' : 'is-loss'}
                        >
                          <span>
                            {prettyLabel(l) ||
                              KIND_LABEL[l.kind] ||
                              l.kind}
                          </span>
                          <strong>
                            {l.amount >= 0 ? `+${l.amount}` : l.amount}₱
                          </strong>
                        </li>
                      ))}
                    </ul>
                  ) : (
                    <p className="manila-settle__empty">暂无变动</p>
                  )}
                </li>
              )
            })}
        </ul>
      </div>
    </div>
  )
}

function prettyLabel(line: SettleLine): string {
  if (line.label) {
    // Server may log ware english id — map if present
    let s = line.label
    for (const [k, v] of Object.entries(WARE_LABEL)) {
      s = s.replaceAll(k, v)
    }
    return s
  }
  return ''
}
