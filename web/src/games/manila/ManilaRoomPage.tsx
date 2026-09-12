import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { MessagePlugin } from 'tdesign-react'
import { api, apiErrorMessage, getToken, isUnauthorizedError, type ManilaPlayer, type ManilaRoom } from '@/api'
import { ManilaBoard } from './ManilaBoard'
import { COIN, meepleSrc, PAWN_LABEL, SHARE_BACK, shareSrc } from './assets'
import { WARE_LABEL } from './rulesContent'
import { useManilaSocket } from './useManilaSocket'
import './manila.css'

const LOGIN_HREF = (code: string) => `/?next=${encodeURIComponent(`/game/manila/r/${code}`)}`

const WARES = ['nutmeg', 'silk', 'ginseng', 'jade'] as const

type HudShare = {
  key: string
  ware: string
  n: number
  secret: boolean
  enc: boolean
  /** 本人：该货种里有多少张是暗股（合并展示用） */
  secretN?: number
}

function buildHudShares(player: ManilaPlayer, isSelf: boolean): HudShare[] {
  const out: HudShare[] = []
  for (const w of WARES) {
    const pub = player.publicShares?.[w] || 0
    const sec = isSelf ? player.secretShares?.[w] || 0 : 0
    const free = pub + sec
    if (free > 0) {
      out.push({
        key: `free-${w}`,
        ware: w,
        n: free,
        secret: sec > 0 && pub === 0,
        enc: false,
        secretN: sec,
      })
    }
  }
  if (!isSelf && (player.secretCount || 0) > 0) {
    out.push({
      key: 'secret-back',
      ware: 'back',
      n: player.secretCount || 0,
      secret: true,
      enc: false,
    })
  }
  if (isSelf) {
    for (const w of WARES) {
      const n = player.encumbered?.[w] || 0
      if (n > 0) {
        out.push({ key: `enc-${w}`, ware: w, n, secret: false, enc: true })
      }
    }
  }
  return out
}

function PlayerHudIcons({
  player,
  isSelf,
  isHM,
  isTurn,
}: {
  player: ManilaPlayer
  isSelf: boolean
  isHM: boolean
  isTurn?: boolean
}) {
  const left = Math.max(0, player.accomplicesLeft ?? 0)
  const shares = buildHudShares(player, isSelf)

  return (
    <div className="manila-rail-card__inner">
      <div className="manila-rail-card__top">
        <img
          src={meepleSrc(player.seat)}
          alt=""
          className="manila-rail-card__avatar"
        />
        <div className="manila-rail-card__who">
          <strong className="manila-rail-card__name">{player.username}</strong>
          <div className="manila-rail-card__tags">
            {isSelf ? <span className="manila-tag manila-tag--me">我</span> : null}
            {isHM ? <span className="manila-tag manila-tag--hm">港主</span> : null}
            {isTurn ? <span className="manila-tag manila-tag--turn">行动中</span> : null}
          </div>
        </div>
      </div>
      <div className="manila-rail-card__stats">
        <span
          className="manila-rail-stat"
          data-manila-rail-cash={player.userId}
          title={`现金 ${player.cash}`}
        >
          <img src={COIN} alt="" className="manila-rail-stat__ico" />
          <em>{player.cash}</em>
        </span>
        <span className="manila-rail-stat manila-rail-stat--pawn" title={`剩余${PAWN_LABEL} ${left}`}>
          {left <= 0 ? (
            <em className="manila-rail-pawn__zero">0</em>
          ) : (
            <span className="manila-rail-pawn-stack" aria-label={`剩余${PAWN_LABEL} ${left}`}>
              {Array.from({ length: Math.min(left, 6) }, (_, i) => (
                <img
                  key={i}
                  src={meepleSrc(player.seat)}
                  alt=""
                  className="manila-rail-pawn-stack__ico"
                  style={{ zIndex: i + 1, marginLeft: i === 0 ? 0 : -10 }}
                />
              ))}
              {left > 6 ? <em className="manila-rail-pawn-stack__more">+{left - 6}</em> : null}
            </span>
          )}
        </span>
      </div>
      <div className="manila-rail-card__shares" aria-label="股份">
        {shares.length === 0 ? (
          <span className="manila-rail-empty">暂无股份</span>
        ) : (
          shares.map((s) => {
            const src =
              s.secret && (s.ware === 'back' || !isSelf) ? SHARE_BACK : shareSrc(s.ware)
            const label = WARE_LABEL[s.ware] || s.ware
            const title = s.enc
              ? `已抵押 ${label} ×${s.n}`
              : s.ware === 'back'
                ? `暗股 ×${s.n}`
                : s.secretN && s.secretN > 0 && s.secretN < s.n
                  ? `${label} ×${s.n}（含暗股 ${s.secretN}）`
                  : s.secret || (s.secretN ?? 0) > 0
                    ? `暗股 ${label} ×${s.n}`
                    : `${label} ×${s.n}`
            return (
              <span
                key={s.key}
                className={`manila-rail-share is-tag${s.secret || (s.secretN ?? 0) > 0 ? ' is-secret' : ''}${
                  s.enc ? ' is-enc' : ''
                }`}
                title={title}
              >
                <img src={src} alt="" />
                {s.n > 1 ? <em className="manila-rail-share__qty">×{s.n}</em> : null}
              </span>
            )
          })
        )}
      </div>
    </div>
  )
}

