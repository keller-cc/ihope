import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react'
import type { ManilaMatch, ManilaWare } from '@/api'
import {
  COIN,
  meepleSrc,
  PANEL_WOOD,
  PAWN_LABEL,
  shareCardSrc,
} from './assets'
import {
  LOAN_AMOUNT,
  REPAY_AMOUNT,
  START_MAX,
  BOARD_IMG,
  HULL_3,
  HULL_4,
  WARE_PROFIT,
  WARE_SEATS,
} from './boardLayout'
import {
  MarketPlate,
  PortDock,
  SeaCanvas,
  ShoreModule,
  YardDock,
} from './ManilaBoardModules'
import { BoardPxProvider } from './BoardPx'
import { ManilaDiceOverlay } from './ManilaDiceOverlay'
import { ManilaSettlePanel } from './ManilaSettlePanel'
import {
  ManilaFlyLayer,
  ManilaPayFlyLayer,
  type FlyMeeple,
  type FlyPay,
  railMeepleEl,
  railCashEl,
  rectCenter,
  slotHitEl,
  puntShipEl,
  pirateSeatEl,
  payoutOriginEl,
  FX_PLACE_MS,
  FX_PLACE_COMMIT_MS,
  FX_HOME_MS,
  FX_BOARD_MS,
  FX_SAIL_MS,
  FX_PAY_MS,
  FX_SHIP_MOVE_MS,
} from './ManilaFx'
import { PHASE_LABEL, WARE_LABEL } from './rulesContent'

const WARES: ManilaWare[] = ['nutmeg', 'silk', 'ginseng', 'jade']

type Props = {
  match: ManilaMatch
  meId: string | undefined
  send: (msg: Record<string, unknown>) => void
}

/** 现金/比索显示：统一用特朗普金币图标 */
function Cash({
  n,
  signed,
  className,
}: {
  n: number
  signed?: boolean
  className?: string
}) {
  const text = signed ? (n > 0 ? `+${n}` : `${n}`) : `${n}`
  return (
    <span className={`manila-cash${className ? ` ${className}` : ''}`}>
      <img src={COIN} alt="" className="manila-cash__ico" />
      <em>{text}</em>
    </span>
  )
}

