import type { ManilaMatch, ManilaWare } from '@/api'
import { PRICE_MARKER, shareSrc } from './assets'
import { useBoardPx } from './BoardPx'
import {
  BOARD_MARKET,
  berthConfig,
  marketPanelBox,
  marketPanelStyle,
  payPadQuad,
  spotConfig,
  type RoleTagId,
} from './boardConfig'
import { berthQuad, costPadQuad } from './boardAnchors'
import {
  PIRATE_SEAT_POS,
  PIRATE_SLOT_IDS,
  PORT_BERTH,
  PORT_SPOT,
  SHORE_POS,
  YARD_BERTH,
  YARD_SPOT,
  WARE_SEAT_COSTS,
  berthHeading,
  lanePose,
  nextPirateSlotId,
  nextPuntSeatId,
} from './boardLayout'
import { ManilaShipToken, type ShipSeat } from './ManilaShipToken'
import { ManilaPayBadge, ManilaSpot } from './ManilaSpot'
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

  const fallbackCosts = WARE_SEAT_COSTS[punt.ware] || [3, 4, 5]
  const seatCount = puntSlots.length > 0 ? puntSlots.length : fallbackCosts.length
  const nextSeatId = nextPuntSeatId(punt.index, seatCount, occupiedMap)

  const seats: ShipSeat[] =
    puntSlots.length > 0
      ? puntSlots.map((slot) => {
          const owner = occupiedMap.get(slot.id)
          const free = !owner
          const isNext = free && slot.id === nextSeatId
          return {
            id: slot.id,
            cost: slot.cost,
            free,
            clickable: canPlace && isNext,
            ownerSeat: owner ? seatOf(match.players, owner) : undefined,
            ownerName: owner ? nameOf(match.players, owner) : undefined,
            onPlace: () => place(slot.id),
            title: isNext
              ? `${spotTitle(slot)}（须从前往后入座）`
              : free
                ? `${spotTitle(slot)}（请先坐船头空位）`
                : spotTitle(slot),
          }
        })
      : fallbackCosts.map((cost, seatIndex) => {
          const id = `punt${punt.index}_${seatIndex}`
          const owner = occupiedMap.get(id)
          const free = !owner
          const isNext = free && id === nextSeatId
          return {
            id,
            cost,
            free,
            clickable: canPlace && isNext,
            ownerSeat: owner ? seatOf(match.players, owner) : undefined,
            ownerName: owner ? nameOf(match.players, owner) : undefined,
            onPlace: () => place(id),
            title: isNext
              ? `${WARE_LABEL[punt.ware] || '船'} · 花费 ${cost}₱（须从前往后入座）`
              : free
                ? `${WARE_LABEL[punt.ware] || '船'} · 花费 ${cost}₱（请先坐船头空位）`
                : `${WARE_LABEL[punt.ware] || '船'} · 花费 ${cost}₱`,
          }
        })

  const pose = lanePose(i, posN)
  const nudge = pilotNudge?.[punt.index] ?? 0
  const draftVal = startDraft?.[i] ?? 0

  return (
    <div
      key={punt.index}
      className="manila-sea-canvas__ship"
      data-manila-punt={punt.index}
      style={{
        left: `${pose.x}%`,
        top: `${pose.y}%`,
        transform: `translate(-50%, -50%) rotate(${pose.rot}deg)`,
        ['--ship-rot' as string]: `${pose.rot}deg`,
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
      ) : atSea ? (
        <span className="manila-sea-pos" aria-label={`航位 ${posN}`}>
          {posN}
        </span>
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

/** Stock panel — geometry mirrors `_rebuild_spots.py` bake (pad / row / icon fractions of panel px). */
export function MarketPlate({ match }: { match: ManilaMatch }) {
  const m = BOARD_MARKET
  const panel = marketPanelStyle()
  const box = marketPanelBox()
  const { w: boardW, h: boardH } = useBoardPx()
  const valueCols = m.track_values?.length ? m.track_values : [...m.value_rows].reverse()
  const pw = boardW > 1 ? (box.w / 100) * boardW : 0
  const ph = boardH > 1 ? (box.h / 100) * boardH : 0
  const ready = pw > 8 && ph > 8
  const pad = ready ? Math.max(4, Math.round(Math.min(pw, ph) * 0.034)) : 0
  const bodyH = ready ? ph - pad * 2 : 0
  const rowH = ready ? bodyH / 4 : 0
  const iconS = ready ? Math.max(12, Math.round(rowH * 0.78)) : 0
  const trackX0 = ready ? pad + iconS + Math.max(6, Math.round(pw * 0.026)) : 0
  const trackW = ready ? pw - trackX0 - pad : 0
  const cellW = ready ? trackW / valueCols.length : 0
  const fontPx = ready ? Math.max(10, Math.round(rowH * 0.4)) : 0
  const pinS = ready ? Math.max(10, Math.round(rowH * 0.55)) : 0

  return (
    <div className="manila-market-hit" aria-label={m.label}>
      <div className="manila-market-hit__panel" style={panel}>
        <div className="manila-market-hit__face manila-market-hit__face--abs">
          {m.wares.map((ware, ri) => {
            const w = ware as ManilaWare
            const price = match.market?.[w] ?? 0
            const y0 = pad + rowH * ri
            const yMid = y0 + rowH * 0.5
            return (
              <div key={w} className="manila-market-hit__row-abs" role="row">
                {ri % 2 === 1 && ready ? (
                  <div
                    className="manila-market-hit__row-bg"
                    style={{
                      left: 4,
                      top: y0 + 1,
                      width: pw - 8,
                      height: Math.max(0, rowH - 2),
                    }}
                    aria-hidden
                  />
                ) : null}
                {ready ? (
                  <img
                    className="manila-market-hit__ware-abs"
                    src={shareSrc(w)}
                    alt={WARE_LABEL[w] || w}
                    title={WARE_LABEL[w]}
                    draggable={false}
                    style={{
                      left: pad,
                      top: yMid - iconS / 2,
                      width: iconS,
                      height: iconS,
                    }}
                  />
                ) : null}
                {ready
                  ? valueCols.map((value, ci) => {
                      const here = price === value
                      const x0 = trackX0 + cellW * ci + 2
                      const cellH = rowH * 0.64
                      return (
                        <span
                          key={`${w}-${value}`}
                          className={`manila-market-hit__cell-abs${here ? ' is-here' : ''}`}
                          aria-current={here ? 'true' : undefined}
                          style={{
                            left: x0,
                            top: yMid - cellH / 2,
                            width: Math.max(0, cellW - 4),
                            height: cellH,
                            fontSize: fontPx,
                          }}
                        >
                          <em>{value}</em>
                          {here ? (
                            <img
                              className="manila-market-hit__pin-abs"
                              src={PRICE_MARKER}
                              alt=""
                              draggable={false}
                              style={{
                                width: pinS,
                                height: pinS,
                                right: -pinS * 0.15,
                                bottom: -pinS * 0.2,
                              }}
                            />
                          ) : null}
                        </span>
                      )
                    })
                  : null}
              </div>
            )
          })}
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
  const { w: boardW, h: boardH } = useBoardPx()
  /* BERTH_LETTER_PX=46 @ 1024 plate — keep CSS px so zoom matches effect bake */
  const letterPx = boardW > 1 ? Math.max(10, (boardW * 46) / 1024) : undefined
  return (
    <aside className="manila-dock manila-dock--port" aria-label="马尼拉港">
      {(['A', 'B', 'C'] as const).map((letter) => {
        const slot = (match.slots || []).find((s) => s.id === `port_${letter}`)
        const ship = (match.punts || []).find((p) => p.berth === `port_${letter}`)
        const spot = PORT_SPOT[letter]
        const bCfg = berthConfig(`port_${letter}`)
        const padQ = costPadQuad(`port_${letter}`)
        const quad = berthQuad(`port_${letter}`)
        const berthPos = bCfg?.center ?? PORT_BERTH[letter]
        const label = (bCfg?.display.letter ?? letter) || letter
        return (
          <div key={letter} className="manila-dock__berth manila-dock__berth--port">
            {/* Letters sit on water slips; hide under docked ships (same as board-effect bake) */}
            {!ship ? (
              <span
                className="manila-dock__letter manila-dock__letter--port"
                style={{
                  left: `${berthPos.x}%`,
                  top: `${berthPos.y}%`,
                  ...(letterPx ? { fontSize: letterPx } : null),
                }}
                aria-hidden
              >
                {label}
              </span>
            ) : null}
            {slot && padQ ? (
              <WarpedBoardSpot
                slot={slot}
                occupiedMap={occupiedMap}
                players={match.players}
                canPlace={canPlace}
                place={place}
                boardW={boardW}
                boardH={boardH}
              />
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
  const { w: boardW, h: boardH } = useBoardPx()
  const letterPx = boardW > 1 ? Math.max(10, (boardW * 46) / 1024) : undefined
  return (
    <aside className="manila-dock manila-dock--yard" aria-label="修船厂">
      {(['A', 'B', 'C'] as const).map((letter) => {
        const slot = (match.slots || []).find((s) => s.id === `shipyard_${letter}`)
        const ship = (match.punts || []).find((p) => p.berth === `shipyard_${letter}`)
        const spot = YARD_SPOT[letter]
        const bCfg = berthConfig(`yard_${letter}`)
        const padQ = costPadQuad(`shipyard_${letter}`)
        const quad = berthQuad(`yard_${letter}`)
        const berthPos = bCfg?.center ?? YARD_BERTH[letter]
        const label = (bCfg?.display.letter ?? letter) || letter
        return (
          <div key={letter} className="manila-dock__berth manila-dock__berth--yard">
            {!ship ? (
              <span
                className="manila-dock__letter manila-dock__letter--yard"
                style={{
                  left: `${berthPos.x}%`,
                  top: `${berthPos.y}%`,
                  ...(letterPx ? { fontSize: letterPx } : null),
                }}
                aria-hidden
              >
                {label}
              </span>
            ) : null}
            {slot && padQ ? (
              <WarpedBoardSpot
                slot={slot}
                occupiedMap={occupiedMap}
                players={match.players}
                canPlace={canPlace}
                place={place}
                boardW={boardW}
                boardH={boardH}
              />
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
  const { w: boardW, h: boardH } = useBoardPx()
  const nextId = nextPirateSlotId(occupiedMap)

  // Scenic board.jpg already paints the pirate boat — only seat hits on top.
  return (
    <aside className="manila-pirate-seats" aria-label="海盗座位">
      {PIRATE_SLOT_IDS.map((id, i) => {
        const slot = (match.slots || []).find((s) => s.id === id)
        const owner = occupiedMap.get(id)
        const isNext = id === nextId
        const clickable = canPlace && isNext && !!slot
        const padQ = costPadQuad(id)
        const fallback = PIRATE_SEAT_POS[i]
        if (!slot) return null
        const body = (
          <ManilaSpot
            slotId={id}
            cost={!owner ? slot.cost : null}
            ownerSeat={owner ? seatOf(match.players, owner) : undefined}
            ownerName={owner ? nameOf(match.players, owner) : undefined}
            live={clickable}
            taken={!!owner}
            disabled={!clickable}
            title={
              owner
                ? nameOf(match.players, owner)
                : isNext
                  ? `海盗 · 花费 ${slot.cost ?? 5}₱（须从右侧依次入座）`
                  : '须先占前方座位'
            }
            onClick={clickable ? () => place(id) : undefined}
          />
        )
        if (padQ) {
          return (
            <div
              key={id}
              className="manila-pirate-seats__seat manila-pirate-seats__seat--warped"
              style={padSpotStyle(padQ, boardW, boardH)}
            >
              {body}
            </div>
          )
        }
        return (
          <div
            key={id}
            className="manila-pirate-seats__seat"
            style={{ left: `${fallback.x}%`, top: `${fallback.y}%` }}
          >
            {body}
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
  const { w: boardW, h: boardH } = useBoardPx()
  const slot = (match.slots || []).find((s) => s.id === slotId)
  const padQ = costPadQuad(slotId)
  const pos = SHORE_POS[slotId]
  if (!slot) return null
  if (padQ) {
    return (
      <aside className="manila-module manila-module--shore-wrap" aria-label={label}>
        <WarpedBoardSpot
          slot={slot}
          occupiedMap={occupiedMap}
          players={match.players}
          canPlace={canPlace}
          place={place}
          boardW={boardW}
          boardH={boardH}
        />
      </aside>
    )
  }
  if (!pos) return null
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
}: {
  slot: SlotT
  occupiedMap: Map<string, string>
  players: ManilaMatch['players']
  canPlace: boolean
  place: (id: string) => void
}) {
  const owner = occupiedMap.get(slot.id)
  const free = !owner
  const clickable = canPlace && free
  const cfg = spotConfig(slot.id)
  const roleTag = (cfg?.pad.display.role_tag ?? null) as RoleTagId | null
  const isInsurance = slot.kind === 'insurance'
  return (
    <ManilaSpot
      slotId={slot.id}
      cost={isInsurance ? null : slot.cost}
      payout={isInsurance ? 10 : slot.payout > 0 ? slot.payout : null}
      insuranceBonus={isInsurance}
      roleTag={roleTag}
      payBeside={isInsurance ? 'on' : undefined}
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

/** Cost + pay from boardConfig: quad warp, or centered circle (insurance bake). */
function WarpedBoardSpot({
  slot,
  occupiedMap,
  players,
  canPlace,
  place,
  boardW,
  boardH,
}: {
  slot: SlotT
  occupiedMap: Map<string, string>
  players: ManilaMatch['players']
  canPlace: boolean
  place: (id: string) => void
  boardW: number
  boardH: number
}) {
  const cfg = spotConfig(slot.id)
  const padQ = costPadQuad(slot.id)
  const payQ = payPadQuad(slot.id)
  const disp = cfg?.pad.display
  const centered = disp?.paste_mode === 'centered'
  const badgeD = disp?.badge_d_px ?? 56
  const showPay = Boolean(payQ && slot.payout > 0 && !centered && disp?.pay_beside !== 'on')

  if (centered && cfg) {
    const c = cfg.pad.center
    const dPct = (badgeD / 1024) * 100
    return (
      <div
        className="manila-dock__spot manila-dock__spot--centered"
        data-manila-pay={slot.id}
        style={{
          left: `${c.x}%`,
          top: `${c.y}%`,
          width: `${dPct}%`,
          height: `${dPct}%`,
          transform: 'translate(-50%, -50%)',
        }}
      >
        <SpotFromSlot
          slot={slot}
          occupiedMap={occupiedMap}
          players={players}
          canPlace={canPlace}
          place={place}
        />
      </div>
    )
  }

  if (!padQ) return null
  const payStyle = payQ && showPay ? padSpotStyle(payQ, boardW, boardH) : null
  return (
    <>
      {payStyle ? (
        <div
          className="manila-dock__pay manila-dock__pay--warped"
          data-manila-pay={slot.id}
          style={payStyle}
          aria-hidden
        >
          <ManilaPayBadge value={slot.payout} />
        </div>
      ) : null}
      <div
        className="manila-dock__spot manila-dock__spot--warped"
        style={padSpotStyle(padQ, boardW, boardH)}
      >
        <SpotFromSlot
          slot={slot}
          occupiedMap={occupiedMap}
          players={players}
          canPlace={canPlace}
          place={place}
        />
      </div>
    </>
  )
}

export { berthHeading, WARE_LABEL }
