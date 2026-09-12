import type { ManilaMatch } from '@/api'
import { PRICE_MARKER, shareSrc, type ManilaRoleTag } from './assets'
import {
  BOARD_MARKET,
  berthConfig,
  marketPanelStyle,
  spotConfig,
  SHIP_SEATS_CFG,
} from './boardConfig'
import { berthQuad, costPadQuad } from './boardAnchors'
import {
  LANE_X,
  PIRATE_SEAT_POS,
  PIRATE_SLOT_IDS,
  PORT_BERTH,
  PORT_SPOT,
  SHORE_POS,
  TRACK_MAX,
  TRACK_NUM_X,
  YARD_BERTH,
  YARD_SPOT,
  berthHeading,
  nextPirateSlotId,
  trackY,
} from './boardLayout'
import { ManilaShipToken, type ShipSeat } from './ManilaShipToken'
import { ManilaSpot } from './ManilaSpot'
import { coverBerthStyle, padSpotStyle } from './quadWarp'
import { WARE_LABEL } from './rulesContent'

type SlotT = NonNullable<ManilaMatch['slots']>[number]
type PuntT = ManilaMatch['punts'][number]

function seatOf(players: ManilaMatch['players'], id?: string) {
  return players.find((p) => p.userId === id)?.seat ?? 0
}

function nameOf(players: ManilaMatch['players'], id?: string) {
  return players.find((p) => p.userId === id)?.username || '—'
}

function spotTitle(slot: SlotT) {
  const bits = [slot.label || slot.id]
  if (slot.kind !== 'insurance') bits.push(`花费 ${slot.cost}₱`)
  if (slot.payout > 0) bits.push(`到账 ${slot.payout}₱`)
  if (slot.kind === 'insurance') bits.push('立即 +10₱，之后赔修船')
  return bits.join(' · ')
}

type Shared = {
  match: ManilaMatch
  occupiedMap: Map<string, string>
  canPlace: boolean
  place: (slotId: string) => void
  sailing?: boolean
  startDraft?: [number, number, number]
  placingStarts?: boolean
  pilotNudge?: Record<number, number>
  bumpStart?: (lane: number, delta: number) => void
  startMax?: number
  /** BGA-style: nudge ship on board during pilot phase */
  onPilotDelta?: (puntIndex: number, delta: number) => void
  pilotBudgetLeft?: number
  /** BGA-style: board a ship during pirate_board */
  onPirateBoard?: (puntIndex: number) => void
  pirateBoardActive?: boolean
}

export function SeaCanvas({
  match,
  occupiedMap,
  canPlace,
  place,
  sailing,
  startDraft,
  placingStarts,
  pilotNudge,
  bumpStart,
  startMax = 5,
  onPilotDelta,
  pilotBudgetLeft,
  onPirateBoard,
  pirateBoardActive,
}: Shared) {
  const punts = match.punts || []

  return (
    <section className="manila-sea-canvas" aria-label="航线">
      <PirateBerth
        match={match}
        occupiedMap={occupiedMap}
        canPlace={canPlace}
        place={place}
        overlay
      />

      {punts.map((punt, i) =>
        renderSeaShip(punt, i, {
          match,
          occupiedMap,
          canPlace,
          place,
          sailing,
          startDraft,
          placingStarts,
          pilotNudge,
          bumpStart,
          startMax,
          onPilotDelta,
          pilotBudgetLeft,
          onPirateBoard,
          pirateBoardActive,
        }),
      )}
    </section>
  )
}


