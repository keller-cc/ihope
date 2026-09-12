import { useEffect, useState } from 'react'
import { meepleSrc } from './assets'

/** Soft default durations — place / payout / sail feel unhurried. */
export const FX_PLACE_MS = 920
export const FX_HOME_MS = 980
export const FX_BOARD_MS = 1000
export const FX_SAIL_MS = 1400
export const FX_PAY_MS = 1400
/** Delay before committing place to server (after fly starts). */
export const FX_PLACE_COMMIT_MS = 720
/** Sea ship slide after dice faces settle. */
export const FX_SHIP_MOVE_MS = 1600

export type FlyMeeple = {
  id: string
  seat: number
  from: { x: number; y: number }
  to: { x: number; y: number }
  durationMs?: number
}

export type FlyPay = {
  id: string
  amount: number
  from: { x: number; y: number }
  to: { x: number; y: number }
  durationMs?: number
  label?: string
}

/** Screen-space flying meeple (viewport coords). */
export function ManilaFlyLayer({
  flights,
  onDone,
}: {
  flights: FlyMeeple[]
  onDone: (id: string) => void
}) {
  return (
    <div className="manila-fx-layer" aria-hidden>
      {flights.map((f) => (
        <FlyMeepleOne key={f.id} flight={f} onDone={() => onDone(f.id)} />
      ))}
    </div>
  )
}

/** Yellow +N chips flying from board pay spots → player cash on the rail. */
export function ManilaPayFlyLayer({
  flights,
  onDone,
}: {
  flights: FlyPay[]
  onDone: (id: string) => void
}) {
  return (
    <div className="manila-fx-layer manila-fx-layer--pay" aria-hidden>
      {flights.map((f) => (
        <FlyPayOne key={f.id} flight={f} onDone={() => onDone(f.id)} />
      ))}
    </div>
  )
}

function FlyMeepleOne({ flight, onDone }: { flight: FlyMeeple; onDone: () => void }) {
  const [on, setOn] = useState(false)
  const dur = flight.durationMs ?? FX_PLACE_MS
  useEffect(() => {
    const t0 = requestAnimationFrame(() => {
      requestAnimationFrame(() => setOn(true))
    })
    const t1 = window.setTimeout(onDone, dur + 80)
    return () => {
      cancelAnimationFrame(t0)
      window.clearTimeout(t1)
    }
  }, [dur, onDone])
  const x = on ? flight.to.x : flight.from.x
  const y = on ? flight.to.y : flight.from.y
  return (
    <img
      className={`manila-fx-meeple${on ? ' is-flying' : ''}`}
      src={meepleSrc(flight.seat)}
      alt=""
      style={{
        left: x,
        top: y,
        transitionDuration: `${dur}ms`,
      }}
    />
  )
}

function FlyPayOne({ flight, onDone }: { flight: FlyPay; onDone: () => void }) {
  const [on, setOn] = useState(false)
  const dur = flight.durationMs ?? FX_PAY_MS
  useEffect(() => {
    const t0 = requestAnimationFrame(() => {
      requestAnimationFrame(() => setOn(true))
    })
    const t1 = window.setTimeout(onDone, dur + 80)
    return () => {
      cancelAnimationFrame(t0)
      window.clearTimeout(t1)
    }
  }, [dur, onDone])
  const x = on ? flight.to.x : flight.from.x
  const y = on ? flight.to.y : flight.from.y
  return (
    <span
      className={`manila-fx-pay${on ? ' is-flying' : ''}${flight.amount < 0 ? ' is-loss' : ''}`}
      style={{
        left: x,
        top: y,
        transitionDuration: `${dur}ms`,
      }}
      title={flight.label}
    >
      {flight.amount >= 0 ? `+${flight.amount}` : `${flight.amount}`}
    </span>
  )
}

/** Rect center in viewport pixels. */
export function rectCenter(el: Element | null): { x: number; y: number } | null {
  if (!el) return null
  const r = el.getBoundingClientRect()
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
}

export function railMeepleEl(userId: string): Element | null {
  return document.querySelector(`[data-manila-rail="${userId}"] .manila-rail-pawn-stack__ico`)
}

export function railCashEl(userId: string): Element | null {
  return (
    document.querySelector(`[data-manila-rail-cash="${userId}"]`) ||
    document.querySelector(`[data-manila-rail="${userId}"] .manila-rail-stat`)
  )
}

export function slotHitEl(slotId: string): Element | null {
  return document.querySelector(`[data-manila-slot="${slotId}"]`)
}

export function payBadgeEl(slotId: string): Element | null {
  return (
    document.querySelector(`[data-manila-pay="${slotId}"]`) ||
    document.querySelector(`[data-manila-slot="${slotId}"]`)
  )
}

export function pirateSeatEl(rank: number): Element | null {
  return document.querySelector(`[data-manila-slot="pirate_${rank}"]`)
}

export function puntShipEl(puntIndex: number): Element | null {
  return (
    document.querySelector(`[data-manila-punt="${puntIndex}"]`) ||
    document.querySelector(`[data-manila-berth-punt="${puntIndex}"]`)
  )
}

/** Best on-board origin for a cash change. Prefer explicit slot when known. */
export function payoutOriginEl(
  userId: string,
  occupied: Map<string, string>,
  slotId?: string,
): Element | null {
  if (slotId) {
    return (
      payBadgeEl(slotId) ||
      slotHitEl(slotId) ||
      (slotId.startsWith('punt')
        ? puntShipEl(Number(/^punt(\d+)/.exec(slotId)?.[1] || 0))
        : null)
    )
  }
  if (occupied.get('insurance') === userId) {
    return payBadgeEl('insurance') || slotHitEl('insurance')
  }
  for (const letter of ['A', 'B', 'C'] as const) {
    const port = `port_${letter}`
    if (occupied.get(port) === userId) return payBadgeEl(port) || slotHitEl(port)
  }
  for (const letter of ['A', 'B', 'C'] as const) {
    const yard = `shipyard_${letter}`
    if (occupied.get(yard) === userId) return payBadgeEl(yard) || slotHitEl(yard)
  }
  for (const [id, uid] of occupied) {
    if (uid !== userId || !id.startsWith('punt')) continue
    const m = /^punt(\d+)_/.exec(id)
    return payBadgeEl(id) || slotHitEl(id) || puntShipEl(Number(m?.[1] || 0))
  }
  return null
}
