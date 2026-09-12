import { useEffect, useRef, useState } from 'react'
import Dice from 'react-dice-roll'
import type { DiceRef } from 'react-dice-roll'
import { dieSrc } from './assets'

type Props = {
  /** Server-authoritative faces for the three sailing ships (1–6). */
  values: number[] | null
  onDone?: () => void
}

const FACES = [1, 2, 3, 4, 5, 6].map((n) => dieSrc(n))

/**
 * Plays a 3d6 tumble via react-dice-roll once values arrive from the server.
 */
export function ManilaDiceOverlay({ values, onDone }: Props) {
  const refs = [useRef<DiceRef>(null), useRef<DiceRef>(null), useRef<DiceRef>(null)]
  const [open, setOpen] = useState(false)
  const doneCount = useRef(0)
  const key = values?.join('-') ?? ''

  useEffect(() => {
    if (!values || values.length < 3) return
    setOpen(true)
    doneCount.current = 0
    const t = window.setTimeout(() => {
      values.slice(0, 3).forEach((v, i) => {
        refs[i].current?.rollDice(v)
      })
    }, 80)
    return () => window.clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])

  if (!open || !values || values.length < 3) return null

  const onOneDone = () => {
    doneCount.current += 1
    if (doneCount.current >= 3) {
      window.setTimeout(() => {
        setOpen(false)
        onDone?.()
      }, 480)
    }
  }

  return (
    <div className="manila-dice-overlay" role="status" aria-live="polite">
      <div className="manila-dice-overlay__panel">
        <p>掷骰</p>
        <div className="manila-dice-overlay__row">
          {values.slice(0, 3).map((v, i) => (
            <Dice
              key={`${key}-${i}`}
              ref={refs[i]}
              size={72}
              rollingTime={1100}
              faces={FACES}
              cheatValue={v as 1 | 2 | 3 | 4 | 5 | 6}
              defaultValue={1}
              triggers={[]}
              onRoll={onOneDone}
            />
          ))}
        </div>
      </div>
    </div>
  )
}
