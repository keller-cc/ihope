import { useEffect } from 'react'

/**
 * 移动端软键盘：只计算底部遮挡高度，不缩放整页。
 * 写入 --im-kb-inset，并在抬起时给 <html> 加 .im-kb-open。
 */
export function useVisualViewportLock(enabled: boolean) {
  useEffect(() => {
    const root = document.documentElement
    if (!enabled) {
      root.style.removeProperty('--im-kb-inset')
      root.classList.remove('im-kb-open')
      return
    }
    const vv = window.visualViewport
    const sync = () => {
      const inset = vv
        ? Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop))
        : 0
      root.style.setProperty('--im-kb-inset', `${inset}px`)
      root.classList.toggle('im-kb-open', inset > 80)
    }
    sync()
    vv?.addEventListener('resize', sync)
    vv?.addEventListener('scroll', sync)
    window.addEventListener('resize', sync)
    return () => {
      vv?.removeEventListener('resize', sync)
      vv?.removeEventListener('scroll', sync)
      window.removeEventListener('resize', sync)
      root.style.removeProperty('--im-kb-inset')
      root.classList.remove('im-kb-open')
    }
  }, [enabled])
}