export function ManilaBoard({ match, meId, send }: Props) {
  const myTurn = match.turnUserId === meId
  const isHM = match.harborMasterId === meId
  const me = match.players.find((p) => p.userId === meId)
  const placingStarts = match.phase === 'hm_place' && isHM
  const [startDraft, setStartDraft] = useState<[number, number, number]>([3, 3, 3])
  const [sailing, setSailing] = useState(false)
  const [pilotNudge, setPilotNudge] = useState<Record<number, number>>({})

  useEffect(() => {
    if (match.phase === 'hm_place') {
      setStartDraft([3, 3, 3])
      setSailing(false)
    }
  }, [match.phase, match.voyage])

  const canPlace = myTurn && match.phase === 'place' && !me?.passedPlacement
  const [pendingSlot, setPendingSlot] = useState<string | null>(null)
  const [flights, setFlights] = useState<FlyMeeple[]>([])
  const [payFlights, setPayFlights] = useState<FlyPay[]>([])
  const [sailGhosts, setSailGhosts] = useState<
    { id: string; ware: string; from: { x: number; y: number }; to: { x: number; y: number }; kind: 'port' | 'yard' }[]
  >([])
  const [holdShipPos, setHoldShipPos] = useState<Record<number, number> | null>(null)
  const [suppressBerth, setSuppressBerth] = useState(false)
  const prevOccRef = useRef<Map<string, string>>(new Map())
  const prevBerthRef = useRef<Record<number, string | undefined>>({})
  const prevCashRef = useRef<Record<string, number>>({})
  const cashReadyRef = useRef(false)

  const occupiedMap = useMemo(() => {
    const m = new Map<string, string>()
    const occ = match.occupied as unknown
    if (Array.isArray(occ)) {
      for (const o of occ as { slotId: string; userId: string }[]) {
        m.set(o.slotId, o.userId)
      }
    } else if (occ && typeof occ === 'object') {
      for (const [slotId, uid] of Object.entries(occ as Record<string, string>)) {
        m.set(slotId, uid)
      }
    }
    return m
  }, [match.occupied])

  const pendingDef = pendingSlot
    ? (match.slots || []).find((s) => s.id === pendingSlot)
    : null

  const requestPlace = (slotId: string) => {
    if (!canPlace) return
    setPendingSlot(slotId)
  }

  const cancelPlace = () => setPendingSlot(null)

  const confirmPlace = () => {
    if (!pendingSlot || !canPlace || !meId || me == null) return
    const slotId = pendingSlot
    const from = rectCenter(railMeepleEl(meId))
    const to = rectCenter(slotHitEl(slotId))
    setPendingSlot(null)
    if (from && to) {
      const id = `place-${slotId}-${Date.now()}`
      setFlights((prev) => [...prev, { id, seat: me.seat, from, to, durationMs: FX_PLACE_MS }])
      window.setTimeout(() => send({ type: 'place', slotId }), FX_PLACE_COMMIT_MS)
    } else {
      send({ type: 'place', slotId })
    }
  }

  useEffect(() => {
    document.querySelectorAll('.manila-spot.is-pending').forEach((el) => el.classList.remove('is-pending'))
    if (!pendingSlot) return
    document.querySelector(`[data-manila-slot="${pendingSlot}"]`)?.classList.add('is-pending')
  }, [pendingSlot])

  useEffect(() => {
    if (!canPlace) setPendingSlot(null)
  }, [canPlace, match.turnUserId])

  // Detect new occupations / berths for pirate kick-home & sail-in ghosts
  useEffect(() => {
    const prev = prevOccRef.current
    const next = occupiedMap
    const added: { slotId: string; userId: string }[] = []
    const removed: { slotId: string; userId: string }[] = []
    for (const [slotId, uid] of next) {
      if (prev.get(slotId) !== uid) {
        if (prev.has(slotId) && prev.get(slotId) !== uid) {
          removed.push({ slotId, userId: prev.get(slotId)! })
        }
        if (!prev.has(slotId) || prev.get(slotId) !== uid) {
          added.push({ slotId, userId: uid })
        }
      }
    }
    for (const [slotId, uid] of prev) {
      if (!next.has(slotId)) removed.push({ slotId, userId: uid })
    }

    // Kicked / left seats → fly home to rail
    for (const r of removed) {
      const stillElsewhere = [...next.values()].includes(r.userId)
      // If they also appear in added (moved seat), skip home-fly unless leaving ship entirely
      const movedTo = added.find((a) => a.userId === r.userId)
      if (movedTo) continue
      if (stillElsewhere) continue
      const pl = match.players.find((p) => p.userId === r.userId)
      const from = rectCenter(slotHitEl(r.slotId))
      const to = rectCenter(railMeepleEl(r.userId))
      if (pl && from && to) {
        const id = `home-${r.slotId}-${Date.now()}`
        setFlights((prevF) => [...prevF, { id, seat: pl.seat, from, to, durationMs: FX_HOME_MS }])
      }
    }

    // Pirate boarding: pirate_* → punt seat
    for (const a of added) {
      if (!a.slotId.startsWith('punt')) continue
      const leftPirate = removed.find(
        (r) => r.userId === a.userId && r.slotId.startsWith('pirate_'),
      )
      if (!leftPirate) continue
      const pl = match.players.find((p) => p.userId === a.userId)
      const from = rectCenter(slotHitEl(leftPirate.slotId)) || rectCenter(pirateSeatEl(0))
      const to = rectCenter(slotHitEl(a.slotId)) || rectCenter(puntShipEl(Number(a.slotId.split('_')[1] || 0)))
      if (pl && from && to) {
        const id = `board-${a.slotId}-${Date.now()}`
        setFlights((prevF) => [...prevF, { id, seat: pl.seat, from, to, durationMs: FX_BOARD_MS }])
      }
    }

    prevOccRef.current = new Map(next)
  }, [occupiedMap, match.players])

  // Sail into port / shipyard when berth newly assigned (after ship slide finishes)
  useEffect(() => {
    if (suppressBerth) return
    const prev = prevBerthRef.current
    const next: Record<number, string | undefined> = {}
    for (const p of match.punts || []) {
      next[p.index] = p.berth
      const was = prev[p.index]
      if (p.berth && p.berth !== was) {
        const kind = p.berth.startsWith('port_') ? 'port' : 'yard'
        const fromEl = document.querySelector(`[data-manila-punt="${p.index}"]`)
        const toEl = document.querySelector(`[data-manila-berth-punt="${p.index}"]`)
        const from = rectCenter(fromEl)
        window.requestAnimationFrame(() => {
          const to =
            rectCenter(document.querySelector(`[data-manila-berth-punt="${p.index}"]`)) ||
            rectCenter(toEl)
          if (!from || !to) return
          const id = `sail-${p.index}-${Date.now()}`
          setSailGhosts((g) => [...g, { id, ware: p.ware, from, to, kind }])
          window.setTimeout(() => {
            setSailGhosts((g) => g.filter((x) => x.id !== id))
          }, FX_SAIL_MS + 40)
        })
      }
    }
    prevBerthRef.current = next
  }, [match.punts, suppressBerth])

  // Cash gains → yellow +N (skip when settlement lines drive the FX)
  useEffect(() => {
    const next: Record<string, number> = {}
    for (const p of match.players) next[p.userId] = p.cash ?? 0
    if (!cashReadyRef.current) {
      prevCashRef.current = next
      cashReadyRef.current = true
      return
    }
    if (match.phase === 'settle' && (match.settlement?.length ?? 0) > 0) {
      prevCashRef.current = next
      return
    }
    const prev = prevCashRef.current
    const spawned: FlyPay[] = []
    let stagger = 0
    for (const p of match.players) {
      const before = prev[p.userId]
      if (before == null) continue
      const delta = (p.cash ?? 0) - before
      if (delta === 0) continue
      const fromEl = payoutOriginEl(p.userId, occupiedMap)
      const from = rectCenter(fromEl)
      const to = rectCenter(railCashEl(p.userId))
      if (!from || !to) continue
      const id = `pay-${p.userId}-${delta}-${Date.now()}-${stagger}`
      spawned.push({
        id,
        amount: delta,
        from: { x: from.x, y: from.y - stagger * 10 },
        to,
        durationMs: FX_PAY_MS + stagger * 90,
      })
      stagger += 1
    }
    if (spawned.length) {
      window.requestAnimationFrame(() => {
        setPayFlights((f) => [...f, ...spawned])
      })
    }
    prevCashRef.current = next
  }, [match.players, occupiedMap, match.phase, match.settlement])

  // Voyage settle UI is driven by ManilaSettlePanel (sequential + roster).
  // Keep cash baseline in sync so we don't double-fly when auction resumes.
  useEffect(() => {
    if (match.phase !== 'settle') return
    const next: Record<string, number> = {}
    for (const p of match.players) next[p.userId] = p.cash ?? 0
    prevCashRef.current = next
  }, [match.phase, match.players])

  const place = requestPlace

  const startSum = startDraft[0] + startDraft[1] + startDraft[2]
  const stageRef = useRef<HTMLDivElement>(null)
  const startValid =
    startSum === 9 && startDraft.every((p) => p >= 0 && p <= START_MAX)

  const bumpStart = (i: number, delta: number) => {
    setStartDraft((prev) => {
      const next: [number, number, number] = [prev[0], prev[1], prev[2]]
      next[i] = Math.max(0, Math.min(START_MAX, prev[i] + delta))
      return next
    })
  }

  const confirmStarts = () => {
    if (!startValid || sailing) return
    setSailing(true)
    window.setTimeout(() => {
      send({ type: 'place_punts', positions: [...startDraft] })
    }, 780)
  }

  const sendWithPilotAnim = (msg: Record<string, unknown>) => {
    if (msg.type === 'pilot' && !msg.skip && Array.isArray(msg.moves)) {
      const nudge: Record<number, number> = {}
      for (const m of msg.moves as { punt: number; delta: number }[]) {
        if (m.delta) nudge[m.punt] = m.delta * -14
      }
      setPilotNudge(nudge)
      window.setTimeout(() => setPilotNudge({}), 900)
    }
    send(msg)
  }

  const banner = turnBanner(match, isHM, myTurn, canPlace, placingStarts)
  const forced = needsForcedAction(match, isHM, myTurn, placingStarts)
  const showModal = forced

  const [diceAnim, setDiceAnim] = useState<number[] | null>(null)
  const [dicePending, setDicePending] = useState(false)
  const [actionCollapsed, setActionCollapsed] = useState(false)
  const prevDiceKey = useRef('')
  useEffect(() => {
    const rolling = (match.punts || []).filter((p) => (p.die || 0) > 0)
    if (rolling.length === 0) return
    const key = `${match.voyage}-${match.moveRound}-${rolling.map((p) => `${p.index}:${p.die}`).join(',')}`
    if (key === prevDiceKey.current) return
    prevDiceKey.current = key
    const hold: Record<number, number> = {}
    for (const p of match.punts || []) {
      hold[p.index] = p.die ? Math.max(0, (p.position || 0) - p.die) : p.position
    }
    setHoldShipPos(hold)
    setSuppressBerth(true)
    setDiceAnim(rolling.map((p) => p.die as number))
    setDicePending(false)
  }, [match.punts, match.voyage, match.moveRound])

  const releaseShipsAfterDice = () => {
    setDiceAnim(null)
    setDicePending(false)
    setHoldShipPos(null)
    window.setTimeout(() => setSuppressBerth(false), FX_SHIP_MOVE_MS)
  }

  useEffect(() => {
    setActionCollapsed(false)
  }, [match.phase, match.turnUserId, match.harborMasterId])

  useEffect(() => {
    if (match.phase !== 'dice') setDicePending(false)
  }, [match.phase])

  useEffect(() => {
    if (!dicePending) return
    const t = window.setTimeout(() => setDicePending(false), 10000)
    return () => window.clearTimeout(t)
  }, [dicePending])

  const rollDice = () => {
    if (dicePending) return
    setDicePending(true)
    send({ type: 'roll_dice' })
  }

  const boardMatch = useMemo(() => {
    if (!holdShipPos && !suppressBerth) return match
    return {
      ...match,
      punts: (match.punts || []).map((p) => {
        const held = holdShipPos?.[p.index]
        const hideBerth = Boolean(holdShipPos) || suppressBerth
        return {
          ...p,
          position: held ?? p.position,
          ...(hideBerth && p.berth
            ? { arrived: false as const, berth: undefined }
            : null),
        }
      }),
    }
  }, [match, holdShipPos, suppressBerth])

  return (
    <div className="manila-board">
      <ManilaDiceOverlay
        values={diceAnim}
        pending={dicePending}
        onDone={releaseShipsAfterDice}
      />
      <ManilaFlyLayer
        flights={flights}
        onDone={(id) => setFlights((prev) => prev.filter((f) => f.id !== id))}
      />
      <ManilaPayFlyLayer
        flights={payFlights}
        onDone={(id) => setPayFlights((prev) => prev.filter((f) => f.id !== id))}
      />
      <ManilaSettlePanel
        match={match}
        occupiedMap={occupiedMap}
        ready={!holdShipPos && !suppressBerth}
        onFly={(flight) => setPayFlights((f) => [...f, flight])}
      />
      {sailGhosts.map((g) => {
        const seats = WARE_SEATS[g.ware as ManilaWare] || 3
        const hull = seats >= 4 ? HULL_4 : HULL_3
        return (
          <img
            key={g.id}
            className={`manila-fx-sail manila-fx-sail--${g.kind}`}
            src={hull}
            alt=""
            aria-hidden
            style={
              {
                left: g.from.x,
                top: g.from.y,
                ['--sail-to-x']: `${g.to.x - g.from.x}px`,
                ['--sail-to-y']: `${g.to.y - g.from.y}px`,
              } as CSSProperties
            }
          />
        )
      })}

      <aside className={`manila-tip-fixed${banner.urgent ? ' is-urgent' : ''}`} role="status">
        <span className="manila-tip-fixed__phase">
          {PHASE_LABEL[match.phase] || match.phase} · 航次 {match.voyage}
        </span>
        <strong className="manila-tip-fixed__msg">{banner.title}</strong>
        {banner.detail ? <span className="manila-tip-fixed__detail">{banner.detail}</span> : null}
        {showModal ? (
          <button
            type="button"
            className="manila-tip-fixed__act"
            onClick={() => setActionCollapsed((v) => !v)}
          >
            {actionCollapsed ? '展开操作' : '收起操作'}
          </button>
        ) : null}
      </aside>

      <div className="manila-tabletop manila-tabletop--modular" aria-label="马尼拉桌游盘面">
        <div className="manila-board-scroll">
          <div
            ref={stageRef}
            className={`manila-board-stage${pendingSlot ? ' has-pending-place' : ''}`}
            data-pending-slot={pendingSlot || undefined}
          >
          <BoardPxProvider stageRef={stageRef}>
          <img
            className="manila-board-stage__photo"
            src={BOARD_IMG}
            alt=""
            draggable={false}
          />
          <MarketPlate match={boardMatch} />
          <PortDock match={boardMatch} occupiedMap={occupiedMap} canPlace={canPlace} place={place} />
          <YardDock match={boardMatch} occupiedMap={occupiedMap} canPlace={canPlace} place={place} />
          <SeaCanvas
            match={boardMatch}
            occupiedMap={occupiedMap}
            canPlace={canPlace}
            place={place}
            sailing={sailing}
            startDraft={startDraft}
            placingStarts={placingStarts}
            pilotNudge={pilotNudge}
            bumpStart={placingStarts ? bumpStart : undefined}
            startMax={START_MAX}
          />

          <div className="manila-board-hits" aria-label="岸边点位">
            <ShoreModule
              slotId="pilot_small"
              label="小领航"
              match={match}
              occupiedMap={occupiedMap}
              canPlace={canPlace}
              place={place}
            />
            <ShoreModule
              slotId="pilot_large"
              label="大领航"
              match={match}
              occupiedMap={occupiedMap}
              canPlace={canPlace}
              place={place}
            />
            <ShoreModule
              slotId="insurance"
              label="保险"
              match={match}
              occupiedMap={occupiedMap}
              canPlace={canPlace}
              place={place}
            />
          </div>

          {placingStarts ? (
            <div className="manila-start-confirm">
              <span className={startValid ? 'is-ok' : 'is-bad'}>合计 {startSum} / 9</span>
              <button
                type="button"
                className="manila-btn"
                disabled={!startValid || sailing}
                onClick={confirmStarts}
              >
                {sailing ? '出航中…' : '确认出航'}
              </button>
            </div>
          ) : null}

          {showModal && !actionCollapsed ? (
            <div className="manila-action-center" role="dialog" aria-modal="true">
              <div className="manila-action-center__panel" id="manila-actions-anchor">
                <ActionPanel
                  match={match}
                  meId={meId}
                  isHM={isHM}
                  myTurn={myTurn}
                  send={sendWithPilotAnim}
                />
              </div>
            </div>
          ) : null}
          </BoardPxProvider>
          </div>
          {match.phase === 'dice' && isHM ? (
            <div className="manila-dice-roll-dock">
              <button
                type="button"
                className="manila-btn manila-dice-roll-dock__btn"
                disabled={dicePending}
                onClick={rollDice}
              >
                {dicePending ? '掷骰中…' : '掷骰前进'}
              </button>
            </div>
          ) : null}
        </div>

      {canPlace ? (
        <div
          className={`manila-place-bar${pendingSlot ? ' is-confirm' : ''}`}
          id="manila-actions-anchor"
        >
          {pendingSlot && pendingDef ? (
            <>
              <div className="manila-place-bar__main">
                <img
                  className="manila-place-bar__pawn"
                  src={meepleSrc(me?.seat ?? 0)}
                  alt=""
                />
                <div className="manila-place-bar__copy">
                  <strong>确认放置</strong>
                  <span>
                    {pendingDef.label || pendingSlot}
                    {pendingDef.kind === 'insurance'
                      ? ' · 立即获得 +10₱'
                      : ` · 花费 ${pendingDef.cost}₱`}
                  </span>
                </div>
              </div>
              <div className="manila-place-bar__acts">
                <button type="button" className="manila-btn manila-btn--ghost" onClick={cancelPlace}>
                  撤销
                </button>
                <button type="button" className="manila-btn manila-btn--place" onClick={confirmPlace}>
                  确认
                </button>
              </div>
            </>
          ) : (
            <>
              <div className="manila-place-bar__copy">
                <strong>放置{PAWN_LABEL}</strong>
                <span>货船须从前往后入座；点空位后确认，棋子从个人面板飞入</span>
              </div>
              <div className="manila-place-bar__acts">
                <button
                  type="button"
                  className="manila-btn manila-btn--ghost"
                  onClick={() => send({ type: 'pass_place' })}
                >
                  跳过本轮
                </button>
              </div>
            </>
          )}
        </div>
      ) : null}

      {!showModal && !canPlace && !(match.phase === 'dice' && isHM) ? (
        <div className="manila-board__docked-ui manila-board__docked-ui--wait">
          <ActionPanel
            match={match}
            meId={meId}
            isHM={isHM}
            myTurn={myTurn}
            send={sendWithPilotAnim}
          />
        </div>
      ) : null}

      <div className="manila-board__docked-ui">
        <LoanPanel
          match={match}
          meId={meId}
          send={send}
          forceOpen={needsLoanPrompt(match, meId, myTurn, isHM)}
        />
        <ul className="manila-events">
          {[...match.events]
            .reverse()
            .slice(0, 12)
            .map((e, i) => (
              <li key={`${i}-${e}`}>{e}</li>
            ))}
        </ul>
      </div>
      </div>
    </div>
  )
}

