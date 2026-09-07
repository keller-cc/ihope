import { api, getToken } from '@/api'
import type { CallKind, CallPeer, CallRoom, RemoteMedia } from './types'
import { ringtone } from './ringtone'
import { userSocket } from './userSocket'

type Listener = () => void
type CallEndedListener = (conversationId: string, status: string) => void

type PeerConn = {
  pc: RTCPeerConnection
  pendingIce: RTCIceCandidateInit[]
  makingOffer: boolean
}

export type CallUIState = {
  incoming: CallRoom | null
  active: CallRoom | null
  /** 当前关注会话内进行中的通话（顶栏；本人未必已加入） */
  conversationCall: CallRoom | null
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
  /** 收起全屏通话页，仅保留顶栏 */
  minimized: boolean
}

const emptyState = (): CallUIState => ({
  incoming: null,
  active: null,
  conversationCall: null,
  localStream: null,
  remotes: [],
  muted: false,
  cameraOff: false,
  speakerMuted: false,
  micVolume: 1,
  speakerVolume: 1,
  error: null,
  connecting: false,
  minimized: false,
})

export class CallController {
  userId = ''
  private iceServers: RTCIceServer[] = []
  private peers = new Map<string, PeerConn>()
  private remoteStreams = new Map<string, MediaStream>()
  private listeners = new Set<Listener>()
  private endedListeners = new Set<CallEndedListener>()
  private unsub: (() => void) | null = null
  private audioCtx: AudioContext | null = null
  private micGain: GainNode | null = null
  private rawLocalStream: MediaStream | null = null
  private watchedConversationId: string | null = null
  private unloadBound: (() => void) | null = null
  private currentVideoDeviceId: string | null = null
  private facingMode: 'user' | 'environment' = 'user'
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

  /** 通话结束（超时/挂断/拒绝等）后刷新会话列表与聊天记录 */
  onCallEnded(fn: CallEndedListener) {
    this.endedListeners.add(fn)
    return () => {
      this.endedListeners.delete(fn)
    }
  }

  private emit() {
    for (const fn of this.listeners) fn()
  }

  private emitCallEnded(conversationId: string, status: string) {
    if (!conversationId) return
    for (const fn of this.endedListeners) fn(conversationId, status)
  }

  private setState(partial: Partial<CallUIState>) {
    this.state = { ...this.state, ...partial }
    this.emit()
  }

  private rememberConversationCall(call: CallRoom | null) {
    if (!call) {
      if (this.state.conversationCall) this.setState({ conversationCall: null })
      return
    }
    if (this.watchedConversationId && call.conversationId === this.watchedConversationId) {
      this.setState({ conversationCall: call })
    }
  }

  /** 打开某会话时拉取进行中通话，供顶栏展示 */
  async watchConversation(conversationId: string | null) {
    this.watchedConversationId = conversationId
    if (!conversationId) {
      this.setState({ conversationCall: null })
      return
    }
    try {
      const res = await api.getActiveCall(conversationId)
      if (this.watchedConversationId === conversationId) {
        this.setState({ conversationCall: res.call ?? null })
      }
    } catch {
      if (this.watchedConversationId === conversationId) {
        this.setState({ conversationCall: null })
      }
    }
  }

