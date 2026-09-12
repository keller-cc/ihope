declare module 'react-dice-roll' {
  import type { ForwardRefExoticComponent, RefAttributes } from 'react'

  export type DiceProps = {
    rollingTime?: number
    onRoll?: (value: number) => void
    triggers?: string[]
    defaultValue?: number
    size?: number
    sound?: string
    disabled?: boolean
    faces?: string[]
    faceBg?: string
    placement?: 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right'
    cheatValue?: 1 | 2 | 3 | 4 | 5 | 6
  }

  export type DiceRef = {
    rollDice: (cheat?: number) => void
  }

  const Dice: ForwardRefExoticComponent<DiceProps & RefAttributes<DiceRef>>
  export default Dice
}
