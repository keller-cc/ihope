import { useEffect, useState } from 'react'

/** Match CSS breakpoint used by `.im-shell--mobile` (max-width: 860px). */
export const MOBILE_BREAKPOINT_PX = 860

export function useIsMobile(breakpoint = MOBILE_BREAKPOINT_PX): boolean {
  const [mobile, setMobile] = useState(() =>
    typeof window !== 'undefined' ? window.matchMedia(`(max-width: ${breakpoint}px)`).matches : false,
  )

  useEffect(() => {
    const mq = window.matchMedia(`(max-width: ${breakpoint}px)`)
    const onChange = () => setMobile(mq.matches)
    onChange()
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [breakpoint])

  return mobile
}