function needsForcedAction(
  match: ManilaMatch,
  isHM: boolean,
  myTurn: boolean,
  _placingStarts: boolean,
): boolean {
  if (match.phase === 'game_over') return true
  if (match.phase === 'auction' && myTurn) return true
  if (match.phase === 'hm_share' && isHM) return true
  if (match.phase === 'hm_load' && isHM) return true
  /* hm_place: start picker is on the board */
  /* place: sticky + board clicks */
  /* dice: right-side roll dock */
  if (match.phase === 'pirate_board' && myTurn) return true
  if (match.phase === 'pilot' && myTurn) return true
  if (match.phase === 'pirate_plunder' && myTurn) return true
  return false
}

function turnBanner(
  match: ManilaMatch,
  isHM: boolean,
  myTurn: boolean,
  canPlace: boolean,
  placingStarts: boolean,
): { title: string; detail?: string; urgent: boolean } {
  const phase = PHASE_LABEL[match.phase] || match.phase
  if (match.phase === 'game_over') {
    return { title: '本局结束', detail: '查看下方排名', urgent: true }
  }
  if (match.phase === 'auction') {
    return myTurn
      ? { title: '轮到你竞拍港主', detail: '可自定义金额，或用 +1 / +5，也可弃标', urgent: true }
      : { title: '港主竞拍进行中', detail: '等待其他玩家出价', urgent: false }
  }
  if (match.phase === 'hm_share') {
    return isHM
      ? { title: '港主：购股或跳过', detail: '按市价买一张公开股', urgent: true }
      : { title: '港主购股中', urgent: false }
  }
  if (match.phase === 'hm_load') {
    return isHM
      ? { title: '港主：选择三艘出航货物', urgent: true }
      : { title: '港主装货中', urgent: false }
  }
  if (placingStarts) {
    return {
      title: '港主：布置起点',
      detail: '在背景航道上调节每船 0–5，三数之和须为 9，然后确认出航',
      urgent: true,
    }
  }
  if (canPlace) {
    return {
      title: `选择空位放置${PAWN_LABEL}`,
      detail: '货船须从前往后入座；点空位后确认花费，可撤销',
      urgent: true,
    }
  }
  if (match.phase === 'place') {
    return { title: `等待其他玩家放置${PAWN_LABEL}`, urgent: false }
  }
  if (match.phase === 'dice') {
    return isHM
      ? { title: '港主：掷骰前进', detail: '点击右侧按钮掷骰，观看落下动画', urgent: true }
      : { title: '港主掷骰中', urgent: false }
  }
  if (match.phase === 'settle') {
    return {
      title: '航次结算',
      detail: '港口分成、船坞与保险赔付播放中，稍后进入下一航次',
      urgent: false,
    }
  }
  if (match.phase === 'pirate_board') {
    return myTurn
      ? {
          title: '船长：是否登船',
          detail: '有空位可免费登船；已满可替换一名船员；也可暂不登船',
          urgent: true,
        }
      : { title: '等待海盗船长决定', urgent: false }
  }
  if (match.phase === 'pirate_plunder') {
    return myTurn
      ? {
          title: '船长：确认截获',
          detail: '踢下全部船员后平分利润，船只能开进修船厂',
          urgent: true,
        }
      : { title: '等待海盗船长确认截获', urgent: false }
  }
  if (match.phase === 'pilot') {
    return myTurn
      ? { title: '领航：调整船位', detail: '大领航可把步数分到不同船上', urgent: true }
      : { title: '领航进行中', urgent: false }
  }
  if (myTurn) {
    return { title: `轮到你：${phase}`, urgent: true }
  }
  return { title: `等待中 · ${phase}`, urgent: false }
}

