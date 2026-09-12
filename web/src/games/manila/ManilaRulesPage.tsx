import { Link, useSearchParams } from 'react-router-dom'
import { PAWN_LABEL } from './assets'
import { MANILA_RULE_SECTIONS, MANILA_SOURCES } from './rulesContent'
import './manila.css'

export function ManilaRulesPage() {
  const [params] = useSearchParams()
  const room = (params.get('room') || '').trim().toLowerCase()
  const backTo = room ? `/game/manila/r/${room}` : '/game/manila'
  const backLabel = room ? '返回对局' : '返回大厅'

  return (
    <div className="manila-shell">
      <div className="manila-sky" aria-hidden />
      <div className="manila-waves" aria-hidden />
      <header className="manila-head">
        <div>
          <p className="manila-eyebrow">规则书</p>
          <h1>马尼拉怎么玩</h1>
        </div>
        <div className="manila-head-actions">
          <Link className="manila-link manila-link--accent" to={backTo}>
            {backLabel}
          </Link>
          {!room && (
            <Link className="manila-link" to="/game">
              返回游戏列表
            </Link>
          )}
        </div>
      </header>

      <article className="manila-rules">
        <p className="manila-rules-lead">
          以下为便于局内查阅的中文要点整理，非正式出版规则原文。细节以对局服务端校验为准。
        </p>
        <p className="manila-rules-lead">
          「{PAWN_LABEL}」是你的小人棋子（素材来自 Kenney Board Game Pack / CC0）：每航次可放到船上、港口、修船厂、海盗船、领航或保险等位置。3
          人局每人 4 枚，4–5 人局每人 3 枚；界面上的「剩余{PAWN_LABEL}」表示本航次还没放出去的枚数。放置时点击盘面上印有花费/收益的空位；向下滑动可看到操作区。
        </p>
        {MANILA_RULE_SECTIONS.map((sec) => (
          <details key={sec.id} className="manila-rule-block" open={sec.id === 'goal'}>
            <summary>{sec.title}</summary>
            {sec.body.map((p) => (
              <p key={p.slice(0, 24)}>{p}</p>
            ))}
          </details>
        ))}
        <footer className="manila-sources">
          <h2>参考来源</h2>
          <ul>
            {MANILA_SOURCES.map((s) => (
              <li key={s.href}>
                <a href={s.href} target="_blank" rel="noreferrer">
                  {s.title}
                </a>
              </li>
            ))}
          </ul>
        </footer>
      </article>
    </div>
  )
}
