/** Kenney meeples/dice + circular share tags (transparent rim). */

export const PIECE_BASE = '/games/manila/pieces'
export const BOARD_BASE = '/games/manila/board'
/** Bust stale PNG/JPG after asset regenerations */
const ASSET_V = '20260913d'

export const SEAT_COLORS = ['red', 'blue', 'green', 'yellow', 'purple'] as const

/** 现代风伙计图标（座位色） */
export function meepleSrc(seat: number) {
  const c = SEAT_COLORS[seat % SEAT_COLORS.length]
  return `${PIECE_BASE}/meeple-${c}.png?v=${ASSET_V}`
}

export function dieSrc(n: number) {
  const v = Math.min(6, Math.max(1, n || 1))
  return `${PIECE_BASE}/die-${v}.png?v=${ASSET_V}`
}

export const COIN = `${PIECE_BASE}/coin.png?v=${ASSET_V}`
export const PRICE_MARKER = `${PIECE_BASE}/price-marker.png?v=${ASSET_V}`
/** 暗股背面（油画风透明底） */
export const SHARE_BACK = `${PIECE_BASE}/share-back.png?v=${ASSET_V}`
/** 花费：正面金币；收益：同尺寸异风格（银碧） */
export const SPOT_BADGE_COST = `${PIECE_BASE}/spot-badge-cost.png?v=${ASSET_V}`
export const SPOT_BADGE_PAY = `${PIECE_BASE}/spot-badge-pay.png?v=${ASSET_V}`
/** @deprecated 等同花费徽章 */
export const SPOT_BADGE = SPOT_BADGE_COST
/** @deprecated 点位改用 SPOT_BADGE_COST */
export const SPOT_WELL = SPOT_BADGE_COST

export type ManilaRoleTag = 'pilot_small' | 'pilot_large' | 'insurance'

/** 领航 / 保险圆形 tag icon */
export const ROLE_TAG: Record<ManilaRoleTag, string> = {
  pilot_small: `${PIECE_BASE}/tag-pilot-small.png?v=${ASSET_V}`,
  pilot_large: `${PIECE_BASE}/tag-pilot-large.png?v=${ASSET_V}`,
  insurance: `${PIECE_BASE}/tag-insurance.png?v=${ASSET_V}`,
}

export const PANEL_WOOD = `${BOARD_BASE}/panel-wood.png?v=${ASSET_V}`

/**
 * 股份唯一图标：油画风商品贴图，透明底，无圆盘/边框底板。
 */
export function shareSrc(ware: string) {
  const w = ['nutmeg', 'silk', 'ginseng', 'jade'].includes(ware) ? ware : 'nutmeg'
  return `${PIECE_BASE}/share-${w}.png?v=${ASSET_V}`
}

/** @deprecated 与 shareSrc 相同 */
export function shareCardSrc(ware: string) {
  return shareSrc(ware)
}

/** 玩家可放置的「伙计」棋子（原规则 accomplice） */
export const PAWN_LABEL = '伙计'