function renderSeaShip(punt: PuntT, i: number, ctx: Shared) {
  const {
    match,
    occupiedMap,
    canPlace,
    place,
    sailing,
    startDraft,
    placingStarts,
    pilotNudge,
    bumpStart,
    startMax = 5,
  } = ctx
  const draft = placingStarts && startDraft ? startDraft[i] : undefined
  const posN = draft ?? punt.position
  const atSea = !punt.arrived && !punt.berth
  if (!(atSea || placingStarts)) return null

  const puntSlots = (match.slots || [])
    .filter((s) => s.kind === 'punt' && s.puntIndex === punt.index)
    .sort((a, b) => (a.seatIndex || 0) - (b.seatIndex || 0))

  const seats: ShipSeat[] = puntSlots.map((slot) => {
    const owner = occupiedMap.get(slot.id)
    const free = !owner
    return {
      id: slot.id,
      cost: slot.cost,
      free,
      clickable: canPlace && free,
      ownerSeat: owner ? seatOf(match.players, owner) : undefined,
      ownerName: owner ? nameOf(match.players, owner) : undefined,
      onPlace: () => place(slot.id),
      title: spotTitle(slot),
    }
  })

  const lx = LANE_X[i] ?? LANE_X[1]
  const ly = trackY(posN)
  const nudge = pilotNudge?.[punt.index] ?? 0
  const draftVal = startDraft?.[i] ?? 0
  const seaRot = (SHIP_SEATS_CFG as { rot_deg?: { sea?: number } })?.rot_deg?.sea ?? 4

  return (
    <div
      key={punt.index}
      className="manila-sea-canvas__ship"
      data-manila-punt={punt.index}
      style={{
        left: `${lx}%`,
        top: `${ly}%`,
        transform: `translate(-50%, 0.45rem) rotate(${seaRot}deg)`,
        ['--ship-rot' as string]: `${seaRot}deg`,
      }}
    >
      {placingStarts && bumpStart ? (
        <div className="manila-sea-start" aria-label={`${WARE_LABEL[punt.ware] || '船'} 起点`}>
          <button
            type="button"
            className="manila-sea-start__spin"
            disabled={sailing || draftVal >= startMax}
            onClick={() => bumpStart(i, 1)}
          >
            ▲
          </button>
          <span className="manila-sea-start__val">{draftVal}</span>
          <button
            type="button"
            className="manila-sea-start__spin"
            disabled={sailing || draftVal <= 0}
            onClick={() => bumpStart(i, -1)}
          >
            ▼
          </button>
        </div>
      ) : null}
      <ManilaShipToken
        ware={punt.ware}
        seats={seats}
        sailing={sailing}
        heading="sea"
        die={punt.die || undefined}
        nudgeY={nudge}
      />
    </div>
  )
}

export function SeaTrackNums() {
  const nums = Array.from({ length: TRACK_MAX + 1 }, (_, n) => n)
  return (
    <ol className="manila-track-nums" aria-hidden>
      {nums.map((n) => (
        <li key={n} style={{ left: `${TRACK_NUM_X}%`, top: `${trackY(n)}%` }}>
          {n}
        </li>
      ))}
    </ol>
  )
}