function auctionMaxCash(p: ManilaMatch['players'][number] | undefined): number {
  return p?.cash ?? 0
}

/** Auto-open mortgage when cash cannot cover the immediate action. */
function needsLoanPrompt(
  match: ManilaMatch,
  meId: string | undefined,
  myTurn: boolean,
  isHM: boolean,
): boolean {
  const me = match.players.find((p) => p.userId === meId)
  if (!me || match.phase === 'game_over') return false
  const cash = me.cash ?? 0
  const hasFreeShare = WARES.some(
    (w) => (me.publicShares?.[w] || 0) + (me.secretShares?.[w] || 0) > 0,
  )
  if (!hasFreeShare) return false

  if (match.phase === 'auction' && myTurn) {
    const minBid = (match.auctionHighBid || 0) + 1
    return cash < minBid
  }
  if (match.phase === 'hm_share' && isHM) {
    return WARES.some((w) => {
      if ((match.shareSupply?.[w] || 0) <= 0) return false
      const price = Math.max(5, match.market?.[w] ?? 0)
      return price > cash
    })
  }
  if (match.phase === 'place' && myTurn && !me.passedPlacement) {
    const cheapest = (match.slots || [])
      .filter((s) => s.cost > 0)
      .reduce((min, s) => Math.min(min, s.cost), Infinity)
    return Number.isFinite(cheapest) && cash < cheapest
  }
  return false
}

