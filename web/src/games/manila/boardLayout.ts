/**
 * Full-plate Manila board — centers from boardConfig.json (board.jpg).
 * Generation methods: public/games/manila/board/GENERATION.md
 */

import {
  ANCHOR_PORT_BERTH,
  ANCHOR_PORT_SPOT,
  ANCHOR_SHORE,
  ANCHOR_YARD_BERTH,
  ANCHOR_YARD_SPOT,
  BOARD_ANCHORS,
} from './boardAnchors'
import {
  BOARD_MARKET,
  marketMarkerPos as marketMarkerPosFromCfg,
  marketTagPos as marketTagPosFromCfg,
} from './boardConfig'

const ASSET_V = '20260913d'

export const BOARD_IMG = `/games/manila/board/board.jpg?v=${ASSET_V}`

/** Scenic board.jpg is square (1024×1024). */
export const PLATE_ASPECT = '1 / 1'

/** Shared wooden hulls (same outer width); 3-seat vs 4-seat wells only. */
export const HULL_3 = `/games/manila/board/hull-3.png?v=${ASSET_V}`
export const HULL_4 = `/games/manila/board/hull-4.png?v=${ASSET_V}`

export const WARE_SEATS: Record<string, number> = {
  nutmeg: 3,
  silk: 3,
  ginseng: 3,
  jade: 4,
}

/** Accomplice seat costs by ware (lowest-priced vacant first) — matches appserver WareSeatCosts. */
export const WARE_SEAT_COSTS: Record<string, number[]> = {
  nutmeg: [3, 4, 5],
  silk: [3, 4, 5],
  ginseng: [2, 3, 4],
  jade: [2, 3, 4, 5],
}

export const WARE_PROFIT: Record<string, number> = {
  nutmeg: 24,
  silk: 18,
  ginseng: 30,
  jade: 36,
}

export const TRACK_MAX = 13
export const START_MAX = 5

export const MARKET_TRACK = [0, 5, 10, 20, 30] as const
/** Overlay rows top→bottom: ware tags, then 30,20,10,5,0 (markers start at 0). */
export const MARKET_VALUE_ROWS = [30, 20, 10, 5, 0] as const

export const LOAN_AMOUNT = 12
export const REPAY_AMOUNT = 15

export type PctPos = { x: number; y: number }

export type ShipHeading = 'sea' | 'port' | 'yard'

/** Three wake lanes (bow toward top / finish). Tuned to scenic board.jpg. */
export const LANE_X = [40, 49, 58]

/** Track numerals sit left of the lanes in open water. */
export const TRACK_NUM_X = 31

/**
 * Sea-route Y% on the full plate. Port pools sit ABOVE `finish`.
 * 0–13 stay in water: 11/12/13 are last sea spaces, not the docks.
 */
export const TRACK_Y = {
  open: 86,
  at5: 60,
  finish: 34,
} as const

/** Pirate token left of the on-water finish band (not the painted scenic sailboat). */
export const PIRATE_POS = { x: 26, y: 36 }

/** Shore pads — from boardConfig.json. */
export const SHORE_POS: Record<string, PctPos> = { ...ANCHOR_SHORE }

/** Meeple / cost wells — cost ON pad (boardConfig). */
export const PORT_SPOT: Record<'A' | 'B' | 'C', PctPos> = { ...ANCHOR_PORT_SPOT }

/** Port A·B·C water slips — from boardConfig. */
export const PORT_BERTH: Record<'A' | 'B' | 'C', PctPos> = { ...ANCHOR_PORT_BERTH }

/** Yard cost wells — from boardConfig. */
export const YARD_SPOT: Record<'A' | 'B' | 'C', PctPos> = { ...ANCHOR_YARD_SPOT }

/** Shipyard water berths — from boardConfig. */
export const YARD_BERTH: Record<'A' | 'B' | 'C', PctPos> = { ...ANCHOR_YARD_BERTH }

/** @deprecated use PORT_BERTH / YARD_BERTH */
export const BERTH_SLOT = {
  A: { y: YARD_BERTH.A.y },
  B: { y: YARD_BERTH.B.y },
  C: { y: YARD_BERTH.C.y },
} as const

/**
 * Black-market / stock panel — perspective + UV layout live in boardConfig.market.
 */
export const MARKET_WARES = ['nutmeg', 'silk', 'ginseng', 'jade'] as const
export { BOARD_MARKET as MARKET_CFG }

export function marketTagPos(ware: (typeof MARKET_WARES)[number]): PctPos {
  return marketTagPosFromCfg(ware) ?? { x: 90, y: 72 }
}

export function marketMarkerPos(ware: (typeof MARKET_WARES)[number], value: number): PctPos {
  return marketMarkerPosFromCfg(ware, value) ?? { x: 90, y: 80 }
}

/** Y% of a space’s front (number). Always clamped to the water band. */
export function trackY(pos: number): number {
  const p = Math.max(0, Math.min(TRACK_MAX, pos))
  const y =
    p <= 5
      ? TRACK_Y.open + (p / 5) * (TRACK_Y.at5 - TRACK_Y.open)
      : TRACK_Y.at5 + ((p - 5) / (TRACK_MAX - 5)) * (TRACK_Y.finish - TRACK_Y.at5)
  const lo = Math.min(TRACK_Y.finish, TRACK_Y.open)
  const hi = Math.max(TRACK_Y.finish, TRACK_Y.open)
  return Math.min(hi, Math.max(lo, y))
}

/** Pirate meeple seats on the painted scenic boat — from anchors.json. */
export const PIRATE_SEAT_POS = [
  {
    x: BOARD_ANCHORS.cost_pads.pirate_0.center.x,
    y: BOARD_ANCHORS.cost_pads.pirate_0.center.y,
  },
  {
    x: BOARD_ANCHORS.cost_pads.pirate_1.center.x,
    y: BOARD_ANCHORS.cost_pads.pirate_1.center.y,
  },
  {
    x: BOARD_ANCHORS.cost_pads.pirate_2.center.x,
    y: BOARD_ANCHORS.cost_pads.pirate_2.center.y,
  },
] as const

export const PIRATE_SLOT_IDS = ['pirate_0', 'pirate_1', 'pirate_2'] as const

export function slotRegion(
  slotId: string,
): 'port' | 'yard' | 'shore' | 'pirate' | 'punt' | 'other' {
  if (slotId.startsWith('port_')) return 'port'
  if (slotId.startsWith('shipyard_')) return 'yard'
  if (slotId.startsWith('pirate_')) return 'pirate'
  if (slotId.startsWith('pilot_') || slotId === 'insurance') return 'shore'
  if (slotId.startsWith('punt')) return 'punt'
  return 'other'
}

export function nextPirateSlotId(occupiedIds: Set<string> | Map<string, string>): string | null {
  for (const id of PIRATE_SLOT_IDS) {
    if (!occupiedIds.has(id)) return id
  }
  return null
}

export function berthHeading(berth?: string): ShipHeading {
  if (!berth) return 'sea'
  if (berth.startsWith('port_')) return 'port'
  if (berth.startsWith('shipyard_')) return 'yard'
  return 'sea'
}

/** Face helpers kept for titles; UI uses cost+payout dual chips. */
export function spotFace(slot: {
  kind: string
  cost: number
  payout: number
}): number | string {
  if (slot.kind === 'insurance') return '+10'
  if (slot.payout > 0 && slot.cost === 0) return slot.payout
  return slot.cost
}
