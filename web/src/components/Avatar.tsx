import { initialOf } from '@/lib/chatFormat'
import type { MemberFace } from '@/api'

type Size = 'sm' | 'md' | 'lg' | 'xl' | 'rail'
export type AvatarPresence = 'online' | 'away' | 'offline'

type Props = {
  name: string
  src?: string | null
  /** WeChat-style default group mosaic when src is empty. */
  faces?: MemberFace[] | null
  size?: Size
  group?: boolean
  className?: string
  onClick?: () => void
  title?: string
  /** QQ-style corner status (green / orange / gray). */
  presence?: AvatarPresence
}

const sizeClass: Record<Size, string> = {
  sm: 'im-avatar--sm',
  md: '',
  lg: 'im-avatar--lg',
  xl: 'im-avatar--xl',
  rail: 'im-avatar--rail',
}

function mosaicCount(n: number): number {
  if (n <= 1) return 1
  if (n === 2) return 2
  if (n === 3) return 3
  if (n === 4) return 4
  return Math.min(9, n)
}

function Mosaic({ faces }: { faces: MemberFace[] }) {
  const tiles = faces.slice(0, 9)
  const count = mosaicCount(tiles.length)
  const shown = tiles.slice(0, count)
  // 5–9 人用 3×3，空位补灰块，避免格子被撑乱
  const cells: Array<MemberFace | null> =
    count >= 5 ? [...shown, ...Array(9 - shown.length).fill(null)] : shown
  return (
    <span className={`im-avatar__mosaic im-avatar__mosaic--${count}`} aria-hidden>
      {cells.map((f, i) =>
        f ? (
          <span key={`${f.name}-${i}`} className="im-avatar__tile">
            {f.avatarUrl ? (
              <img src={f.avatarUrl} alt="" />
            ) : (
              <span className="im-avatar__tile-initial">{initialOf(f.name)}</span>
            )}
          </span>
        ) : (
          <span key={`empty-${i}`} className="im-avatar__tile im-avatar__tile--empty" />
        ),
      )}
    </span>
  )
}

export function Avatar({
  name,
  src,
  faces,
  size = 'md',
  group,
  className = '',
  onClick,
  title,
  presence,
}: Props) {
  const classes = [
    'im-avatar',
    sizeClass[size],
    group ? 'im-avatar--group' : '',
    className,
  ]
    .filter(Boolean)
    .join(' ')

  const useMosaic = group && !src && !!faces && faces.length > 0
  const content = src ? (
    <img src={src} alt="" />
  ) : useMosaic ? (
    <Mosaic faces={faces!} />
  ) : (
    initialOf(name)
  )

  const avatar = onClick ? (
    <button type="button" className={classes} title={title || name} onClick={onClick}>
      {content}
    </button>
  ) : (
    <span className={classes} title={title || name}>
      {content}
    </span>
  )

  if (!presence) return avatar

  const statusLabel =
    presence === 'online' ? '在线' : presence === 'away' ? '连接中' : '离线'

  return (
    <span
      className={`im-avatar-wrap${onClick ? ' im-avatar-wrap--btn' : ''}`}
      title={statusLabel}
    >
      {avatar}
      <i className={`im-avatar__dot im-avatar__dot--${presence}`} aria-hidden />
    </span>
  )
}
