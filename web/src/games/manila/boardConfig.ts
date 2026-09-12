/**
 * Board layout config — editable source of truth.
 *
 * Each spot / berth / market entry records:
 * - perspective transform (`quad_pct` TL→TR→BR→BL, % of plate)
 * - what to show (`display` / `rules`)
 *
 * File: boardConfig.json (synced under public/games/manila/board/)
 */
import cfg from './boardConfig.json'
import { berthShipStyle, coverBerthStyle, padSpotStyle, quadBBox, type PctPos, type QuadPct } from './quadWarp'

export type { PctPos, QuadPct } from './quadWarp'

export type PayBeside = 'left' | 'right' | 'up-right' | 'on' | 'none'
export type RoleTagId = 'pilot_small' | 'pilot_large' | 'insurance'

export type SpotDisplay = {
  cost_badge: boolean
  cost_value: number | null
  pay_badge: boolean
  pay_value: number | null
  pay_beside: PayBeside
  pay_offset_pct?: [number, number]
  role_tag: RoleTagId | null
}

export type SpotConfig = {
  id: string
  anchor_id: string
  kind: string
  region: string
  label: string
  rules: {
    cost: number
    payout: number
    berth?: string
    pirate_rank?: number
    pilot_size?: string
  }
  pad: {
    center: PctPos
    quad_pct: QuadPct
    plane?: Record<string, unknown>
    display: SpotDisplay
  }
  linked_berth?: string
}

export type BerthConfig = {
  id: string
  region: string
  center: PctPos
  quad_pct: QuadPct
  plane?: Record<string, unknown>
  ship_orient: 'port' | 'yard' | 'sea'
  ship_rot_deg?: number
  display: { accepts_ship: boolean; perspective?: boolean; letter?: string | null }
}

export type MarketConfig = {
  id: string
  label: string
  panel_quad_pct: QuadPct
  wares: string[]
  value_rows: number[]
  track_values: number[]
  /** landscape: values along width, wares along height */
  orientation?: 'portrait' | 'landscape'
  layout: {
    tag_y?: number
    first_value_y?: number
    row_h?: number
    col_pad_x?: number
    col_w?: number
    /** landscape: ware tag on left of each row */
    tag_x?: number
    first_value_x?: number
    row_pad_y?: number
  }
  display: {
    show_ware_tags: boolean
    show_value_labels: boolean
    show_price_markers: boolean
    panel_wood: boolean
  }
}

export const BOARD_CONFIG = cfg

export const BOARD_SPOTS = cfg.spots as unknown as Record<string, SpotConfig>
export const BOARD_BERTHS = cfg.berths as unknown as Record<string, BerthConfig>
export const BOARD_MARKET = cfg.market as unknown as MarketConfig
export const SHIP_SEATS_CFG = cfg.ship_seats

export function spotConfig(id: string): SpotConfig | null {
  return BOARD_SPOTS[id] ?? null
}

export function spotPadQuad(id: string): QuadPct | null {
  const s = spotConfig(id)
  return s ? s.pad.quad_pct : null
}

export function spotPadCenter(id: string): PctPos | null {
  const s = spotConfig(id)
  return s ? s.pad.center : null
}

export function berthConfig(id: string): BerthConfig | null {
  return BOARD_BERTHS[id] ?? null
}

export function berthPadQuad(id: string): QuadPct | null {
  const b = berthConfig(id)
  return b ? b.quad_pct : null
}

/** Bilinear map UV∈[0,1]² → plate % inside a perspective quad. */
export function quadUvToPct(quad: QuadPct, u: number, v: number): PctPos {
  const [tl, tr, br, bl] = quad
  const topX = tl[0] + (tr[0] - tl[0]) * u
  const topY = tl[1] + (tr[1] - tl[1]) * u
  const botX = bl[0] + (br[0] - bl[0]) * u
  const botY = bl[1] + (br[1] - bl[1]) * u
  return {
    x: topX + (botX - topX) * v,
    y: topY + (botY - topY) * v,
  }
}

export function marketWareCol(ware: string): number {
  return BOARD_MARKET.wares.indexOf(ware)
}

export function marketTagUv(ware: string): { u: number; v: number } | null {
  const col = marketWareCol(ware)
  if (col < 0) return null
  const m = BOARD_MARKET
  if (m.orientation === 'landscape') {
    const { tag_x = 0.08, row_pad_y = 0.1, row_h = 0.2 } = m.layout
    return { u: tag_x, v: row_pad_y + col * row_h + row_h / 2 }
  }
  const { col_pad_x = 0.08, col_w = 0.21, tag_y = 0.08 } = m.layout
  return { u: col_pad_x + col * col_w + col_w / 2, v: tag_y }
}

export function marketCellUv(ware: string, value: number): { u: number; v: number } | null {
  const wi = marketWareCol(ware)
  const vi = BOARD_MARKET.value_rows.indexOf(value)
  if (wi < 0 || vi < 0) return null
  const m = BOARD_MARKET
  if (m.orientation === 'landscape') {
    // columns = values left→right (0,5,10,20,30), rows = wares top→bottom
    const { first_value_x = 0.22, col_w = 0.14, row_pad_y = 0.1, row_h = 0.2 } = m.layout
    const asc = m.track_values
    const ci = asc.indexOf(value)
    if (ci < 0) return null
    return {
      u: first_value_x + ci * col_w + col_w / 2,
      v: row_pad_y + wi * row_h + row_h / 2,
    }
  }
  const { col_pad_x = 0.08, col_w = 0.21, first_value_y = 0.22, row_h = 0.14 } = m.layout
  return {
    u: col_pad_x + wi * col_w + col_w / 2,
    v: first_value_y + vi * row_h + row_h / 2,
  }
}

export function marketTagPos(ware: string): PctPos | null {
  const uv = marketTagUv(ware)
  if (!uv) return null
  return quadUvToPct(BOARD_MARKET.panel_quad_pct, uv.u, uv.v)
}

export function marketMarkerPos(ware: string, value: number): PctPos | null {
  const uv = marketCellUv(ware, value)
  if (!uv) return null
  return quadUvToPct(BOARD_MARKET.panel_quad_pct, uv.u, uv.v)
}

export function marketPanelStyle() {
  // Flat axis-aligned panel — no perspective warp
  const box = quadBBox(BOARD_MARKET.panel_quad_pct)
  return {
    left: `${box.x}%`,
    top: `${box.y}%`,
    width: `${box.w}%`,
    height: `${box.h}%`,
  }
}

export function marketPanelBox() {
  return quadBBox(BOARD_MARKET.panel_quad_pct)
}

/** Spot defs for rules / init — derived from boardConfig. */
export function boardSpotDefs() {
  return Object.values(BOARD_SPOTS).map((s) => ({
    id: s.id,
    region: s.region as 'port' | 'yard' | 'shore' | 'pirate' | 'punt' | 'market',
    kind: s.kind as 'port' | 'shipyard' | 'pirate' | 'pilot' | 'insurance' | 'punt',
    label: s.label,
    cost: s.rules.cost,
    payout: s.rules.payout,
    berth: s.rules.berth as 'A' | 'B' | 'C' | undefined,
    pirateRank: s.rules.pirate_rank,
    pilotSize: s.rules.pilot_size as 'small' | 'large' | undefined,
    anchorId: s.anchor_id,
    display: s.pad.display,
    quad: s.pad.quad_pct,
  }))
}

export { berthShipStyle, coverBerthStyle, padSpotStyle }