  private hangupKeepalive() {
    const id = this.state.active?.id
    if (!id) return
    try {
      const token = getToken()
      if (!token) return
      void fetch(`/api/calls/${id}/hangup`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        keepalive: true,
      })
    } catch {
      /* ignore */
    }
  }

  start() {
    userSocket.connect()
    if (!this.unsub) {
      this.unsub = userSocket.on((data) => void this.onSignal(data))
    }
    if (!this.unloadBound) {
      this.unloadBound = () => this.hangupKeepalive()
      window.addEventListener('pagehide', this.unloadBound)
      window.addEventListener('beforeunload', this.unloadBound)
    }
    void this.syncIncomingInvites()
  }

  /** 刚登录 / 重连：拉取未接来电，展示接听/拒绝 */
  async syncIncomingInvites() {
    if (this.state.active || this.state.connecting) return
    try {
      const res = await api.listIncomingCalls()
      const call = (res.calls || [])[0]
      if (!call || this.state.active || this.state.connecting) return
      this.rememberConversationCall(call)
      this.setState({ incoming: call })
    } catch {
      /* ignore */
    }
  }

  async stop() {
    if (this.unloadBound) {
      window.removeEventListener('pagehide', this.unloadBound)
      window.removeEventListener('beforeunload', this.unloadBound)
      this.unloadBound = null
    }
    if (this.state.active) {
      try {
        await api.hangupCall(this.state.active.id)
      } catch {
        /* ignore */
      }
    }
    this.unsub?.()
    this.unsub = null
    await this.cleanupMedia()
    userSocket.disconnect()
    this.watchedConversationId = null
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
      await this.enterLocal(room, {
        muted: opts?.muted,
        cameraOff: opts?.cameraOff ?? true,
        stream: opts?.stream,
      })
      this.setState({ active: room, incoming: null, connecting: false, minimized: false })
      this.rememberConversationCall(room)
      await this.offerToJoinedPeers(room)
      // 同步服务端媒体态
      userSocket.send({
        type: 'call.media',
        callId: room.id,
        audio: !this.state.muted,
        video: room.kind === 'video' && !this.state.cameraOff,
      })
    } catch (e) {
      opts?.stream?.getTracks().forEach((t) => t.stop())
      this.setState({
        connecting: false,
        error: e instanceof Error ? e.message : '发起通话失败',
      })
      throw e
    }
  }

  async joinCall(
    callId: string,
    opts?: { muted?: boolean; cameraOff?: boolean; stream?: MediaStream },
  ) {
    if (this.state.connecting) return
    const cameraOff = opts?.cameraOff ?? true
    this.setState({ connecting: true, error: null, incoming: null })
    ringtone.stop()
    try {
      await this.ensureIce()
      const room = await api.acceptCall(callId)
      await this.enterLocal(room, { ...opts, cameraOff })
      this.setState({ active: room, connecting: false, minimized: false })
      this.rememberConversationCall(room)
      await this.offerToJoinedPeers(room)
      userSocket.send({
        type: 'call.media',
        callId: room.id,
        audio: !this.state.muted,
        video: room.kind === 'video' && !this.state.cameraOff,
      })
    } catch (e) {
      opts?.stream?.getTracks().forEach((t) => t.stop())
      await this.cleanupMedia()
      this.setState({
        active: null,
        remotes: [],
        localStream: null,
        connecting: false,
        error: e instanceof Error ? e.message : '加入通话失败',
      })
      throw e
    }
  }

  async acceptIncoming(opts?: { muted?: boolean; cameraOff?: boolean; stream?: MediaStream }) {
    const room = this.state.incoming
    if (!room || this.state.connecting) return
    await this.joinCall(room.id, { cameraOff: true, ...opts })
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
      minimized: false,
    })
    if (room && this.watchedConversationId === room.conversationId) {
      void this.watchConversation(room.conversationId)
    }
  }

  minimize() {
    if (this.state.active) this.setState({ minimized: true })
  }

  restore() {
    if (this.state.active) this.setState({ minimized: false })
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

  /** 切换前置/后置或下一台摄像头 */
  async switchCamera() {
    const room = this.state.active
    if (!room || room.kind !== 'video') return
    try {
      if (!navigator.mediaDevices?.enumerateDevices) {
        await this.replaceLocalVideoTrack({
          facingMode: this.facingMode === 'user' ? 'environment' : 'user',
        })
        return
      }
      // 部分浏览器需先有权限才会返回设备标签
      const devices = await navigator.mediaDevices.enumerateDevices()
      const cams = devices.filter((d) => d.kind === 'videoinput' && d.deviceId)
      if (cams.length >= 2) {
        const currentId =
          this.currentVideoDeviceId ||
          this.state.localStream?.getVideoTracks()[0]?.getSettings().deviceId ||
          this.rawLocalStream?.getVideoTracks()[0]?.getSettings().deviceId ||
          ''
        const idx = Math.max(
          0,
          cams.findIndex((c) => c.deviceId === currentId),
        )
        const next = cams[(idx + 1) % cams.length]
        await this.replaceLocalVideoTrack({ deviceId: { exact: next.deviceId } })
        return
      }
      await this.replaceLocalVideoTrack({
        facingMode: { ideal: this.facingMode === 'user' ? 'environment' : 'user' },
      })
    } catch (e) {
      this.setState({
        error: e instanceof Error ? e.message : '切换摄像头失败',
      })
    }
  }

  private async replaceLocalVideoTrack(video: MediaTrackConstraints) {
    const fresh = await navigator.mediaDevices.getUserMedia({ audio: false, video })
    const newTrack = fresh.getVideoTracks()[0]
    if (!newTrack) {
      fresh.getTracks().forEach((t) => t.stop())
      return
    }
    newTrack.enabled = !this.state.cameraOff

    const applyToStream = (stream: MediaStream | null) => {
      if (!stream) return
      for (const t of stream.getVideoTracks()) {
        stream.removeTrack(t)
        if (t !== newTrack) t.stop()
      }
      stream.addTrack(newTrack)
    }

    applyToStream(this.rawLocalStream)
    applyToStream(this.state.localStream)

    for (const [, entry] of this.peers) {
      const sender = entry.pc.getSenders().find((s) => s.track?.kind === 'video')
      if (sender) {
        try {
          await sender.replaceTrack(newTrack)
        } catch {
          /* ignore single-peer failure */
        }
      } else {
        // 尚无 video sender 时补上（极少见）
        try {
          entry.pc.addTrack(newTrack, this.state.localStream || fresh)
        } catch {
          /* ignore */
        }
      }
    }

    this.currentVideoDeviceId = newTrack.getSettings().deviceId || null
    const facing = newTrack.getSettings().facingMode
    if (facing === 'user' || facing === 'environment') {
      this.facingMode = facing
    } else {
      this.facingMode = this.facingMode === 'user' ? 'environment' : 'user'
    }
    // 触发预览刷新
    this.setState({
      localStream: this.state.localStream,
      error: null,
    })
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
    const vTrack = stream.getVideoTracks()[0]
    if (vTrack) {
      this.currentVideoDeviceId = vTrack.getSettings().deviceId || null
      const facing = vTrack.getSettings().facingMode
      if (facing === 'user' || facing === 'environment') this.facingMode = facing
    }
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
    this.currentVideoDeviceId = null
    this.facingMode = 'user'
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
        this.rememberConversationCall(call)
        if (this.state.active) return
        this.setState({ incoming: call })
        break
      }
      case 'call.started': {
        const call = data.call as CallRoom
        if (call) {
          this.rememberConversationCall(call)
          if (this.state.active?.id === call.id || call.hostId === this.userId) {
            this.setState({ active: call })
          }
        }
        break
      }
      case 'call.peer_joined': {
        const call = data.call as CallRoom | undefined
        const peer = data.peer as CallPeer | undefined
        if (call) {
          this.rememberConversationCall(call)
          if (this.state.active?.id === call.id) {
            this.setState({ active: call })
          }
        }
        // 新加入者会主动 offer；已在通话中的人等待对方 offer
        if (peer && peer.userId !== this.userId && this.state.active) {
          // no-op wait
        }
        break
      }
      case 'call.peer_left': {
        const peer = data.peer as CallPeer | undefined
        const call = data.call as CallRoom | undefined
        if (peer) this.removePeer(peer.userId)
        if (call) {
          this.rememberConversationCall(call)
          if (this.state.active?.id === call.id) {
            this.setState({ active: call })
          }
        }
        break
      }
      case 'call.peer_rejected': {
        // 私聊拒绝时随后会有 call.ended
        break
      }
      case 'call.ended': {
        const endedCall = data.call as CallRoom | undefined
        const convId =
          endedCall?.conversationId ||
          this.state.active?.conversationId ||
          this.state.incoming?.conversationId ||
          this.state.conversationCall?.conversationId ||
          ''
        const status = String(data.status || '')
        await this.cleanupMedia()
        this.setState({
          active: null,
          incoming: null,
          conversationCall:
            this.state.conversationCall?.conversationId === convId
              ? null
              : this.state.conversationCall,
          remotes: [],
          localStream: null,
          muted: false,
          cameraOff: false,
          speakerMuted: false,
          micVolume: 1,
          speakerVolume: 1,
          minimized: false,
        })
        this.emitCallEnded(convId, status)
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
