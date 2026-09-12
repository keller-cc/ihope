/**
 * Board anchors — thin accessors over boardConfig.json (editable source of truth).
 * Prefer importing from boardConfig.ts for new code.
 */
import {
  BOARD_BERTHS,
  BOARD_SPOTS,
  SHIP_SEATS_CFG,
  berthPadQuad,
  spotPadCenter,
  spotPadQuad,
  type BerthConfig,
  type SpotConfig,
} from './boardConfig'
import type { PctPos, QuadPct } from './quadWarp'

export type { PctPos, QuadPct } from './quadWarp'

/** @deprecated use BOARD_SPOTS / BOARD_BERTHS from boardConfig */
export const BOARD_ANCHORS = {
  cost_pads: Object.fromEntries(
    Object.values(BOARD_SPOTS).map((s: SpotConfig) => [
      s.anchor_id,
      { center: s.pad.center, quad_pct: s.pad.quad_pct, cost: s.rules.cost, payout: s.rules.payout },
    ]),
  ),
  berths: BOARD_BERTHS,
  ship_seats: SHIP_SEATS_CFG,
}

export function costPadCenter(id: string): PctPos | null {
  // Accept either slot id (shipyard_A) or anchor id (yard_A)
  const bySlot = spotPadCenter(id)
  if (bySlot) return bySlot
  const spot = Object.values(BOARD_SPOTS).find((s) => s.anchor_id === id)
  return spot ? spot.pad.center : null
}

export function costPadQuad(id: string): QuadPct | null {
  const bySlot = spotPadQuad(id)
  if (bySlot) return bySlot
  const spot = Object.values(BOARD_SPOTS).find((s) => s.anchor_id === id)
  return spot ? spot.pad.quad_pct : null
}

export function berthCenter(id: string): PctPos | null {
  const b = BOARD_BERTHS[id as keyof typeof BOARD_BERTHS] as BerthConfig | undefined
  return b ? b.center : null
}

export function berthQuad(id: string): QuadPct | null {
  return berthPadQuad(id)
}

export const ANCHOR_PORT_SPOT = {
  A: costPadCenter('port_A')!,
  B: costPadCenter('port_B')!,
  C: costPadCenter('port_C')!,
} as const

export const ANCHOR_YARD_SPOT = {
  A: costPadCenter('shipyard_A')!,
  B: costPadCenter('shipyard_B')!,
  C: costPadCenter('shipyard_C')!,
} as const

export const ANCHOR_SHORE = {
  pilot_small: costPadCenter('pilot_small')!,
  pilot_large: costPadCenter('pilot_large')!,
  insurance: costPadCenter('insurance')!,
} as const

export const ANCHOR_PORT_BERTH = {
  A: berthCenter('port_A')!,
  B: berthCenter('port_B')!,
  C: berthCenter('port_C')!,
} as const

export const ANCHOR_YARD_BERTH = {
  A: berthCenter('yard_A')!,
  B: berthCenter('yard_B')!,
  C: berthCenter('yard_C')!,
} as const

export const SHIP_SEAT_Y_3 = SHIP_SEATS_CFG.hull3_y_pct
export const SHIP_SEAT_Y_4 = SHIP_SEATS_CFG.hull4_y_pct
