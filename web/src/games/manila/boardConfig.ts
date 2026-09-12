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
import { quadBBox, shiftQuad, type PctPos, type QuadPct } from './quadWarp'

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
  /** board-effect: centered circle (no pad-quad warp), e.g. insurance */
  paste_mode?: 'centered' | 'quad'
  /** Fixed badge diameter in board px when paste_mode=centered (bake uses 56) */
  badge_d_px?: number
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

/** Pay badge quad = cost pad shifted by display.pay_offset_pct (board-effect bake). */
export function payPadQuad(id: string): QuadPct | null {
  const s = spotConfig(id)
  if (!s?.pad.display.pay_badge) return null
  const beside = s.pad.display.pay_beside
  if (!beside || beside === 'none' || beside === 'on') return null
  const off = s.pad.display.pay_offset_pct
  if (!off) return null
  const q = s.pad.quad_pct
  return shiftQuad(q, off[0], off[1])
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
