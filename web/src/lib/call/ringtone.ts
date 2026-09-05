/** 柔和旋律铃声（Web Audio，无需外部音文件） */
export class RingtonePlayer {
  private ctx: AudioContext | null = null
  private timer: ReturnType<typeof setTimeout> | null = null
  private nodes: AudioNode[] = []
  private running = false
  private mode: 'outgoing' | 'incoming' = 'outgoing'

  start(mode: 'outgoing' | 'incoming' = 'outgoing') {
    if (this.running && this.mode === mode) return
    this.stop()
    this.mode = mode
    this.running = true
    void this.ensureCtx().then(() => {
      if (!this.running) return
      this.schedulePhrase()
    })
  }

  stop() {
    this.running = false
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    for (const n of this.nodes) {
      try {
        if ('stop' in n && typeof (n as OscillatorNode).stop === 'function') {
          ;(n as OscillatorNode).stop()
        }
        n.disconnect()
      } catch {
        /* ignore */
      }
    }
    this.nodes = []
  }

  private async ensureCtx() {
    if (!this.ctx) {
      this.ctx = new AudioContext()
    }
    if (this.ctx.state === 'suspended') {
      await this.ctx.resume()
    }
    return this.ctx
  }

  private schedulePhrase() {
    if (!this.running || !this.ctx) return
    const ctx = this.ctx
    const now = ctx.currentTime

    // 呼出：轻柔上行琶音；来电：稍亮、稍密的回响动机
    const phrase =
      this.mode === 'incoming'
        ? [
            { f: 523.25, t: 0 }, // C5
            { f: 659.25, t: 0.18 }, // E5
            { f: 783.99, t: 0.36 }, // G5
            { f: 1046.5, t: 0.54 }, // C6
            { f: 783.99, t: 0.78 }, // G5
            { f: 659.25, t: 0.96 }, // E5
          ]
        : [
            { f: 392.0, t: 0 }, // G4
            { f: 493.88, t: 0.22 }, // B4
            { f: 587.33, t: 0.44 }, // D5
            { f: 783.99, t: 0.66 }, // G5
            { f: 587.33, t: 0.96 }, // D5
            { f: 493.88, t: 1.18 }, // B4
          ]

    const noteDur = this.mode === 'incoming' ? 0.28 : 0.34
    const phraseLen = this.mode === 'incoming' ? 1.35 : 1.7
    const gapMs = this.mode === 'incoming' ? 900 : 1600

    for (const n of phrase) {
      this.playSoftNote(ctx, now + n.t, n.f, noteDur)
    }
    // 低八度垫音，让音色更饱满
    this.playSoftNote(ctx, now, phrase[0].f / 2, phraseLen * 0.85, 0.035)

    this.timer = setTimeout(() => {
      this.timer = null
      if (this.running) this.schedulePhrase()
    }, phraseLen * 1000 + gapMs)
  }

  private playSoftNote(
    ctx: AudioContext,
    start: number,
    freq: number,
    dur: number,
    peak = 0.09,
  ) {
    const master = ctx.createGain()
    master.gain.setValueAtTime(0.0001, start)
    master.gain.exponentialRampToValueAtTime(peak, start + 0.025)
    master.gain.exponentialRampToValueAtTime(peak * 0.55, start + dur * 0.45)
    master.gain.exponentialRampToValueAtTime(0.0001, start + dur)
    master.connect(ctx.destination)
    this.nodes.push(master)

    const filter = ctx.createBiquadFilter()
    filter.type = 'lowpass'
    filter.frequency.setValueAtTime(freq * 4.2, start)
    filter.Q.value = 0.7
    filter.connect(master)
    this.nodes.push(filter)

    // 主音：三角波更接近铃声/木琴
    const fund = ctx.createOscillator()
    fund.type = 'triangle'
    fund.frequency.value = freq
    const fundGain = ctx.createGain()
    fundGain.gain.value = 0.85
    fund.connect(fundGain)
    fundGain.connect(filter)
    fund.start(start)
    fund.stop(start + dur + 0.02)
    this.nodes.push(fund, fundGain)

    // 轻柔泛音
    const harm = ctx.createOscillator()
    harm.type = 'sine'
    harm.frequency.value = freq * 2
    const harmGain = ctx.createGain()
    harmGain.gain.value = 0.18
    harm.connect(harmGain)
    harmGain.connect(filter)
    harm.start(start)
    harm.stop(start + dur + 0.02)
    this.nodes.push(harm, harmGain)
  }
}

export const ringtone = new RingtonePlayer()
