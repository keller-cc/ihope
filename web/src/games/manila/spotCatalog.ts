/**
 * Spot catalog — rules + init state, derived from editable boardConfig.json.
 * Visual transform + display live on each spot in boardConfig (pad.quad_pct / pad.display).
 */
import { boardSpotDefs, type SpotDisplay } from './boardConfig'

export type SpotRegion = 'port' | 'yard' | 'shore' | 'pirate' | 'punt' | 'market'
export type SpotKind = 'port' | 'shipyard' | 'pirate' | 'pilot' | 'insurance' | 'punt'

export type SpotDef = {
  id: string
  region: SpotRegion
  kind: SpotKind
  label: string
  cost: number
  payout: number
  berth?: 'A' | 'B' | 'C'
  pirateRank?: number
  pilotSize?: 'small' | 'large'
  anchorId: string
  display: SpotDisplay
  quad: [[number, number], [number, number], [number, number], [number, number]]
}

export const BOARD_SPOT_DEFS: SpotDef[] = boardSpotDefs()

export type SpotRuntimeState = {
  id: string
  occupantUserId: string | null
  occupantSeat: number | null
  shipPresent: boolean
  shipWare: string | null
}

export function initialSpotStates(): SpotRuntimeState[] {
  return BOARD_SPOT_DEFS.map((d) => ({
    id: d.id,
    occupantUserId: null,
    occupantSeat: null,
    shipPresent: false,
    shipWare: null,
  }))
}
