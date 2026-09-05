import { useEffect } from 'react'

/**
 * 移动端软键盘：把布局高度对齐 visualViewport，避免输入框被盖住。
 * 写入 --im-vv-height / --im-vv-offset 供 .im-shell--mobile 使用。
 */
export function useVisualViewportLock(enabled: boolean) {
  useEffect(() => {
    if (!enabled) {
      document.documentElement.style.removeProperty('--im-vv-height')
      document.documentElement.style.removeProperty('--im-vv-offset')
      return
    }
    const root = document.documentElement
    const vv = window.visualViewport
    const sync = () => {
      const h = vv?.height ?? window.innerHeight
      const top = vv?.offsetTop ?? 0
      root.style.setProperty('--im-vv-height', `${Math.round(h)}px`)
      root.style.setProperty('--im-vv-offset', `${Math.round(top)}px`)
    }
    sync()
    vv?.addEventListener('resize', sync)
    vv?.addEventListener('scroll', sync)
    window.addEventListener('resize', sync)
    return () => {
      vv?.removeEventListener('resize', sync)
      vv?.removeEventListener('scroll', sync)
      window.removeEventListener('resize', sync)
      root.style.removeProperty('--im-vv-height')
      root.style.removeProperty('--im-vv-offset')
    }
  }, [enabled])
}
