/** Independent game catalog — not part of IM/chat. */
export type GameInfo = {
  id: string
  title: string
  subtitle: string
  description: string
  path: string
  status: 'playable' | 'coming'
  /** CSS modifier for cover art */
  cover: string
}

export const GAMES: GameInfo[] = [
  {
    id: 'dinodasher',
    title: '恐龙冲刺',
    subtitle: 'Chrome 经典彩蛋',
    description:
      '控制像素风小恐龙在沙漠中奔跑，跳过仙人掌、闪避翼龙，挑战更高分。',
    path: '/game/dinodasher',
    status: 'playable',
    cover: 'dino',
  },
]
