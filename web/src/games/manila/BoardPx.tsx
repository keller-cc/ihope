import {
  createContext,
  useContext,
  useLayoutEffect,
  useState,
  type ReactNode,
  type RefObject,
} from 'react'

export type BoardPx = { w: number; h: number }

const BoardPxContext = createContext<BoardPx>({ w: 0, h: 0 })

/** Board plate size in CSS pixels — keeps pad matrix3d correct under zoom/resize. */
export function BoardPxProvider({
  stageRef,
  children,
}: {
  stageRef: RefObject<HTMLElement | null>
  children: ReactNode
}) {
  const [px, setPx] = useState<BoardPx>({ w: 0, h: 0 })

  useLayoutEffect(() => {
    const el = stageRef.current
    if (!el) return

    const sync = () => {
      const r = el.getBoundingClientRect()
      const w = r.width
      const h = r.height
      setPx((prev) => (prev.w === w && prev.h === h ? prev : { w, h }))
    }

    sync()
    const ro = new ResizeObserver(sync)
    ro.observe(el)
    window.addEventListener('resize', sync)
    const vv = window.visualViewport
    vv?.addEventListener('resize', sync)
    vv?.addEventListener('scroll', sync)
    return () => {
      ro.disconnect()
      window.removeEventListener('resize', sync)
      vv?.removeEventListener('resize', sync)
      vv?.removeEventListener('scroll', sync)
    }
  }, [stageRef])

  return <BoardPxContext.Provider value={px}>{children}</BoardPxContext.Provider>
}

export function useBoardPx(): BoardPx {
  return useContext(BoardPxContext)
}
