import { Link } from 'react-router-dom'
import { ASSET_V } from './assets'
import { BOARD_IMG } from './boardLayout'
import '@/games/game-shell.css'
import './manila.css'

const COSTS_IMG = `/games/manila/board/board-costs-only.jpg?v=${ASSET_V}`
const EFFECT_IMG = `/games/manila/board/board-effect.jpg?v=${ASSET_V}`

/**
 * Cost-on-pad preview (first locked generation step).
 * Anchors + method: public/games/manila/board/anchors.json + GENERATION.md
 */
export function ManilaBoardPreviewPage() {
  return (
    <div className="game-shell manila-preview-page">
      <header className="manila-preview-page__bar">
        <div>
          <h1>马尼拉 · 花费点位（垫上）</h1>
          <p>
            可编辑配置表 <code>boardConfig.json</code>：每个点位含透视四边形 +
            显示内容（花费/收益/角色）；股票面板同文件 <code>market.panel_quad_pct</code>。
          </p>
        </div>
        <nav className="manila-preview-page__links">
          <a href={COSTS_IMG} target="_blank" rel="noreferrer">
            仅花费大图
          </a>
          <a href={EFFECT_IMG} target="_blank" rel="noreferrer">
            含货船
          </a>
          <a href={BOARD_IMG} target="_blank" rel="noreferrer">
            仅背景
          </a>
          <Link to="/game/manila">返回大厅</Link>
        </nav>
      </header>

      <div className="manila-preview-page__stage-wrap">
        <img
          className="manila-preview-page__effect"
          src={COSTS_IMG}
          alt="花费点位贴在背景垫子上"
        />
      </div>
    </div>
  )
}