function LoanPanel({
  match,
  meId,
  send,
  forceOpen = false,
}: {
  match: ManilaMatch
  meId: string | undefined
  send: (msg: Record<string, unknown>) => void
  forceOpen?: boolean
}) {
  const me = match.players.find((p) => p.userId === meId)
  const [open, setOpen] = useState(false)
  const [pending, setPending] = useState<null | { kind: 'loan' | 'repay'; ware: ManilaWare }>(
    null,
  )

  useEffect(() => {
    setPending(null)
  }, [match.phase, me?.cash, me?.encumbered, me?.publicShares, me?.secretShares])

  useEffect(() => {
    if (forceOpen) setOpen(true)
  }, [forceOpen])

  if (!me || match.phase === 'game_over') return null

  const freeShares = WARES.flatMap((w) => {
    const n = (me.publicShares?.[w] || 0) + (me.secretShares?.[w] || 0)
    return n > 0 ? [{ ware: w, n }] : []
  })
  const encShares = WARES.flatMap((w) => {
    const n = me.encumbered?.[w] || 0
    return n > 0 ? [{ ware: w, n }] : []
  })
  const encTotal = encShares.reduce((s, x) => s + x.n, 0)

  const confirm = () => {
    if (!pending) return
    send({ type: pending.kind, ware: pending.ware })
    setPending(null)
  }

  const pendingCopy =
    pending == null
      ? null
      : pending.kind === 'loan'
        ? {
            title: `确认抵押「${WARE_LABEL[pending.ware]}」？`,
            detail: `立即获得 ${LOAN_AMOUNT}。抵押后不可撤销，仅可用 ${REPAY_AMOUNT} 正式赎回。`,
          }
        : {
            title: `确认赎回「${WARE_LABEL[pending.ware]}」？`,
            detail: `支付 ${REPAY_AMOUNT}（当前现金 ${me.cash || 0}），解除抵押。`,
          }

  return (
    <section
      className={`manila-loanboard${open ? ' is-open' : ''}${forceOpen ? ' is-forced' : ''}`}
      style={{ backgroundImage: `url(${PANEL_WOOD})` }}
    >
      <button
        type="button"
        className="manila-loanboard__toggle"
        aria-expanded={open}
        onClick={() => {
          setOpen((v) => !v)
          setPending(null)
        }}
      >
        <span>
          股份抵押 / 赎回
          {encTotal > 0 ? <em>已抵押 {encTotal}</em> : null}
          {forceOpen ? <em>现金不足</em> : null}
        </span>
        <strong>{open ? '收起' : '展开'}</strong>
      </button>

      {open ? (
        <div className="manila-loanboard__body">
          <p className="manila-loanboard__hint">
            {forceOpen
              ? `当前现金不够本次操作，可先抵押股份获得 ${LOAN_AMOUNT}。抵押不可撤销；正式赎回付 ${REPAY_AMOUNT}。`
              : `抵押得 ${LOAN_AMOUNT}；不可撤销。正式赎回付 ${REPAY_AMOUNT}。终局未赎回每张 −15。操作需确认。`}
          </p>

          {pending && pendingCopy ? (
            <div className="manila-loanboard__confirm" role="alertdialog" aria-modal="true">
              <img src={shareCardSrc(pending.ware)} alt="" />
              <div className="manila-loanboard__confirm-body">
                <strong>{pendingCopy.title}</strong>
                <p>{pendingCopy.detail}</p>
                <div className="manila-loanboard__confirm-acts">
                  <button
                    type="button"
                    className="manila-btn"
                    disabled={pending.kind === 'repay' && (me.cash || 0) < REPAY_AMOUNT}
                    onClick={confirm}
                  >
                    确认
                  </button>
                  <button
                    type="button"
                    className="manila-btn manila-btn--ghost"
                    onClick={() => setPending(null)}
                  >
                    取消
                  </button>
                </div>
              </div>
            </div>
          ) : (
            <div className="manila-loanboard__cols">
              <div>
                <h4>可抵押 · +{LOAN_AMOUNT}</h4>
                {freeShares.length === 0 ? (
                  <p className="manila-muted">暂无可抵押股份</p>
                ) : (
                  <div className="manila-loanboard__cards">
                    {freeShares.map(({ ware, n }) => (
                      <button
                        key={`loan-${ware}`}
                        type="button"
                        className="manila-share-tile"
                        onClick={() => setPending({ kind: 'loan', ware })}
                        title={`抵押 ${WARE_LABEL[ware]}`}
                      >
                        <img src={shareCardSrc(ware)} alt="" />
                        <span>{WARE_LABEL[ware]}</span>
                        <em>×{n}</em>
                      </button>
                    ))}
                  </div>
                )}
              </div>
              <div>
                <h4>已抵押 · 赎回 {REPAY_AMOUNT}</h4>
                {encShares.length === 0 ? (
                  <p className="manila-muted">无抵押股份</p>
                ) : (
                  <div className="manila-loanboard__cards">
                    {encShares.map(({ ware, n }) => {
                      const canRepay = (me.cash || 0) >= REPAY_AMOUNT
                      return (
                        <div key={`enc-${ware}`} className="manila-share-tile-wrap">
                          <div className="manila-share-tile is-enc" aria-hidden>
                            <img src={shareCardSrc(ware)} alt="" />
                            <span>{WARE_LABEL[ware]}</span>
                            <em>×{n}</em>
                          </div>
                          <button
                            type="button"
                            className="manila-btn manila-btn--ghost manila-share-tile__repay"
                            disabled={!canRepay}
                            onClick={() => setPending({ kind: 'repay', ware })}
                            title={
                              canRepay
                                ? `正式赎回（付 ${REPAY_AMOUNT}）`
                                : `现金不足（需 ${REPAY_AMOUNT}）`
                            }
                          >
                            赎回
                          </button>
                        </div>
                      )
                    })}
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      ) : null}
    </section>
  )
}

function AuctionBidPanel({
  match,
  meId,
  send,
}: {
  match: ManilaMatch
  meId: string | undefined
  send: (msg: Record<string, unknown>) => void
}) {
  const high = match.auctionHighBid
  const opening = high <= 0
  const minBid = high + 1
  const me = match.players.find((p) => p.userId === meId)
  const cash = auctionMaxCash(me)
  const [amount, setAmount] = useState(minBid)

  useEffect(() => {
    setAmount((prev) => {
      const next = Math.max(minBid, prev || minBid)
      return cash > 0 ? Math.min(next, cash) : minBid
    })
  }, [minBid, cash])

  const bid = (n: number) => {
    if (n < minBid || n > cash) return
    send({ type: 'auction_bid', amount: n })
  }

  const canCustom = amount >= minBid && amount <= cash

  return (
    <div className="manila-actions manila-actions--live manila-actions--auction">
      <h3>
        {opening ? '起叫港主' : (
          <>
            当前最高 <Cash n={high} />
          </>
        )}
      </h3>
      <p className="manila-actions__lead">
        自由出价（至少 <Cash n={minBid} />）
        <span className="manila-muted">
          {' '}
          · 可用现金 <Cash n={cash} />
        </span>
      </p>
      <div className="manila-bid-custom">
        <label className="manila-field">
          出价金额
          <input
            type="number"
            min={minBid}
            max={cash}
            value={Number.isFinite(amount) ? amount : minBid}
            onChange={(e) => setAmount(Number(e.target.value))}
          />
        </label>
        <button
          type="button"
          className="manila-btn manila-btn--place"
          disabled={!canCustom}
          onClick={() => bid(amount)}
        >
          确认出价 <Cash n={amount} />
        </button>
      </div>
      <div className="manila-actions__row manila-actions__row--bid">
        <button
          type="button"
          className="manila-btn manila-btn--ghost"
          disabled={cash < minBid}
          onClick={() => bid(minBid)}
        >
          +1（<Cash n={minBid} />）
        </button>
        <button
          type="button"
          className="manila-btn manila-btn--ghost"
          disabled={cash < high + 5}
          onClick={() => bid(high + 5)}
        >
          +5（<Cash n={high + 5} />）
        </button>
        <button
          type="button"
          className="manila-btn manila-btn--ghost"
          onClick={() => send({ type: 'auction_pass' })}
        >
          弃标
        </button>
      </div>
      <p className="manila-muted manila-actions__cap">
        可填写任意高于当前价的金额；+1 / +5 为常用加价。现金不够时会自动展开「股份抵押」。
      </p>
    </div>
  )
}

function ActionPanel({
  match,
  meId,
  isHM,
  myTurn,
  send,
}: {
  match: ManilaMatch
  meId: string | undefined
  isHM: boolean
  myTurn: boolean
  send: (msg: Record<string, unknown>) => void
}) {
  if (match.phase === 'game_over') {
    return (
      <div className="manila-actions">
        <h3>终局排名</h3>
        <ol>
          {[...match.players]
            .sort((a, b) => (a.rank || 99) - (b.rank || 99))
            .map((p) => (
              <li key={p.userId}>
                {p.username} — <Cash n={p.fortune ?? 0} />
                {p.userId === match.winnerUserId ? ' 胜' : ''}
              </li>
            ))}
        </ol>
      </div>
    )
  }

  if (match.phase === 'auction' && myTurn) {
    return <AuctionBidPanel match={match} meId={meId} send={send} />
  }

  if (match.phase === 'hm_share' && isHM) {
    return <HMShareBuyPanel match={match} send={send} />
  }

  if (match.phase === 'hm_load' && isHM) {
    return <LoadWaresPanel send={send} />
  }

  if (match.phase === 'hm_place' && isHM) {
    return (
      <div className="manila-actions manila-muted">在航道背景上调节各船起点后确认出航</div>
    )
  }

  if (match.phase === 'place' && myTurn) {
    return (
      <div className="manila-actions manila-actions--live">
        <h3>放置{PAWN_LABEL}</h3>
        <p>
          点盘面空位放置（费用见格子说明）。现金不够会自动展开抵押。
        </p>
        <button
          type="button"
          className="manila-btn manila-btn--ghost"
          onClick={() => send({ type: 'pass_place' })}
        >
          跳过本轮
        </button>
      </div>
    )
  }

  if (match.phase === 'dice' && isHM) {
    return null
  }

  if (match.phase === 'pirate_board' && myTurn) {
    return <PirateBoardPanel match={match} send={send} />
  }

  if (match.phase === 'pilot' && myTurn) {
    return <PilotPanel match={match} send={send} />
  }

  if (match.phase === 'pirate_plunder' && myTurn) {
    return (
      <div className="manila-actions manila-actions--live">
        <h3>海盗截获</h3>
        <p>
          请下船上全部船员（空手返回），海盗平分印刷利润。踢下所有人后，船只能开进修船厂。
        </p>
        <PlunderPanel match={match} send={send} />
      </div>
    )
  }

  return (
    <div className="manila-actions manila-muted">{waitHint(match, isHM, myTurn)}</div>
  )
}

function waitHint(match: ManilaMatch, isHM: boolean, myTurn: boolean): string {
  const phase = PHASE_LABEL[match.phase] || match.phase
  if (match.phase === 'hm_share' || match.phase === 'hm_load' || match.phase === 'hm_place') {
    return isHM ? `请完成：${phase}` : `港主操作中（${phase}）…`
  }
  if (match.phase === 'dice') return isHM ? '请掷骰前进' : '港主掷骰中…'
  if (match.phase === 'settle') return '航次结算动画播放中…'
  if (match.phase === 'place') {
    return myTurn ? `轮到你放置${PAWN_LABEL}` : `等待其他玩家放置${PAWN_LABEL}…`
  }
  if (myTurn) return `轮到你：${phase}`
  return `等待其他玩家（${phase}）…`
}

function HMShareBuyPanel({
  match,
  send,
}: {
  match: ManilaMatch
  send: (msg: Record<string, unknown>) => void
}) {
  const [picked, setPicked] = useState<ManilaWare | null>(null)
  const price = picked != null ? Math.max(5, match.market?.[picked] ?? 0) : 0
  const canBuy = picked != null && (match.shareSupply[picked] || 0) > 0

  return (
    <div className="manila-actions manila-actions--live">
      <h3>港主购股</h3>
      <p>点选一种股票，再确认购买（或跳过）</p>
      <div className="manila-share-pick">
        {WARES.map((w) => {
          const p = Math.max(5, match.market?.[w] ?? 0)
          const left = match.shareSupply[w] || 0
          const soldOut = left <= 0
          const on = picked === w
          return (
            <button
              key={w}
              type="button"
              className={`manila-share-pick__btn${on ? ' is-selected' : ''}${
                soldOut ? ' is-soldout' : ''
              }`}
              aria-pressed={on}
              onClick={() => setPicked(w)}
              title={
                soldOut
                  ? `${WARE_LABEL[w]} · 售罄`
                  : `${WARE_LABEL[w]} · ${p}₱ · 余 ${left}`
              }
            >
              <img className="manila-share-pick__tag" src={shareCardSrc(w)} alt="" draggable={false} />
              <strong>{WARE_LABEL[w]}</strong>
              <span>
                <Cash n={p} />
              </span>
              <em className="manila-share-pick__stock">{soldOut ? '售罄' : `余 ${left}`}</em>
            </button>
          )
        })}
      </div>
      <div className="manila-share-pick__acts">
        <button
          type="button"
          className="manila-btn"
          disabled={!canBuy}
          onClick={() => {
            if (!canBuy || !picked) return
            send({ type: 'buy_share', ware: picked })
          }}
        >
          {canBuy ? `确认购买 ${WARE_LABEL[picked!]}（${price}₱）` : '确认购买'}
        </button>
        <button
          type="button"
          className="manila-btn manila-btn--ghost"
          onClick={() => send({ type: 'buy_share', skip: true })}
        >
          跳过
        </button>
      </div>
    </div>
  )
}

function LoadWaresPanel({ send }: { send: (msg: Record<string, unknown>) => void }) {
  const [picked, setPicked] = useState<ManilaWare[]>([])
  const toggle = (w: ManilaWare) => {
    setPicked((prev) => {
      if (prev.includes(w)) return prev.filter((x) => x !== w)
      if (prev.length >= 3) return prev
      return [...prev, w]
    })
  }
  return (
    <div className="manila-actions manila-actions--live">
      <h3>港主装货</h3>
      <p>按顺序点选三种货物（再点可取消）</p>
      <div className="manila-share-pick">
        {WARES.map((w) => {
          const idx = picked.indexOf(w)
          const on = idx >= 0
          return (
            <button
              key={w}
              type="button"
              className={`manila-share-pick__btn${on ? ' is-selected' : ''}`}
              aria-pressed={on}
              onClick={() => toggle(w)}
            >
              {on ? <span className="manila-share-pick__ord">{idx + 1}</span> : null}
              <img className="manila-share-pick__tag" src={shareCardSrc(w)} alt="" draggable={false} />
              <strong>{WARE_LABEL[w]}</strong>
              <span className="manila-ware-pick__hint">
                {on ? '已装载' : `+${WARE_PROFIT[w]}`}
              </span>
            </button>
          )
        })}
      </div>
      <p className="manila-muted">
        已选 {picked.length}/3
        {picked.length ? `：${picked.map((w) => WARE_LABEL[w]).join(' → ')}` : ''}
      </p>
      <button
        type="button"
        className="manila-btn"
        disabled={picked.length !== 3}
        onClick={() => send({ type: 'load_wares', wares: picked })}
      >
        确认装货
      </button>
    </div>
  )
}

function PirateBoardPanel({
  match,
  send,
}: {
  match: ManilaMatch
  send: (msg: Record<string, unknown>) => void
}) {
  const [punt, setPunt] = useState<number | null>(null)
  const [displaceSeat, setDisplaceSeat] = useState(0)

  const occupiedMap = useMemo(() => {
    const m = new Map<string, string>()
    const occ = match.occupied as unknown
    if (Array.isArray(occ)) {
      for (const o of occ as { slotId: string; userId: string }[]) m.set(o.slotId, o.userId)
    } else if (occ && typeof occ === 'object') {
      for (const [slotId, uid] of Object.entries(occ as Record<string, string>)) {
        m.set(slotId, uid)
      }
    }
    return m
  }, [match.occupied])

  const selected = punt == null ? null : match.punts.find((p) => p.index === punt)
  const seats =
    selected == null
      ? []
      : (match.slots || [])
          .filter((s) => s.kind === 'punt' && s.puntIndex === selected.index)
          .sort((a, b) => (a.seatIndex || 0) - (b.seatIndex || 0))
  const vacant = seats.find((s) => !occupiedMap.has(s.id))
  const full = seats.length > 0 && !vacant

  return (
    <div className="manila-actions manila-actions--live">
      <h3>海盗登船（船长优先）</h3>
      <p>
        ① 有空位：免费当船员（目标进港）。② 已满：可指定替换一名船员再登船。也可暂不登船，留给后续机会。
      </p>
      <div className="manila-actions__row">
        {(match.pirateBoardPunts || []).map((pi) => {
          const p = match.punts.find((x) => x.index === pi)
          return (
            <button
              key={pi}
              type="button"
              className={`manila-btn${punt === pi ? '' : ' manila-btn--ghost'}`}
              onClick={() => {
                setPunt(pi)
                setDisplaceSeat(0)
              }}
            >
              {p ? WARE_LABEL[p.ware] : `船 ${pi + 1}`}
            </button>
          )
        })}
      </div>
      {selected && full ? (
        <label className="manila-field">
          替换船员席位
          <select
            value={displaceSeat}
            onChange={(e) => setDisplaceSeat(Number(e.target.value))}
          >
            {seats.map((s, i) => (
              <option key={s.id} value={s.seatIndex ?? i}>
                席位 {(s.seatIndex ?? i) + 1}（花费标价 {s.cost}）
              </option>
            ))}
          </select>
        </label>
      ) : null}
      <div className="manila-actions__row">
        <button
          type="button"
          className="manila-btn"
          disabled={punt == null}
          onClick={() =>
            send({
              type: 'pirate_board',
              punt,
              displaceSeat: full ? displaceSeat : -1,
            })
          }
        >
          {full ? '替换并登船' : '免费登船'}
        </button>
        <button
          type="button"
          className="manila-btn manila-btn--ghost"
          onClick={() => send({ type: 'pirate_board', skip: true })}
        >
          暂不登船
        </button>
      </div>
    </div>
  )
}

function PilotPanel({
  match,
  send,
}: {
  match: ManilaMatch
  send: (msg: Record<string, unknown>) => void
}) {
  const budget = match.pilotTurn === 'large' ? 2 : 1
  const seaPunts = match.punts.filter((p) => !p.arrived && !p.berth)
  const [deltas, setDeltas] = useState<Record<number, number>>({})

  const used = Object.values(deltas).reduce((s, d) => s + Math.abs(d || 0), 0)
  const moves = Object.entries(deltas)
    .map(([punt, delta]) => ({ punt: Number(punt), delta }))
    .filter((m) => m.delta !== 0)

  const setDelta = (punt: number, delta: number) => {
    setDeltas((prev) => {
      const next = { ...prev, [punt]: delta }
      const total = Object.values(next).reduce((s, d) => s + Math.abs(d || 0), 0)
      if (total > budget) return prev
      return next
    })
  }

  return (
    <div className="manila-actions manila-actions--live">
      <h3>{match.pilotTurn === 'large' ? '大领航' : '小领航'}</h3>
      <p>
        可前后移动未进港的船；合计最多 {budget} 格
        {match.pilotTurn === 'large' ? '，可分到不同船上' : ''}。已用 {used}/{budget}。
      </p>
      <div className="manila-pilot-grid">
        {seaPunts.map((p) => (
          <div key={p.index} className="manila-pilot-row">
            <strong>
              {WARE_LABEL[p.ware]} · 位 {p.position}
            </strong>
            <div className="manila-actions__row">
              {[-2, -1, 0, 1, 2]
                .filter((d) => Math.abs(d) <= budget)
                .map((d) => (
                  <button
                    key={d}
                    type="button"
                    className={`manila-btn manila-btn--ghost${
                      (deltas[p.index] || 0) === d ? ' is-on' : ''
                    }`}
                    disabled={
                      d !== 0 &&
                      used - Math.abs(deltas[p.index] || 0) + Math.abs(d) > budget
                    }
                    onClick={() => setDelta(p.index, d)}
                  >
                    {d > 0 ? `+${d}` : d === 0 ? '0' : `${d}`}
                  </button>
                ))}
            </div>
          </div>
        ))}
      </div>
      <div className="manila-actions__row">
        <button
          type="button"
          className="manila-btn"
          disabled={moves.length === 0 || used > budget}
          onClick={() => send({ type: 'pilot', moves })}
        >
          确认领航
        </button>
        <button
          type="button"
          className="manila-btn manila-btn--ghost"
          onClick={() => send({ type: 'pilot', skip: true })}
        >
          跳过
        </button>
      </div>
    </div>
  )
}

function PlunderPanel({
  match,
  send,
}: {
  match: ManilaMatch
  send: (msg: Record<string, unknown>) => void
}) {
  return (
    <>
      <div className="manila-plunder-list">
        {(match.plunderPunts || []).map((pi) => {
          const p = match.punts.find((x) => x.index === pi)
          return (
            <div key={pi} className="manila-plunder-card">
              <strong>
                {p ? WARE_LABEL[p.ware] : `船 ${pi + 1}`} · 利润 +
                {p ? WARE_PROFIT[p.ware] || 0 : '?'}
              </strong>
              <p className="manila-muted manila-actions__cap">去向：修船厂（固定）</p>
            </div>
          )
        })}
      </div>
      <button
        type="button"
        className="manila-btn"
        onClick={() => send({ type: 'pirate_plunder', toPort: {} })}
      >
        确认截获并进修船厂
      </button>
    </>
  )
}
