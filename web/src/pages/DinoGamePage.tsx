import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { SettingIcon } from 'tdesign-icons-react'
import { Drawer, Switch } from 'tdesign-react'
import {
  api,
  apiErrorMessage,
  getToken,
  type DinoScoreRow,
} from '@/api'
import audioResourcesHtml from '@/games/dino/audio-resources.html?raw'
import '@/games/dino/index.css'
import '@/games/dino/offline.js'
import '@/games/game-shell.css'

declare global {
  interface Window {
    Runner?: {
      new (outerContainerId: string, opt_config?: object): unknown
      instance_?: {
        stop?: () => void
        stopListening?: () => void
        stopSounds?: () => void
        audioContext?: { close?: () => Promise<void> | void } | null
      } | null
      spriteSrc1x?: string
      spriteSrc2x?: string
      muted?: boolean
      onGameStart?: (() => void) | null
      onGameOver?: ((score: number) => void) | null
    }
  }
}

const SPRITE_1X = '/games/dino/1x-offline-sprite.png'
const SPRITE_2X = '/games/dino/2x-offline-sprite.png'
const MUTE_KEY = 'ihope_dino_muted'
const BOARD_KEY = 'ihope_dino_show_board'
const LOGIN_HREF = `/?next=${encodeURIComponent('/game/dinodasher')}`

type Phase = 'idle' | 'playing' | 'over'

