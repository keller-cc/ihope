import { initialOf } from '@/lib/chatFormat'

type Size = 'sm' | 'md' | 'lg' | 'xl' | 'rail'
export type AvatarPresence = 'online' | 'away' | 'offline'

type Props = {
  name: string
  src?: string | null
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

export function Avatar({
  name,
  src,
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

  const content = src ? <img src={src} alt="" /> : initialOf(name)

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
