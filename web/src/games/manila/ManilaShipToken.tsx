import type { CSSProperties } from 'react'
import type { ManilaWare } from '@/api'
import { shareSrc } from './assets'
import { HULL_3, HULL_4, WARE_PROFIT, WARE_SEATS, type ShipHeading } from './boardLayout'
import { ManilaSpot } from './ManilaSpot'
import { WARE_LABEL } from './rulesContent'

export type ShipSeat = {
  id: string
  cost: number
  ownerSeat?: number
  ownerName?: string
  free: boolean
  clickable: boolean
  onPlace: () => void
  title: string
}

type Props = {
  ware: string
  seats: ShipSeat[]
  die?: number
  sailing?: boolean
  heading?: ShipHeading
  nudgeY?: number
  className?: string
  compact?: boolean
}

import { SHIP_SEAT_Y_3, SHIP_SEAT_Y_4 } from './boardAnchors'
import { SHIP_SEATS_CFG } from './boardConfig'

/** Deck seat centers (%) — from anchors.json ship_seats (same for every cargo ship). */
const SEAT_Y_3 = SHIP_SEAT_Y_3
const SEAT_Y_4 = SHIP_SEAT_Y_4
const SEAT_X = SHIP_SEATS_CFG.seat_x_pct ?? 50
  const SEAT_FRAC = SHIP_SEATS_CFG.badge_diameter_frac_of_hull_width ?? 0.58
const SLIM = SHIP_SEATS_CFG.width_frac ?? 0.78
const FIXED_LEN = SHIP_SEATS_CFG.fixed_len_px ?? 168
const CARGO_FRAC =
  (SHIP_SEATS_CFG.cargo_px ?? 50) / Math.max(1, FIXED_LEN * SLIM)
/** Bow profit plaque height as fraction of hull layout width (bake: profit_h / (len × artAspect)). */
const PROFIT_H_FRAC =
  ((SHIP_SEATS_CFG as { profit_h_px?: number }).profit_h_px ?? 24) /
  Math.max(1, FIXED_LEN * (360 / 897))
/** Plaque width ≈ 0.9 × slim visual hull, in layout-width units. */
const PROFIT_W_FRAC = 0.9 * SLIM

/**
 * Narrow photoreal hull (identical width + side curve):
 * bow brass profit · large mid pads · stern cargo — pads fill inner deck.
 */
export function ManilaShipToken({
  ware,
  seats,
  die,
  sailing,
  heading = 'sea',
  nudgeY = 0,
  className,
  compact,
}: Props) {
  const w = (['nutmeg', 'silk', 'ginseng', 'jade'].includes(ware) ? ware : 'nutmeg') as ManilaWare
  const profit = WARE_PROFIT[w] || 0
  const seatN = WARE_SEATS[w] || seats.length || 3
  const ys = seatN >= 4 ? SEAT_Y_4 : SEAT_Y_3
  const hull = seatN >= 4 ? HULL_4 : HULL_3

  return (
    <div
      className={`manila-ship-token manila-ship-token--art manila-ship-token--${w} manila-ship-token--${heading}${
        sailing ? ' is-sail' : ''
      }${compact ? ' is-compact' : ''}${className ? ` ${className}` : ''}`}
      data-seats={seatN}
      style={
        {
          ['--manila-ship-slim']: String(SLIM),
          ['--manila-seat-frac']: String(SEAT_FRAC),
          ['--manila-cargo-frac']: String(CARGO_FRAC),
          ['--manila-profit-h']: String(PROFIT_H_FRAC),
          ['--manila-profit-w']: String(PROFIT_W_FRAC),
          ...(nudgeY ? { ['--ship-nudge']: `${nudgeY}px` } : null),
        } as CSSProperties
      }
    >
      <div className="manila-ship-token__hull">
        <img className="manila-ship-token__punt" src={hull} alt="" draggable={false} />
        <span
          className="manila-ship-token__profit-onbow"
          title={`${WARE_LABEL[w]} 进港收益 +${profit}`}
          aria-label={`${WARE_LABEL[w]} 收益 +${profit}`}
        >
          +{profit}
        </span>
        <img
          className="manila-ship-token__cargo"
          src={shareSrc(w)}
          alt={WARE_LABEL[w]}
          draggable={false}
        />
        {!compact
          ? seats.map((s, i) => {
              const top = ys[i] ?? ys[ys.length - 1]
              const occupied = s.ownerSeat != null
              return (
                <div
                  key={s.id}
                  className="manila-ship-seat-wrap"
                  style={{ left: `${SEAT_X}%`, top: `${top}%` }}
                >
                  <ManilaSpot
                    slotId={s.id}
                    cost={occupied || !s.free ? null : s.cost}
                    ownerSeat={occupied ? s.ownerSeat : undefined}
                    ownerName={s.ownerName}
                    live={s.clickable}
                    taken={occupied || !s.free}
                    disabled={!s.clickable}
                    title={s.title}
                    onClick={s.clickable ? s.onPlace : undefined}
                  />
                </div>
              )
            })
          : null}
      </div>

      {die ? <span className="manila-ship-token__die">{die}</span> : null}
    </div>
  )
}
