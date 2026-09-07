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

function GameCard({ game }: { game: GameInfo }) {
  const playable = game.status === 'playable'
  const body = (
    <>
      <div className={`game-card__cover game-card__cover--${game.cover}`}>
        {game.cover === 'dino' ? <DinoCoverArt /> : <div className="game-card__cover-art" />}
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