export function ManilaRoomPage() {
  const { code = '' } = useParams()
  const navigate = useNavigate()
  const [room, setRoom] = useState<ManilaRoom | null>(null)
  const [meId, setMeId] = useState<string | undefined>()

  useEffect(() => {
    if (!getToken()) {
      navigate(LOGIN_HREF(code), { replace: true })
      return
    }
    void api
      .me()
      .then((u) => setMeId(u.id))
      .catch(() => navigate(LOGIN_HREF(code), { replace: true }))
  }, [code, navigate])

  useEffect(() => {
    if (!code || !getToken()) return
    void api
      .manilaJoinRoom(code)
      .then(setRoom)
      .catch(async (e) => {
        if (isUnauthorizedError(e)) {
          navigate(LOGIN_HREF(code), { replace: true })
          return
        }
        try {
          setRoom(await api.manilaGetRoom(code))
        } catch (e2) {
          if (isUnauthorizedError(e2)) {
            navigate(LOGIN_HREF(code), { replace: true })
            return
          }
          MessagePlugin.error(apiErrorMessage(e, '无法进入房间'))
          navigate('/game/manila')
        }
      })
  }, [code, navigate])

  const onState = useCallback((r: ManilaRoom) => setRoom(r), [])
  const { connected, lastError, send } = useManilaSocket(room?.id, onState)

  useEffect(() => {
    if (lastError) MessagePlugin.warning(lastError)
  }, [lastError])

  const me = useMemo(
    () => room?.members.find((m) => m.userId === meId),
    [room, meId],
  )
  const isHost = room?.hostUserId === meId
  const playing = room?.status === 'playing' || room?.status === 'closed'

  return (
    <div className={`manila-shell${playing ? ' manila-shell--play' : ''}`}>
      {!playing && (
        <>
          <div className="manila-sky" aria-hidden />
          <div className="manila-waves" aria-hidden />
        </>
      )}
      <header className="manila-head">
        <div>
          <p className="manila-eyebrow">房间 {room?.code || code}</p>
          <h1>{playing ? '对局桌面' : '候场大厅'}</h1>
        </div>
        <div className="manila-head-actions">
          <span className={`manila-conn${connected ? ' is-on' : ''}`}>
            {connected ? '已同步' : '连接中…'}
          </span>
          <Link className="manila-link" to={`/game/manila/rules?room=${encodeURIComponent(room?.code || code)}`}>
            规则
          </Link>
          <Link className="manila-link" to="/game/manila">
            大厅
          </Link>
        </div>
      </header>

      {!playing && (
        <section className="manila-waiting">
          <div className="manila-waiting-meta">
            <span>
              {(room?.members?.length || 0)}/{room?.maxPlayers || '—'} 人
            </span>
            <span>{room?.isPrivate ? '私密房' : '公开房'}</span>
          </div>
          <div className="manila-seat-stage" aria-label="座位">
            {Array.from({ length: room?.maxPlayers || 4 }, (_, seat) => {
              const m = (room?.members || []).find((x) => (x.seat ?? -1) === seat)
              const isFirst = (room?.firstSeat ?? 0) === seat
              const isMe = m?.userId === meId
              const canSit = !m && !!meId
              return (
                <div
                  key={seat}
                  className={`manila-pad-seat${m ? ' is-filled' : ' is-empty'}${
                    isFirst ? ' is-first' : ''
                  }${isMe ? ' is-me' : ''}${!m?.connected && m ? ' is-away' : ''}`}
                >
                  <span className="manila-pad-seat__idx">{seat + 1}</span>
                  {isFirst ? <em className="manila-pad-seat__tag">起始</em> : null}
                  {m ? (
                    <>
                      <img
                        className="manila-pad-seat__avatar"
                        src={meepleSrc(m.seat)}
                        alt=""
                        draggable={false}
                      />
                      <strong className="manila-pad-seat__name">{m.username}</strong>
                      <span className="manila-pad-seat__meta">
                        {m.isHost ? '房主' : m.ready ? '已准备' : '未准备'}
                        {!m.connected ? ' · 离线' : ''}
                      </span>
                      <div className="manila-pad-seat__acts">
                        {!isMe && me ? (
                          <button
                            type="button"
                            className="manila-text-btn manila-pad-seat__swap"
                            onClick={() => send({ type: 'swap_seat', seat })}
                          >
                            交换座位
                          </button>
                        ) : null}
                        {isHost && !isFirst ? (
                          <button
                            type="button"
                            className="manila-text-btn"
                            onClick={() => send({ type: 'set_first_seat', seat })}
                          >
                            设为起始
                          </button>
                        ) : null}
                        {isHost && m.userId !== meId ? (
                          <button
                            type="button"
                            className="manila-text-btn"
                            onClick={() => send({ type: 'kick', userId: m.userId })}
                          >
                            踢出
                          </button>
                        ) : null}
                      </div>
                    </>
                  ) : (
                    <button
                      type="button"
                      className="manila-pad-seat__sit"
                      disabled={!canSit}
                      onClick={() => send({ type: 'claim_seat', seat })}
                    >
                      <span className="manila-pad-seat__sit-ico" aria-hidden>
                        ＋
                      </span>
                      入座
                    </button>
                  )}
                </div>
              )
            })}
          </div>
          <p className="manila-muted manila-waiting-seat-hint">
            空位点「入座」，他人座位点「交换座位」；房主可指定起始与踢出。换座不更换房主。
          </p>
          <div className="manila-waiting-actions">
            {isHost && (
              <div className="manila-waiting-settings">
                <label className="manila-field">
                  人数上限
                  <select
                    value={room?.maxPlayers || 4}
                    onChange={(e) =>
                      send({ type: 'settings', maxPlayers: Number(e.target.value) })
                    }
                  >
                    {[3, 4, 5].map((n) => (
                      <option
                        key={n}
                        value={n}
                        disabled={n < (room?.members?.length || 0)}
                      >
                        {n} 人
                      </option>
                    ))}
                  </select>
                </label>
                <label className="manila-check">
                  <input
                    type="checkbox"
                    checked={!!room?.isPrivate}
                    onChange={(e) =>
                      send({ type: 'settings', private: e.target.checked })
                    }
                  />
                  私密房（不出现在公开列表）
                </label>
              </div>
            )}
            {!isHost && (
              <button
                type="button"
                className="manila-btn"
                onClick={() => send({ type: 'ready', ready: !me?.ready })}
              >
                {me?.ready ? '取消准备' : '准备'}
              </button>
            )}
            {isHost && (
              <button
                type="button"
                className="manila-btn"
                onClick={() => send({ type: 'start' })}
              >
                开始游戏（需满 3 人且均已准备）
              </button>
            )}
            <p className="manila-muted">分享房间码：{room?.code || code}</p>
          </div>
        </section>
      )}

      {playing && room?.match && (
        <>
          <aside className="manila-rail" aria-label="玩家信息">
            {room.match.players.map((p) => (
              <div
                key={p.userId}
                data-manila-rail={p.userId}
                className={`manila-rail-card${p.userId === meId ? ' is-me' : ''}${
                  p.userId === room.match?.harborMasterId ? ' is-hm' : ''
                }${p.userId === room.match?.turnUserId ? ' is-turn' : ''}`}
              >
                <PlayerHudIcons
                  player={p}
                  isSelf={p.userId === meId}
                  isHM={p.userId === room.match?.harborMasterId}
                  isTurn={p.userId === room.match?.turnUserId}
                />
              </div>
            ))}
          </aside>
          <ManilaBoard match={room.match} meId={meId} send={send} />
        </>
      )}
    </div>
  )
}
