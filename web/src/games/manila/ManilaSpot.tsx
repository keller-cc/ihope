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
  /**
   * - omit: cost disc only (pay is a separate warped layer)
   * - 'on': yellow pay disc on this pad (insurance)
   */
  payBeside?: 'on'
  /** Stable id for fly-to / confirm targeting */
  slotId?: string
  onClick?: () => void
}

/**
 * Cost / on-pad pay disc fills the parent box.
 * Insurance uses the yellow pay art (+N), same as board-effect bake.
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
  const payOnPad = payBeside === 'on' || !!insuranceBonus

  const showWellDisc = hasCost || payOnPad || occupied
  const wellText = occupied
    ? null
    : payOnPad
      ? `+${insuranceBonus ? 10 : payout}`
      : hasCost
        ? String(cost)
        : null

  const label =
    title ||
    (occupied
      ? ownerName || '已占用'
      : insuranceBonus || payOnPad
        ? '保险 · 立即 +10₱'
        : hasCost && hasPay
          ? `花费 ${cost} · 到账 ${payout}`
          : hasCost
            ? `花费 ${cost}`
            : hasPay
              ? `到账 ${payout}`
              : '空位')

  return (
    <button
      type="button"
      data-manila-slot={slotId || undefined}
      className={`manila-spot${live ? ' is-live' : ''}${taken || occupied ? ' is-taken' : ''}${
        roleSrc ? ' manila-spot--role' : ''
      }${payOnPad ? ' manila-spot--pay-on' : ''}${className ? ` ${className}` : ''}`}
      disabled={disabled || !onClick}
      onClick={onClick}
      title={label}
      aria-label={label}
    >
      {showWellDisc ? (
        <span
          className={`manila-spot__badge ${payOnPad ? 'manila-spot__badge--pay' : 'manila-spot__badge--cost'}`}
          aria-hidden
        >
          <img src={payOnPad ? SPOT_BADGE_PAY : SPOT_BADGE_COST} alt="" draggable={false} />
          {wellText != null ? <em>{wellText}</em> : null}
        </span>
      ) : null}

      {roleSrc ? (
        <span className="manila-spot__outer manila-spot__role" aria-hidden>
          <img src={roleSrc} alt="" draggable={false} />
        </span>
      ) : null}

      {occupied ? (
        <img className="manila-spot__meeple" src={meepleSrc(ownerSeat)} alt={ownerName || ''} />
      ) : null}
    </button>
  )
}

/** Yellow pay disc — parent must be the pay pad’s warped quad. */
export function ManilaPayBadge({ value }: { value: number }) {
  return (
    <span className="manila-spot manila-spot--pay-layer" aria-hidden>
      <span className="manila-spot__badge manila-spot__badge--pay">
        <img src={SPOT_BADGE_PAY} alt="" draggable={false} />
        <em>+{value}</em>
      </span>
    </span>
  )
}
