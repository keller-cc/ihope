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
import { BOARD_BERTHS } from './boardConfig'
import { ASSET_V } from './assets'

export const BOARD_IMG = `/games/manila/board/board.jpg?v=${ASSET_V}`

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

export const LOAN_AMOUNT = 12
export const REPAY_AMOUNT = 15

export type PctPos = { x: number; y: number }

export type ShipHeading = 'sea' | 'port' | 'yard'

const START_FALLBACK: PctPos[] = [
  { x: 37.6, y: 89.0 },
  { x: 47.9, y: 91.46 },
  { x: 57.47, y: 91.6 },
]
const START_ROT_FALLBACK = [8, 5, 2] as const

/**
 * Per-punt sea geometry from boardConfig `start_*` (each ship: start + heading).
 * Route is a straight line along `rotDeg` (CW from vertical, bow toward harbor).
 */
export const SEA_LANES: { start: PctPos; rotDeg: number }[] = [0, 1, 2].map((i) => {
  const b = BOARD_BERTHS[`start_${i}`]
  return {
    start: b?.center ? { x: b.center.x, y: b.center.y } : START_FALLBACK[i]!,
    rotDeg: b?.ship_rot_deg ?? START_ROT_FALLBACK[i]!,
  }
})

/**
 * Sea-route finish Y% (ship center). Port pools sit ABOVE this band.
 */
export const TRACK_Y = {
  open: (SEA_LANES[0]!.start.y + SEA_LANES[1]!.start.y + SEA_LANES[2]!.start.y) / 3,
  finish: 40.5,
} as const

/** Pose along a ship's own heading — straight line from its start. */
export function lanePose(
  lane: number,
  pos = 0,
): { x: number; y: number; rot: number } {
  const i = Math.max(0, Math.min(2, Math.floor(lane)))
  const L = SEA_LANES[i]!
  const t = Math.max(0, Math.min(TRACK_MAX, pos)) / TRACK_MAX
  const rad = (L.rotDeg * Math.PI) / 180
  const cos = Math.cos(rad)
  const pathLen = (L.start.y - TRACK_Y.finish) / Math.max(0.25, Math.abs(cos))
  return {
    x: L.start.x + pathLen * t * Math.sin(rad),
    y: L.start.y - pathLen * t * cos,
    rot: L.rotDeg,
  }
}

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

/** Pirate meeple seats on the painted scenic boat — from boardConfig. */
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

export function nextPirateSlotId(occupiedIds: Set<string> | Map<string, string>): string | null {
  for (const id of PIRATE_SLOT_IDS) {
    if (!occupiedIds.has(id)) return id
  }
  return null
}

/** Punt accomplice seats: lowest index (bow / cheapest) must fill first. */
export function nextPuntSeatId(
  puntIndex: number,
  seatCount: number,
  occupiedIds: Set<string> | Map<string, string>,
): string | null {
  for (let i = 0; i < seatCount; i++) {
    const id = `punt${puntIndex}_${i}`
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