export function MarketPlate({ match }: { match: ManilaMatch }) {
  const m = BOARD_MARKET
  const panel = marketPanelStyle()
  const valueCols = m.track_values?.length ? m.track_values : [...m.value_rows].reverse()
  return (
    <div className="manila-market-hit" aria-label={m.label}>
      <div className="manila-market-hit__panel" style={panel}>
        <div className="manila-market-hit__face">
          <div className="manila-market-hit__grid" role="table">
            {m.wares.map((ware) => {
              const price = match.market?.[ware] ?? 0
              return (
                <div key={ware} className="manila-market-hit__row" role="row">
                  <div className="manila-market-hit__ware" role="rowheader" title={WARE_LABEL[ware]}>
                    <img src={shareSrc(ware)} alt={WARE_LABEL[ware] || ware} draggable={false} />
                  </div>
                  <div className="manila-market-hit__track" role="cell">
                    {valueCols.map((value) => {
                      const here = price === value
                      return (
                        <span
                          key={`${ware}-${value}`}
                          className={`manila-market-hit__cell${here ? ' is-here' : ''}`}
                          aria-current={here ? 'true' : undefined}
                        >
                          <em>{value}</em>
                          {here ? (
                            <img className="manila-market-hit__pin" src={PRICE_MARKER} alt="" draggable={false} />
                          ) : null}
                        </span>
                      )
                    })}
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </div>
    </div>
  )
}

export function PortDock({
  match,
  occupiedMap,
  canPlace,
  place,
}: Omit<Shared, 'sailing' | 'startDraft' | 'placingStarts' | 'pilotNudge'>) {
  return (
    <aside className="manila-dock manila-dock--port" aria-label="马尼拉港">
      {(['A', 'B', 'C'] as const).map((letter) => {
        const slot = (match.slots || []).find((s) => s.id === `port_${letter}`)
        const ship = (match.punts || []).find((p) => p.berth === `port_${letter}`)
        const spot = PORT_SPOT[letter]
        const def = spotConfig(`port_${letter}`)
        const padQ = costPadQuad(`port_${letter}`)
        const quad = berthQuad(`port_${letter}`)
        const payBeside =
          def?.pad.display.pay_beside === 'left'
            ? 'left'
            : def?.pad.display.pay_beside === 'up-right'
              ? 'up-right'
              : 'right'
        const berthPos = PORT_BERTH[letter]
        return (
          <div key={letter} className="manila-dock__berth manila-dock__berth--port">
            <span
              className="manila-dock__letter manila-dock__letter--port"
              style={{ left: `${berthPos.x}%`, top: `${berthPos.y}%` }}
              aria-hidden
            >
              {letter}
            </span>
            {slot && padQ ? (
              <div className="manila-dock__spot manila-dock__spot--warped" style={padSpotStyle(padQ)}>
                <SpotFromSlot
                  slot={slot}
                  occupiedMap={occupiedMap}
                  players={match.players}
                  canPlace={canPlace}
                  place={place}
                  payBeside={payBeside}
                />
              </div>
            ) : slot ? (
              <div
                className="manila-dock__spot"
                style={{ left: `${spot.x}%`, top: `${spot.y}%` }}
              >
                <SpotFromSlot
                  slot={slot}
                  occupiedMap={occupiedMap}
                  players={match.players}
                  canPlace={canPlace}
                  place={place}
                  payBeside={payBeside}
                />
              </div>
            ) : null}
            {ship && quad ? (
              <div
                className="manila-dock__ship"
                data-manila-berth-punt={ship.index}
                style={coverBerthStyle(
                  quad,
                  'port',
                  berthConfig(`port_${letter}`)?.ship_rot_deg,
                )}
              >
                <ManilaShipToken ware={ship.ware} seats={[]} heading="port" compact />
              </div>
            ) : null}
          </div>
        )
      })}
    </aside>
  )
}

export function YardDock({
  match,
  occupiedMap,
  canPlace,
  place,
}: Omit<Shared, 'sailing' | 'startDraft' | 'placingStarts' | 'pilotNudge'>) {
  return (
    <aside className="manila-dock manila-dock--yard" aria-label="修船厂">
      {(['A', 'B', 'C'] as const).map((letter) => {
        const slot = (match.slots || []).find((s) => s.id === `shipyard_${letter}`)
        const ship = (match.punts || []).find((p) => p.berth === `shipyard_${letter}`)
        const spot = YARD_SPOT[letter]
        const def = spotConfig(`shipyard_${letter}`)
        const padQ = costPadQuad(`shipyard_${letter}`)
        const quad = berthQuad(`yard_${letter}`)
        const payBeside =
          def?.pad.display.pay_beside === 'up-right'
            ? 'up-right'
            : def?.pad.display.pay_beside === 'left'
              ? 'left'
              : 'right'
        const berthPos = YARD_BERTH[letter]
        return (
          <div key={letter} className="manila-dock__berth manila-dock__berth--yard">
            <span
              className="manila-dock__letter manila-dock__letter--yard"
              style={{ left: `${berthPos.x}%`, top: `${berthPos.y}%` }}
              aria-hidden
            >
              {letter}
            </span>
            {slot && padQ ? (
              <div className="manila-dock__spot manila-dock__spot--warped" style={padSpotStyle(padQ)}>
                <SpotFromSlot
                  slot={slot}
                  occupiedMap={occupiedMap}
                  players={match.players}
                  canPlace={canPlace}
                  place={place}
                  payBeside={payBeside}
                />
              </div>
            ) : slot ? (
              <div
                className="manila-dock__spot"
                style={{ left: `${spot.x}%`, top: `${spot.y}%` }}
              >
                <SpotFromSlot
                  slot={slot}
                  occupiedMap={occupiedMap}
                  players={match.players}
                  canPlace={canPlace}
                  place={place}
                  payBeside={payBeside}
                />
              </div>
            ) : null}
            {ship && quad ? (
              <div
                className="manila-dock__ship"
                data-manila-berth-punt={ship.index}
                style={coverBerthStyle(
                  quad,
                  'yard',
                  berthConfig(`yard_${letter}`)?.ship_rot_deg,
                )}
              >
                <ManilaShipToken ware={ship.ware} seats={[]} heading="yard" compact />
              </div>
            ) : null}
          </div>
        )
      })}
    </aside>
  )
}

export function PirateBerth({
  match,
  occupiedMap,
  canPlace,
  place,
}: Omit<Shared, 'sailing' | 'startDraft' | 'placingStarts' | 'pilotNudge'> & {
  overlay?: boolean
}) {
  const nextId = nextPirateSlotId(occupiedMap)

  // Scenic board.jpg already paints the pirate boat — only seat hits on top.
  return (
    <aside className="manila-pirate-seats" aria-label="海盗座位">
      {PIRATE_SLOT_IDS.map((id, i) => {
        const slot = (match.slots || []).find((s) => s.id === id)
        const owner = occupiedMap.get(id)
        const isNext = id === nextId
        const clickable = canPlace && isNext && !!slot
        const pos = PIRATE_SEAT_POS[i]
        return (
          <div
            key={id}
            className="manila-pirate-seats__seat"
            style={{ left: `${pos.x}%`, top: `${pos.y}%` }}
          >
            <ManilaSpot
              slotId={id}
              cost={slot && !owner ? slot.cost : null}
              ownerSeat={owner ? seatOf(match.players, owner) : undefined}
              ownerName={owner ? nameOf(match.players, owner) : undefined}
              live={clickable}
              taken={!!owner}
              disabled={!clickable}
              title={
                owner
                  ? nameOf(match.players, owner)
                  : isNext
                    ? `海盗 · 花费 ${slot?.cost ?? 5}₱（须从船头依次入座）`
                    : '须先占前方座位'
              }
              onClick={clickable ? () => place(id) : undefined}
            />
          </div>
        )
      })}
    </aside>
  )
}

export function ShoreModule({
  slotId,
  label,
  match,
  occupiedMap,
  canPlace,
  place,
}: Omit<Shared, 'sailing' | 'startDraft' | 'placingStarts' | 'pilotNudge'> & {
  slotId: string
  label: string
}) {
  const slot = (match.slots || []).find((s) => s.id === slotId)
  const pos = SHORE_POS[slotId]
  if (!slot || !pos) return null
  return (
    <aside
      className={`manila-module manila-module--hit manila-module--${slotId}`}
      style={{ left: `${pos.x}%`, top: `${pos.y}%` }}
      aria-label={label}
    >
      <SpotFromSlot
        slot={slot}
        occupiedMap={occupiedMap}
        players={match.players}
        canPlace={canPlace}
        place={place}
        payBeside="right"
      />
    </aside>
  )
}

function SpotFromSlot({
  slot,
  occupiedMap,
  players,
  canPlace,
  place,
  payBeside,
}: {
  slot: SlotT
  occupiedMap: Map<string, string>
  players: ManilaMatch['players']
  canPlace: boolean
  place: (id: string) => void
  payBeside?: 'left' | 'right' | 'up-right' | 'on'
}) {
  const owner = occupiedMap.get(slot.id)
  const free = !owner
  const clickable = canPlace && free
  const cfg = spotConfig(slot.id)
  const beside = payBeside ?? cfg?.pad.display.pay_beside
  const roleTag =
    slot.id === 'pilot_small' || slot.id === 'pilot_large' || slot.id === 'insurance'
      ? (slot.id as ManilaRoleTag)
      : null
  const isInsurance = slot.kind === 'insurance'
  return (
    <ManilaSpot
      slotId={slot.id}
      cost={isInsurance ? null : slot.cost}
      payout={isInsurance ? 10 : slot.payout > 0 ? slot.payout : null}
      insuranceBonus={isInsurance}
      roleTag={isInsurance ? null : roleTag}
      payBeside={isInsurance ? 'on' : beside === 'none' ? undefined : beside}
      ownerSeat={owner ? seatOf(players, owner) : undefined}
      ownerName={owner ? nameOf(players, owner) : undefined}
      live={clickable}
      taken={!free}
      disabled={!clickable}
      title={spotTitle(slot)}
      onClick={clickable ? () => place(slot.id) : undefined}
    />
  )
}

export { berthHeading, WARE_LABEL }
