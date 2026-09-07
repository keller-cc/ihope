import { initialOf } from '@/lib/chatFormat'

type Size = 'sm' | 'md' | 'lg' | 'xl' | 'rail'

type Props = {
  name: string
  src?: string | null
  size?: Size
  group?: boolean
  className?: string
  onClick?: () => void
  title?: string
}

const sizeClass: Record<Size, string> = {
  sm: 'im-avatar--sm',
  md: '',
  lg: 'im-avatar--lg',
  xl: 'im-avatar--xl',
  rail: 'im-avatar--rail',
}

export function Avatar({ name, src, size = 'md', group, className = '', onClick, title }: Props) {
  const classes = [
    'im-avatar',
    sizeClass[size],
    group ? 'im-avatar--group' : '',
    className,
  ]
    .filter(Boolean)
    .join(' ')

  const content = src ? <img src={src} alt="" /> : initialOf(name)

  if (onClick) {
    return (
      <button type="button" className={classes} title={title || name} onClick={onClick}>
        {content}
      </button>
    )
  }
  return (
    <span className={classes} title={title || name}>
      {content}
    </span>
  )
}
