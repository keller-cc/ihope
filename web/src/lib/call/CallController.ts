import { api } from '../../api'
import type { CallKind, CallPeer, CallRoom, RemoteMedia } from './types'
import { ringtone } from './ringtone'
import { userSocket } from './userSocket'

type Listener = () => void

type PeerConn = {
  pc: RTCPeerConnection
  pendingIce: RTCIceCandidateInit[]
  makingOffer: boolean
}

export type CallUIState = {
  incoming: CallRoom | null
  active: CallRoom | null
  localStream: MediaStream | null
  remotes: RemoteMedia[]
  muted: boolean
  cameraOff: boolean
  /** 扬声器静音（不影响麦克风） */
  speakerMuted: boolean
  /** 麦克风增益 0–1 */
  micVolume: number
  /** 扬声器音量 0–1 */
  speakerVolume: number
  error: string | null
  connecting: boolean
}

const emptyState = (): CallUIState => ({
  incoming: null,
  active: null,
  localStream: null,
  remotes: [],
  muted: false,
  cameraOff: false,
  speakerMuted: false,
  micVolume: 1,
  speakerVolume: 1,
  error: null,
  connecting: false,
})

export class CallController {
  userId = ''
  private iceServers: RTCIceServer[] = []
  private peers = new Map<string, PeerConn>()
  private remoteStreams = new Map<string, MediaStream>()
  private listeners = new Set<Listener>()
  private unsub: (() => void) | null = null
  private audioCtx: AudioContext | null = null
  private micGain: GainNode | null = null
  private rawLocalStream: MediaStream | null = null
  state: CallUIState = emptyState()

  setUserId(id: string) {
    this.userId = id
  }

  subscribe(fn: Listener) {
    this.listeners.add(fn)
    return () => {
      this.listeners.delete(fn)
    }
  }

  private emit() {
    for (const fn of this.listeners) fn()
  }

  private setState( partial: Partial<CallUIState>) {
    this.state = { ...this.state, ...partial }
    this.emit()
  }

  start() {
    userSocket.connect()
    if (!this.unsub) {
      this.unsub = userSocket.on((data) => void this.onSignal(data))
    }
  }

  stop() {
    this.unsub?.()
    this.unsub = null
    void this.cleanupMedia()
    userSocket.disconnect()
    this.state = emptyState()
    this.emit()
  }

  async startCall(
    conversationId: string,
    kind: CallKind,
    opts?: { muted?: boolean; cameraOff?: boolean; stream?: MediaStream },
  ) {
    this.setState({ connecting: true, error: null })
    try {
      await this.ensureIce()
      const room = await api.startCall(conversationId, kind)
      await this.enterLocal(room, opts)
      this.setState({ active: room, incoming: null, connecting: false })
      await this.offerToJoinedPeers(room)
    } catch (e) {
      opts?.stream?.getTracks().forEach((t) => t.stop())
      this.setState({
        connecting: false,
        error: e instanceof Error ? e.message : '发起通话失败',
      })
      throw e
    }
  }

  async acceptIncoming(opts?: { muted?: boolean; cameraOff?: boolean; stream?: MediaStream }) {
    const room = this.state.incoming
    if (!room) return
    this.setState({ connecting: true, error: null })
    try {
      await this.ensureIce()
      const next = await api.acceptCall(room.id)
      await this.enterLocal(next, opts)
      this.setState({ active: next, incoming: null, connecting: false })
      await this.offerToJoinedPeers(next)
    } catch (e) {
      opts?.stream?.getTracks().forEach((t) => t.stop())
      this.setState({
        connecting: false,
        error: e instanceof Error ? e.message : '接听失败',
      })
      throw e
    }
  }

  async rejectIncoming() {
    const room = this.state.incoming
    if (!room) return
    ringtone.stop()
    try {
      await api.rejectCall(room.id)
    } finally {
      this.setState({ incoming: null })
    }
  }

  async hangup() {
    const room = this.state.active
    if (room) {
      try {
        await api.hangupCall(room.id)
      } catch {
        /* ignore */
      }
    }
    await this.cleanupMedia()
    this.setState({
      active: null,
      remotes: [],
      localStream: null,
      muted: false,
      cameraOff: false,
      speakerMuted: false,
      micVolume: 1,
      speakerVolume: 1,
    })
  }

  async toggleMute() {
    const stream = this.state.localStream
    if (!stream) return
    const next = !this.state.muted
    for (const t of stream.getAudioTracks()) t.enabled = !next
    if (this.micGain) {
      this.micGain.gain.value = next ? 0 : this.state.micVolume
    }
    this.setState({ muted: next })
    const callId = this.state.active?.id
    if (callId) {
      userSocket.send({ type: 'call.media', callId, audio: !next })
    }
  }

  toggleSpeaker() {
    this.setState({ speakerMuted: !this.state.speakerMuted })
  }

