import {
  meepleSrc,
  SPOT_BADGE_COST,
  SPOT_BADGE_PAY,
  ROLE_TAG,
  type ManilaRoleTag,
} from './assets'

export type ManilaSpotProps = {
  cost?: number | null
  payout?: number | null
  insuranceBonus?: boolean
  /** 领航 / 保险等角色圆形 tag（覆盖背景坑） */
  roleTag?: ManilaRoleTag | null
  ownerSeat?: number | null
  ownerName?: string
  live?: boolean
  taken?: boolean
  disabled?: boolean
  title?: string
  className?: string
  /** Port / yard: payout chip relative to cost well. */
  payBeside?: 'left' | 'right' | 'up-right' | 'on'
  /** Stable id for fly-to / confirm targeting */
  slotId?: string
  onClick?: () => void
}

/**
 * Badge overlays the painted well; meeple stacks on top.
 * Cost always ON the pad when present.
 * Payout / role icons sit BESIDE the pad (never covering the well).
 */
export function ManilaSpot({
  cost,
  payout,
  insuranceBonus,
  roleTag,
  ownerSeat,
  ownerName,
  live,
  taken,
  disabled,
  title,
  className,
  payBeside,
  slotId,
  onClick,
}: ManilaSpotProps) {
  const occupied = ownerSeat != null
  const hasCost = cost != null && cost > 0
  const hasPay = payout != null && payout > 0
  const roleSrc = roleTag ? ROLE_TAG[roleTag] : null

  // Cost stays in the well (pad). Role icons + pay go beside — except insurance pay ON pad.
  const inWellCost =
    insuranceBonus || payBeside === 'on'
      ? hasPay || insuranceBonus
        ? `+${insuranceBonus ? 10 : payout}`
        : null
      : hasCost
        ? String(cost)
        : null
  const besidePay =
    insuranceBonus || payBeside === 'on'
      ? null
      : hasPay
        ? `+${payout}`
        : null
  const besideSide = payBeside === 'left' || payBeside === 'up-right' ? payBeside : 'right'

  const label =
    title ||
    (occupied
      ? ownerName || '已占用'
      : insuranceBonus
        ? '保险 · 立即 +10₱'
        : hasCost && hasPay
          ? `花费 ${cost} · 到账 ${payout}`
          : hasCost
            ? `花费 ${cost}`
            : hasPay || insuranceBonus
              ? `到账 ${insuranceBonus ? 10 : payout}`
              : '空位')

  return (
    <button
      type="button"
      data-manila-slot={slotId || undefined}
      className={`manila-spot${live ? ' is-live' : ''}${taken || occupied ? ' is-taken' : ''}${
        roleSrc ? ' manila-spot--role' : ''
      }${besidePay || roleSrc ? ` manila-spot--pay-${besideSide}` : ''}${
        payBeside === 'on' || insuranceBonus ? ' manila-spot--pay-on' : ''
      }${className ? ` ${className}` : ''}`}
      disabled={disabled || !onClick}
      onClick={onClick}
      title={label}
      aria-label={label}
    >
      {inWellCost != null ? (
        <span
          className={`manila-spot__badge${
            payBeside === 'on' || insuranceBonus ? ' manila-spot__badge--pay' : ' manila-spot__badge--cost'
          }`}
          aria-hidden
        >
          <img
            src={payBeside === 'on' || insuranceBonus ? SPOT_BADGE_PAY : SPOT_BADGE_COST}
            alt=""
            draggable={false}
          />
          <em>{inWellCost}</em>
        </span>
      ) : null}

      {roleSrc ? (
        <span className="manila-spot__outer manila-spot__role" aria-hidden>
          <img src={roleSrc} alt="" draggable={false} />
        </span>
      ) : null}

      {besidePay != null ? (
        <span
          className={`manila-spot__outer manila-spot__badge manila-spot__badge--pay${
            roleSrc ? ' manila-spot__outer--stack' : ''
          }`}
          aria-hidden
        >
          <img src={SPOT_BADGE_PAY} alt="" draggable={false} />
          <em>{besidePay}</em>
        </span>
      ) : null}

      {occupied ? (
        <img className="manila-spot__meeple" src={meepleSrc(ownerSeat)} alt={ownerName || ''} />
      ) : null}
    </button>
  )
}
