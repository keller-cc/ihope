import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getToken } from '@/api'
import { GAMES, type GameInfo } from '@/games/catalog'
import '@/games/game-shell.css'

const LOGIN_HREF = `/?next=${encodeURIComponent('/game')}`

/** Sparse desert vignette — no overlapping sprites. */
function DinoCoverArt() {
  return (
    <div className="dino-cover" aria-hidden>
      <span className="dino-cover__cloud dino-cover__cloud--a" />
      <span className="dino-cover__cloud dino-cover__cloud--b" />
      <span className="dino-cover__ground" />
      <span className="dino-cover__cactus" />
      <span className="dino-cover__trex" />
    </div>
  )
}

function ManilaCoverArt() {
  return (
    <div className="manila-cover" aria-hidden>
      <svg className="manila-cover__art" viewBox="0 0 320 160" preserveAspectRatio="xMidYMid slice">
        <defs>
          <linearGradient id="manilaCoverSea" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#0e7490" stopOpacity="0" />
            <stop offset="35%" stopColor="#0f766e" stopOpacity="0.55" />
            <stop offset="100%" stopColor="#134e4a" />
          </linearGradient>
          <radialGradient id="manilaCoverSun" cx="78%" cy="28%" r="35%">
            <stop offset="0%" stopColor="#fbbf24" stopOpacity="0.55" />
            <stop offset="100%" stopColor="#fbbf24" stopOpacity="0" />
          </radialGradient>
        </defs>
        <rect width="320" height="160" fill="url(#manilaCoverSun)" />
        <rect y="78" width="320" height="82" fill="url(#manilaCoverSea)" />
        {/* pier / dock silhouette */}
        <g fill="#78350f" opacity="0.92">
          <rect x="248" y="96" width="64" height="10" rx="1" />
          <rect x="256" y="106" width="6" height="28" />
          <rect x="278" y="106" width="6" height="34" />
          <rect x="298" y="106" width="6" height="24" />
        </g>
        {/* nearer boat */}
        <g className="manila-cover__boat manila-cover__boat--a" fill="#fef3c7">
          <path d="M48 108c8-2 28-4 52-2l8 6H42l6-4z" />
          <path d="M72 90v16h6V94l18-2v-4l-24 2z" fill="#fde68a" />
        </g>
        {/* farther boat */}
        <g className="manila-cover__boat manila-cover__boat--b" fill="#fde68a" opacity="0.88">
          <path d="M150 98c6-1 20-3 38-1l5 4h-46l3-3z" />
          <path d="M168 86v12h4V88l12-1v-3l-16 2z" fill="#fef3c7" />
        </g>
        {/* soft horizon line */}
        <path
          d="M0 90h320"
          stroke="rgba(255,255,255,0.12)"
          strokeWidth="1"
          fill="none"
        />
      </svg>
    </div>
  )
}

function GameCard({ game }: { game: GameInfo }) {
  const playable = game.status === 'playable'
  const body = (
    <>
      <div className={`game-card__cover game-card__cover--${game.cover}`}>
        {game.cover === 'dino' ? (
          <DinoCoverArt />
        ) : game.cover === 'manila' ? (
          <ManilaCoverArt />
        ) : (
          <div className="game-card__cover-art" />
        )}
        {!playable && <span className="game-card__badge">即将上线</span>}
      </div>
      <div className="game-card__body">
        <p className="game-card__subtitle">{game.subtitle}</p>
        <h2>{game.title}</h2>
        <p className="game-card__desc">{game.description}</p>
      </div>
      <div className="game-card__footer">
        <span className={`game-card__cta${playable ? '' : ' game-card__cta--disabled'}`}>
          {playable ? '开始游玩' : '敬请期待'}
        </span>
      </div>
    </>
  )

  if (playable) {
    return (
      <Link className="game-card" to={game.path}>
        {body}
      </Link>
    )
  }

  return <div className="game-card game-card--disabled">{body}</div>
}

export function GameHubPage() {
  const [loggedIn, setLoggedIn] = useState(() => !!getToken())

  useEffect(() => {
    setLoggedIn(!!getToken())
  }, [])

  return (
    <div className="game-shell">
      <header className="game-shell__head">
        <h1>游戏</h1>
        <div className="game-shell__head-actions">
          {!loggedIn && (
            <Link className="game-shell__link game-shell__link--accent" to={LOGIN_HREF}>
              登录
            </Link>
          )}
          <Link className="game-shell__link" to="/">
            返回
          </Link>
        </div>
      </header>

      <ul className="game-grid">
        {GAMES.map((g) => (
          <li key={g.id}>
            <GameCard game={g} />
          </li>
        ))}
      </ul>
    </div>
  )
}