  setMicVolume(v: number) {
    const micVolume = Math.max(0, Math.min(1, v))
    if (this.micGain && !this.state.muted) {
      this.micGain.gain.value = micVolume
    }
    this.setState({ micVolume })
  }

  setSpeakerVolume(v: number) {
    this.setState({ speakerVolume: Math.max(0, Math.min(1, v)) })
  }

  async toggleCamera() {
    const stream = this.state.localStream
    const room = this.state.active
    if (!stream || !room || room.kind !== 'video') return
    const next = !this.state.cameraOff
    for (const t of stream.getVideoTracks()) t.enabled = !next
    this.setState({ cameraOff: next })
    userSocket.send({ type: 'call.media', callId: room.id, video: !next })
  }

  private async ensureIce() {
    if (this.iceServers.length) return
    const { iceServers } = await api.getCallIce()
    this.iceServers = iceServers.map((s) => ({
      urls: s.urls,
      username: s.username,
      credential: s.credential,
    }))
  }

  private async enterLocal(
    room: CallRoom,
    opts?: { muted?: boolean; cameraOff?: boolean; stream?: MediaStream },
  ) {
    const muted = !!opts?.muted
    const cameraOff = room.kind === 'video' ? !!opts?.cameraOff : false
    let stream = opts?.stream || null
    if (!stream) {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: room.kind === 'video',
      })
    } else {
      // 预览流可能缺轨，补齐
      const needVideo = room.kind === 'video' && stream.getVideoTracks().length === 0
      const needAudio = stream.getAudioTracks().length === 0
      if (needVideo || needAudio) {
        const extra = await navigator.mediaDevices.getUserMedia({
          audio: needAudio,
          video: needVideo,
        })
        for (const t of extra.getTracks()) stream.addTrack(t)
      }
    }
    for (const t of stream.getAudioTracks()) t.enabled = !muted
    for (const t of stream.getVideoTracks()) t.enabled = !cameraOff
    const micVolume = this.state.micVolume
    const outbound = await this.withMicGain(stream, muted ? 0 : micVolume)
    this.setState({ localStream: outbound, muted, cameraOff })
  }

  /** 用 GainNode 调节上行麦克风音量，视频轨原样保留 */
  private async withMicGain(stream: MediaStream, gainValue: number): Promise<MediaStream> {
    const audioTracks = stream.getAudioTracks()
    if (!audioTracks.length) return stream
    this.rawLocalStream = stream
    await this.closeAudioGraph()
    const ctx = new AudioContext()
    this.audioCtx = ctx
    if (ctx.state === 'suspended') {
      try {
        await ctx.resume()
      } catch {
        /* ignore */
      }
    }
    const source = ctx.createMediaStreamSource(new MediaStream(audioTracks))
    const gain = ctx.createGain()
    gain.gain.value = Math.max(0, Math.min(1, gainValue))
    this.micGain = gain
    const dest = ctx.createMediaStreamDestination()
    source.connect(gain)
    gain.connect(dest)
    return new MediaStream([...dest.stream.getAudioTracks(), ...stream.getVideoTracks()])
  }

  private async closeAudioGraph() {
    this.micGain = null
    if (this.audioCtx) {
      try {
        await this.audioCtx.close()
      } catch {
        /* ignore */
      }
      this.audioCtx = null
    }
  }

  private async offerToJoinedPeers(room: CallRoom) {
    for (const p of room.participants) {
      if (p.userId === this.userId || p.state !== 'joined') continue
      await this.ensurePeer(p.userId, true, p)
    }
  }

  private async ensurePeer(peerId: string, asOfferer: boolean, meta?: CallPeer) {
    if (peerId === this.userId || this.peers.has(peerId)) return
    const local = this.state.localStream
    if (!local) return

    const pc = new RTCPeerConnection({ iceServers: this.iceServers })
    const entry: PeerConn = { pc, pendingIce: [], makingOffer: false }
    this.peers.set(peerId, entry)

    for (const track of local.getTracks()) {
      pc.addTrack(track, local)
    }

    pc.onicecandidate = (ev) => {
      if (!ev.candidate || !this.state.active) return
      userSocket.send({
        type: 'call.ice',
        callId: this.state.active.id,
        toUserId: peerId,
        candidate: ev.candidate.toJSON(),
      })
    }

    pc.ontrack = (ev) => {
      const stream = ev.streams[0] || new MediaStream([ev.track])
      this.remoteStreams.set(peerId, stream)
      this.refreshRemotes(meta)
    }

    pc.onconnectionstatechange = () => {
      if (pc.connectionState === 'failed' || pc.connectionState === 'closed') {
        this.removePeer(peerId)
      }
    }

    if (asOfferer) {
      entry.makingOffer = true
      try {
        const offer = await pc.createOffer()
        await pc.setLocalDescription(offer)
        if (this.state.active) {
          userSocket.send({
            type: 'call.offer',
            callId: this.state.active.id,
            toUserId: peerId,
            sdp: pc.localDescription,
          })
        }
      } finally {
        entry.makingOffer = false
      }
    }
  }

  private refreshRemotes(meta?: CallPeer) {
    const room = this.state.active
    const remotes: RemoteMedia[] = []
    for (const [userId, stream] of this.remoteStreams) {
      const p = room?.participants.find((x) => x.userId === userId) || meta
      remotes.push({
        userId,
        stream,
        username: p?.username,
        avatarUrl: p?.avatarUrl,
      })
    }
    this.setState({ remotes })
  }

  private removePeer(peerId: string) {
    const entry = this.peers.get(peerId)
    if (entry) {
      entry.pc.close()
      this.peers.delete(peerId)
    }
    this.remoteStreams.delete(peerId)
    this.refreshRemotes()
  }

  private async cleanupMedia() {
    ringtone.stop()
    for (const [, entry] of this.peers) {
      entry.pc.close()
    }
    this.peers.clear()
    this.remoteStreams.clear()
    this.state.localStream?.getTracks().forEach((t) => t.stop())
    this.rawLocalStream?.getTracks().forEach((t) => t.stop())
    this.rawLocalStream = null
    await this.closeAudioGraph()
  }

  private async flushIce(peerId: string) {
    const entry = this.peers.get(peerId)
    if (!entry || !entry.pc.remoteDescription) return
    const pending = entry.pendingIce.splice(0)
    for (const c of pending) {
      try {
        await entry.pc.addIceCandidate(c)
      } catch {
        /* ignore */
      }
    }
  }

  private async onSignal(data: Record<string, unknown>) {
    const type = String(data.type || '')
    switch (type) {
      case 'call.invite': {
        const call = data.call as CallRoom
        if (!call || call.hostId === this.userId) return
        if (this.state.active) return
        this.setState({ incoming: call })
        break
      }
      case 'call.started': {
        const call = data.call as CallRoom
        if (call) this.setState({ active: call })
        break
      }
      case 'call.peer_joined': {
        const call = data.call as CallRoom | undefined
        const peer = data.peer as CallPeer | undefined
        if (call) this.setState({ active: call })
        // 新加入者会主动 offer；已在通话中的人等待对方 offer
        if (peer && peer.userId !== this.userId && this.state.active) {
          // no-op wait
        }
        break
      }
      case 'call.peer_left': {
        const peer = data.peer as CallPeer | undefined
        if (peer) this.removePeer(peer.userId)
        break
      }
      case 'call.peer_rejected': {
        // 私聊拒绝时随后会有 call.ended
        break
      }
      case 'call.ended': {
        await this.cleanupMedia()
        this.setState({
          active: null,
          incoming: null,
          remotes: [],
          localStream: null,
          muted: false,
          cameraOff: false,
          speakerMuted: false,
          micVolume: 1,
          speakerVolume: 1,
        })
        break
      }
      case 'call.offer': {
        const from = String(data.fromUserId || '')
        const sdp = data.sdp as RTCSessionDescriptionInit
        const callId = String(data.callId || '')
        if (!from || !sdp || !this.state.active || this.state.active.id !== callId) return
        await this.ensurePeer(from, false)
        const entry = this.peers.get(from)
        if (!entry) return
        await entry.pc.setRemoteDescription(sdp)
        await this.flushIce(from)
        const answer = await entry.pc.createAnswer()
        await entry.pc.setLocalDescription(answer)
        userSocket.send({
          type: 'call.answer',
          callId,
          toUserId: from,
          sdp: entry.pc.localDescription,
        })
        break
      }
      case 'call.answer': {
        const from = String(data.fromUserId || '')
        const sdp = data.sdp as RTCSessionDescriptionInit
        const entry = this.peers.get(from)
        if (!entry || !sdp) return
        await entry.pc.setRemoteDescription(sdp)
        await this.flushIce(from)
        break
      }
      case 'call.ice': {
        const from = String(data.fromUserId || '')
        const candidate = data.candidate as RTCIceCandidateInit
        const entry = this.peers.get(from)
        if (!entry || !candidate) return
        if (!entry.pc.remoteDescription) {
          entry.pendingIce.push(candidate)
          return
        }
        try {
          await entry.pc.addIceCandidate(candidate)
        } catch {
          /* ignore */
        }
        break
      }
      case 'call.media': {
        const peer = data.peer as CallPeer | undefined
        if (!peer || !this.state.active) return
        const participants = this.state.active.participants.map((p) =>
          p.userId === peer.userId ? { ...p, ...peer } : p,
        )
        this.setState({ active: { ...this.state.active, participants } })
        break
      }
      default:
        break
    }
  }
}

export const callController = new CallController()
