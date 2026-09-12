import { useEffect, useState } from 'react'
import { meepleSrc } from './assets'

export type FlyMeeple = {
  id: string
  seat: number
  from: { x: number; y: number }
  to: { x: number; y: number }
  durationMs?: number
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
        <FlyOne key={f.id} flight={f} onDone={() => onDone(f.id)} />
      ))}
    </div>
  )
}

function FlyOne({ flight, onDone }: { flight: FlyMeeple; onDone: () => void }) {
  const [on, setOn] = useState(false)
  const dur = flight.durationMs ?? 520
  useEffect(() => {
    const t0 = requestAnimationFrame(() => setOn(true))
    const t1 = window.setTimeout(onDone, dur + 40)
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

/** Rect center in viewport pixels. */
export function rectCenter(el: Element | null): { x: number; y: number } | null {
  if (!el) return null
  const r = el.getBoundingClientRect()
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
}

export function railMeepleEl(userId: string): Element | null {
  return document.querySelector(`[data-manila-rail="${userId}"] .manila-rail-pawn-stack__ico`)
}

export function slotHitEl(slotId: string): Element | null {
  return document.querySelector(`[data-manila-slot="${slotId}"]`)
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