/** Chrome T-Rex runner embedded directly (no iframe). */
export function DinoGamePage() {
  const bootRef = useRef(false)
  const lastSubmitRef = useRef(0)
  const audioHostRef = useRef<HTMLDivElement | null>(null)
  const [phase, setPhase] = useState<Phase>('idle')
  const [board, setBoard] = useState<DinoScoreRow[]>([])
  const [myBest, setMyBest] = useState(0)
  const [lastScore, setLastScore] = useState<number | null>(null)
  const [boardHint, setBoardHint] = useState('')
  const [muted, setMuted] = useState(() => localStorage.getItem(MUTE_KEY) === '1')
  const [showLeaderboard, setShowLeaderboard] = useState(
    () => localStorage.getItem(BOARD_KEY) !== '0',
  )
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [loggedIn, setLoggedIn] = useState(() => !!getToken())
  const onMainUi = phase !== 'playing'
  const showBoard = showLeaderboard && onMainUi

  const refreshBoard = useCallback(async () => {
    try {
      const res = await api.dinoLeaderboard()
      setBoard(res.scores || [])
    } catch {
      /* ignore */
    }
    if (getToken()) {
      try {
        const me = await api.dinoMyBest()
        setMyBest(me.best || 0)
      } catch {
        /* ignore */
      }
    }
  }, [])

  useEffect(() => {
    setLoggedIn(!!getToken())
    void refreshBoard()
  }, [refreshBoard])

  useEffect(() => {
    if (window.Runner) window.Runner.muted = muted
    localStorage.setItem(MUTE_KEY, muted ? '1' : '0')
    if (muted) window.Runner?.instance_?.stopSounds?.()
  }, [muted])

  useEffect(() => {
    localStorage.setItem(BOARD_KEY, showLeaderboard ? '1' : '0')
  }, [showLeaderboard])

  useEffect(() => {
    if (bootRef.current) return
    bootRef.current = true

    const host = document.createElement('div')
    host.style.display = 'none'
    host.innerHTML = audioResourcesHtml
    document.body.appendChild(host)
    audioHostRef.current = host

    const Runner = window.Runner
    if (!Runner) return

    Runner.muted = muted
    Runner.spriteSrc1x = SPRITE_1X
    Runner.spriteSrc2x = SPRITE_2X
    Runner.instance_ = null
    Runner.onGameStart = () => {
      setPhase('playing')
      setBoardHint('')
      setSettingsOpen(false)
    }
    Runner.onGameOver = (score: number) => {
      setPhase('over')
      setLastScore(score)
      if (!getToken()) {
        setBoardHint('')
        return
      }
      if (score <= 0 || score === lastSubmitRef.current) return
      lastSubmitRef.current = score
      void (async () => {
        try {
          const res = await api.dinoSubmitScore(score)
          setMyBest(res.best)
          setBoardHint(res.improved ? '新纪录！' : '')
          await refreshBoard()
        } catch (e) {
          setBoardHint(apiErrorMessage(e, '成绩上传失败'))
        }
      })()
    }
    // eslint-disable-next-line no-new
    new Runner('.interstitial-wrapper')

    return () => {
      Runner.onGameStart = null
      Runner.onGameOver = null
      const inst = Runner.instance_
      inst?.stopSounds?.()
      inst?.stop?.()
      inst?.stopListening?.()
      try {
        void inst?.audioContext?.close?.()
      } catch {
        /* ignore */
      }
      Runner.instance_ = null
      bootRef.current = false
      document.body.classList.remove('arcade-mode', 'inverted')
      const gameHost = document.querySelector('.interstitial-wrapper')
      if (gameHost) {
        gameHost.querySelectorAll('.runner-container, .controller, canvas').forEach((el) => el.remove())
      }
      audioHostRef.current?.remove()
      audioHostRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refreshBoard])

  return (
    <div className="game-shell game-shell--dino">
      <header className="game-shell__head game-shell__head--dino">
        <div className="dino-head-actions">
          <button
            type="button"
            className="dino-menu-btn"
            aria-label="设置"
            aria-expanded={settingsOpen}
            onClick={() => setSettingsOpen(true)}
          >
            <SettingIcon size="20px" />
          </button>
          <Link className="game-shell__link" to="/game">
            返回
          </Link>
        </div>
      </header>

      <Drawer
        header="设置"
        visible={settingsOpen}
        placement="right"
        size="280px"
        onClose={() => setSettingsOpen(false)}
        footer={null}
        showOverlay
        className="dino-settings-drawer"
      >
        <div className="dino-settings-drawer__body">
          <label className="dino-settings-drawer__row">
            <span>静音</span>
            <Switch value={muted} onChange={(v) => setMuted(!!v)} />
          </label>
          <label className="dino-settings-drawer__row">
            <span>展示排行榜</span>
            <Switch value={showLeaderboard} onChange={(v) => setShowLeaderboard(!!v)} />
          </label>
          {!loggedIn && (
            <Link
              className="dino-settings-drawer__login"
              to={LOGIN_HREF}
              onClick={() => setSettingsOpen(false)}
            >
              登录账号以上传成绩
            </Link>
          )}
        </div>
      </Drawer>

      <div className="dino-layout">
        <div className="dino-play">
          {onMainUi && !loggedIn && (
            <div className="dino-player-bar">
              <div className="dino-player dino-player--guest">
                <div className="dino-player__meta">
                  <span className="dino-player__hint">登录后可上传成绩并参与排行榜</span>
                </div>
                <Link className="dino-player__login" to={LOGIN_HREF}>
                  登录
                </Link>
              </div>
            </div>
          )}

          <div className="dino-frame">
            <div className="dino-stage offline" id="t">
              <div id="main-frame-error" className="interstitial-wrapper">
                <div id="main-content">
                  <div className="icon icon-offline" aria-hidden />
                </div>
                <div id="offline-resources">
                  <img id="offline-resources-1x" src={SPRITE_1X} alt="" />
                  <img id="offline-resources-2x" src={SPRITE_2X} alt="" />
                </div>
              </div>
            </div>
          </div>

          {onMainUi && (
            <div className="dino-controls-hint">
              <span className="dino-controls-hint__text">使用方向键</span>
              <div className="dino-keys" aria-hidden>
                <span className="dino-key">↑</span>
                <span className="dino-key">↓</span>
              </div>
              <span className="dino-controls-hint__or">或</span>
              <span className="dino-key dino-key--space">空格</span>
            </div>
          )}

          {phase === 'over' && lastScore != null && (
            <p className="dino-score-line">
              <span>本局 {lastScore}</span>
              {myBest > 0 && <span> · 我的最佳 {myBest}</span>}
              {boardHint && <span className="dino-score-line__hint"> · {boardHint}</span>}
              {!loggedIn && (
                <>
                  {' · '}
                  <Link className="dino-score-line__login" to={LOGIN_HREF}>
                    去登录
                  </Link>
                </>
              )}
            </p>
          )}
        </div>

        {showBoard && (
          <section className="dino-board" aria-label="排行榜">
            <h2>排行榜</h2>
            {!loggedIn && (
              <p className="dino-board__login">
                <Link to={LOGIN_HREF}>登录</Link>
                后可上传成绩并参与排名
              </p>
            )}
            {board.length === 0 ? (
              <p className="dino-board__empty">暂无成绩</p>
            ) : (
              <ol className="dino-board__list">
                {board.map((row) => (
                  <li key={`${row.userId}-${row.score}`}>
                    <span className="dino-board__rank">{row.rank}</span>
                    <span className="dino-board__name">{row.username}</span>
                    <span className="dino-board__score">{row.score}</span>
                  </li>
                ))}
              </ol>
            )}
          </section>
        )}
      </div>
    </div>
  )
}
