import { useEffect, useRef, useState } from 'react'
import { dieSrc } from './assets'

type Props = {
  /** Server-authoritative faces (1–6), one per ship that rolled. */
  values: number[] | null
  /** Harbor master clicked roll; animate drop while waiting for server. */
  pending?: boolean
  onDone?: () => void
}

type Phase = 'idle' | 'falling' | 'settle'

function randFaces(n: number): number[] {
  return Array.from({ length: n }, () => 1 + Math.floor(Math.random() * 6))
}

/**
 * Dice fall from above with spin, then settle on server faces.
 */
export function ManilaDiceOverlay({ values, pending = false, onDone }: Props) {
  const [phase, setPhase] = useState<Phase>('idle')
  const [faces, setFaces] = useState<number[]>([1, 1, 1])
  const [session, setSession] = useState(0)
  const count = Math.max(1, values?.length || 3)
  const key = values?.join('-') ?? ''
  const doneRef = useRef(false)
  const spinRef = useRef(0)
  const lastKey = useRef('')
  const phaseRef = useRef<Phase>('idle')

  useEffect(() => {
    phaseRef.current = phase
  }, [phase])

  const beginFall = (n: number) => {
    doneRef.current = false
    setSession((s) => s + 1)
    setFaces(randFaces(n))
    setPhase('falling')
  }

  useEffect(() => {
    if (!pending) return
    if (phaseRef.current === 'falling' || phaseRef.current === 'settle') return
    beginFall(count)
  }, [pending, count])

  useEffect(() => {
    if (!values || values.length < 1) return
    if (key === lastKey.current) return
    lastKey.current = key
    if (phaseRef.current === 'idle') beginFall(values.length)
  }, [key, values])

  useEffect(() => {
    if (phase !== 'falling') {
      window.clearInterval(spinRef.current)
      return
    }
    const n = faces.length || count
    spinRef.current = window.setInterval(() => setFaces(randFaces(n)), 70)
    return () => window.clearInterval(spinRef.current)
  }, [phase, count, faces.length])

  useEffect(() => {
    if (!values || values.length < 1 || phase !== 'falling') return
    const delay = pending ? 780 : 560
    const settleAt = window.setTimeout(() => {
      window.clearInterval(spinRef.current)
      setFaces(values.map((v) => Math.min(6, Math.max(1, v || 1))))
      setPhase('settle')
    }, delay)
    return () => window.clearTimeout(settleAt)
  }, [values, phase, pending])

  useEffect(() => {
    if (phase !== 'settle' || doneRef.current) return
    const t = window.setTimeout(() => {
      doneRef.current = true
      setPhase('idle')
      onDone?.()
    }, 1250)
    return () => window.clearTimeout(t)
  }, [phase, onDone])

  if (phase === 'idle') return null

  return (
    <div className="manila-dice-overlay" role="status" aria-live="polite">
      <div className={`manila-dice-overlay__stage is-${phase}`}>
        <p className="manila-dice-overlay__label">{phase === 'settle' ? '前进！' : '掷骰…'}</p>
        <div className="manila-dice-overlay__row">
          {faces.map((face, i) => (
            <div
              key={`${session}-${i}`}
              className={`manila-die-drop is-${phase}`}
              style={{ animationDelay: `${i * 95}ms` }}
            >
              <img
                className="manila-die-drop__face"
                src={dieSrc(face)}
                alt={phase === 'settle' ? String(face) : ''}
                draggable={false}
              />
            </div>
          ))}
        </div>
        {phase === 'settle' && values && values.length >= 1 ? (
          <p className="manila-dice-overlay__sum">{values.join(' · ')}</p>
        ) : null}
      </div>
    </div>
  )
}
