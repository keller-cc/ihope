import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import {
  CallIcon,
  CallOffIcon,
  Camera2Icon,
  CameraOffIcon,
  LoudspeakerIcon,
  Microphone1Icon,
  SoundMute1Icon,
  SoundMuteIcon,
  VideoCamera1Icon,
} from 'tdesign-icons-react'
import { Button } from 'tdesign-react'
import { Avatar } from '@/components/Avatar'
import { callController, type CallUIState } from '@/lib/call/CallController'
import type { RemoteMedia } from '@/lib/call/types'
import { ringtone } from '@/lib/call/ringtone'

function useCallState(): CallUIState {
  const [state, setState] = useState(callController.state)
  useEffect(() => {
    return callController.subscribe(() => setState({ ...callController.state }))
  }, [])
  return state
}

function VideoTile({
  stream,
  muted,
  volume = 1,
  label,
  mirror,
  className = '',
  showLabel = true,
}: {
  stream: MediaStream | null
  muted?: boolean
  volume?: number
  label?: string
  mirror?: boolean
  className?: string
  showLabel?: boolean
}) {
  const ref = useRef<HTMLVideoElement>(null)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    el.srcObject = stream
  }, [stream])
  useEffect(() => {
    const el = ref.current
    if (!el) return
    el.volume = muted ? 0 : Math.max(0, Math.min(1, volume))
  }, [muted, volume])
  return (
    <div className={['im-call-tile', className].filter(Boolean).join(' ')}>
      {stream ? (
        <video
          ref={ref}
          className={mirror ? 'im-call-tile__video is-mirror' : 'im-call-tile__video'}
          autoPlay
          playsInline
          muted={muted}
        />
      ) : (
        <div className="im-call-tile__empty" />
      )}
      {showLabel && label ? <span className="im-call-tile__name">{label}</span> : null}
    </div>
  )
}

/** 可拖动的画中画；轻点切换大小屏 */
function DraggablePip({
  children,
  onSwap,
  title = '拖动移动，点击切换大小屏',
}: {
  children: React.ReactNode
  onSwap: () => void
  title?: string
}) {
  const stageRef = useRef<HTMLElement | null>(null)
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null)
  const drag = useRef<{
    pointerId: number
    startX: number
    startY: number
    origX: number
    origY: number
    moved: boolean
  } | null>(null)

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return
    const el = e.currentTarget
    const parent = el.offsetParent as HTMLElement | null
    stageRef.current = parent
    const rect = el.getBoundingClientRect()
    const parentRect = parent?.getBoundingClientRect()
    const curX = pos?.x ?? (parentRect ? rect.left - parentRect.left : el.offsetLeft)
    const curY = pos?.y ?? (parentRect ? rect.top - parentRect.top : el.offsetTop)
    drag.current = {
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      origX: curX,
      origY: curY,
      moved: false,
    }
    el.setPointerCapture(e.pointerId)
  }

  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const d = drag.current
    if (!d || d.pointerId !== e.pointerId) return
    const dx = e.clientX - d.startX
    const dy = e.clientY - d.startY
    if (Math.abs(dx) > 4 || Math.abs(dy) > 4) d.moved = true
    if (!d.moved) return

    const el = e.currentTarget
    const parent = stageRef.current || (el.offsetParent as HTMLElement | null)
    if (!parent) return
    const maxX = Math.max(0, parent.clientWidth - el.offsetWidth)
    const maxY = Math.max(0, parent.clientHeight - el.offsetHeight)
    setPos({
      x: Math.min(maxX, Math.max(0, d.origX + dx)),
      y: Math.min(maxY, Math.max(0, d.origY + dy)),
    })
  }

  const onPointerUp = (e: ReactPointerEvent<HTMLDivElement>) => {
    const d = drag.current
    if (!d || d.pointerId !== e.pointerId) return
    drag.current = null
    try {
      e.currentTarget.releasePointerCapture(e.pointerId)
    } catch {
      /* ignore */
    }
    if (!d.moved) onSwap()
  }

  return (
    <div
      className="im-call-tile im-call-tile--pip"
      title={title}
      style={
        pos
          ? { left: pos.x, top: pos.y, right: 'auto', bottom: 'auto' }
          : undefined
      }
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
    >
      {children}
    </div>
  )
}

function RemoteAudio({
  stream,
  volume,
  muted,
}: {
  stream: MediaStream
  volume: number
  muted?: boolean
}) {
  const ref = useRef<HTMLAudioElement>(null)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    el.srcObject = stream
  }, [stream])
  useEffect(() => {
    const el = ref.current
    if (!el) return
    el.volume = muted ? 0 : Math.max(0, Math.min(1, volume))
    el.muted = !!muted
  }, [volume, muted])
  return <audio ref={ref} autoPlay playsInline />
}

function AudioAvatar({
  name,
  avatarUrl,
  speaking,
}: {
  name: string
  avatarUrl?: string | null
  speaking?: boolean
}) {
  return (
    <div className={speaking ? 'im-call-avatar is-live' : 'im-call-avatar'}>
      <Avatar name={name} src={avatarUrl} size="xl" />
      <span>{name}</span>
    </div>
  )
}

function PipVideoBody({
  stream,
  muted,
  volume = 1,
  label,
  mirror,
}: {
  stream: MediaStream | null
  muted?: boolean
  volume?: number
  label: string
  mirror?: boolean
}) {
  const ref = useRef<HTMLVideoElement>(null)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    el.srcObject = stream
  }, [stream])
  useEffect(() => {
    const el = ref.current
    if (!el || muted) return
    el.volume = Math.max(0, Math.min(1, volume))
  }, [muted, volume])
  return (
    <>
      {stream ? (
        <video
          ref={ref}
          className={mirror ? 'im-call-tile__video is-mirror' : 'im-call-tile__video'}
          autoPlay
          playsInline
          muted={muted}
        />
      ) : (
        <div className="im-call-tile__empty" />
      )}
      <span className="im-call-tile__name">{label}</span>
    </>
  )
}

type Props = {
  selfName: string
  selfAvatar?: string | null
  resolveTitle?: (conversationId: string) => string | undefined
}

export function CallOverlay({ selfName, selfAvatar, resolveTitle }: Props) {
  const state = useCallState()
  const [elapsed, setElapsed] = useState(0)
  /** false = 对方大屏、自己小窗；true = 自己大屏、对方小窗 */
  const [selfOnMain, setSelfOnMain] = useState(false)
  const [focusRemoteId, setFocusRemoteId] = useState<string | null>(null)
  const room = state.active
  const isVideo = room?.kind === 'video'
  const ringing = room?.status === 'ringing'
  const connecting = state.connecting
  const hasRemote = state.remotes.length > 0
  const outVolume = state.speakerMuted ? 0 : state.speakerVolume

  useEffect(() => {
    setSelfOnMain(false)
    setFocusRemoteId(null)
  }, [room?.id])

  useEffect(() => {
    if (!room?.startedAt && room?.status !== 'active') {
      setElapsed(0)
      return
    }
    const start = room.startedAt ? Date.parse(room.startedAt) : Date.now()
    const tick = () => setElapsed(Math.max(0, Math.floor((Date.now() - start) / 1000)))
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [room?.id, room?.startedAt, room?.status])

  useEffect(() => {
    // 仅主叫振铃播等待音；接听方 connecting 时不播
    if (room && ringing && !connecting) {
      ringtone.start('outgoing')
      return () => ringtone.stop()
    }
    ringtone.stop()
    return undefined
  }, [room?.id, ringing, connecting])

  if (!room || state.minimized) return null

  const peer = room.participants.find((p) => p.userId !== callController.userId)
  const title =
    resolveTitle?.(room.conversationId) ||
    (room.convType === 'group' ? '群通话' : peer?.username || '通话')
  const mm = String(Math.floor(elapsed / 60)).padStart(2, '0')
  const ss = String(elapsed % 60).padStart(2, '0')
  const statusText = connecting
    ? '正在连接…'
    : ringing
      ? '等待对方接听…'
      : `${mm}:${ss}`

  const focusedRemote: RemoteMedia | null =
    state.remotes.find((r) => r.userId === focusRemoteId) || state.remotes[0] || null
  const otherRemotes = state.remotes.filter((r) => r.userId !== focusedRemote?.userId)

  const swapMainPip = () => setSelfOnMain((v) => !v)

  return (
    <div className={isVideo ? 'im-call-overlay im-call-overlay--video' : 'im-call-overlay'}>
      <div className="im-call-overlay__head">
        <div className="im-call-overlay__head-text">
          <strong>{title}</strong>
          <span>
            {room.kind === 'video' ? '视频通话' : '语音通话'} · {statusText}
          </span>
        </div>
        <button
          type="button"
          className="im-call-overlay__minimize"
          title="最小化，回到聊天（可从顶部通话条返回）"
          aria-label="最小化通话"
          onClick={() => callController.minimize()}
        >
          最小化
        </button>
      </div>

      <div
        className={
          isVideo
            ? hasRemote
              ? 'im-call-overlay__stage im-call-overlay__stage--pip'
              : 'im-call-overlay__stage im-call-overlay__stage--solo'
            : 'im-call-overlay__stage'
        }
      >
        {isVideo ? (
          hasRemote ? (
            <>
              <div
                className={
                  !selfOnMain && otherRemotes.length > 0
                    ? 'im-call-main im-call-main--grid'
                    : 'im-call-main'
                }
              >
                {selfOnMain ? (
                  <VideoTile
                    stream={state.localStream}
                    muted
                    mirror
                    label={selfName}
                    className="im-call-tile--main"
                  />
                ) : otherRemotes.length > 0 ? (
                  <>
                    {focusedRemote && (
                      <div
                        key={focusedRemote.userId}
                        className="im-call-tile im-call-tile--main"
                      >
                        <PipVideoBody
                          stream={focusedRemote.stream}
                          label={focusedRemote.username || '对方'}
                          volume={outVolume}
                          muted={state.speakerMuted}
                        />
                      </div>
                    )}
                    {otherRemotes.map((r) => (
                      <button
                        key={r.userId}
                        type="button"
                        className="im-call-tile im-call-tile--main im-call-tile--pick"
                        onClick={() => setFocusRemoteId(r.userId)}
                      >
                        <PipVideoBody
                          stream={r.stream}
                          label={r.username || '对方'}
                          volume={outVolume}
                          muted={state.speakerMuted}
                        />
                      </button>
                    ))}
                  </>
                ) : (
                  focusedRemote && (
                    <VideoTile
                      stream={focusedRemote.stream}
                      label={focusedRemote.username || '对方'}
                      className="im-call-tile--main"
                      volume={outVolume}
                      muted={state.speakerMuted}
                    />
                  )
                )}
              </div>
              <DraggablePip onSwap={swapMainPip}>
                {selfOnMain && focusedRemote ? (
                  <PipVideoBody
                    stream={focusedRemote.stream}
                    label={focusedRemote.username || '对方'}
                    volume={outVolume}
                    muted={state.speakerMuted}
                  />
                ) : (
                  <PipVideoBody
                    stream={state.localStream}
                    muted
                    mirror
                    label={selfName}
                  />
                )}
              </DraggablePip>
            </>
          ) : (
            <>
              <VideoTile
                stream={state.localStream}
                muted
                mirror
                label={selfName}
                className="im-call-tile--solo"
                showLabel={false}
              />
              <div className="im-call-overlay__wait im-call-overlay__wait--on-video">
                {connecting ? '正在连接…' : ringing ? '正在呼叫…' : '连接中…'}
              </div>
            </>
          )
        ) : (
          <div className="im-call-overlay__voices">
            {state.remotes.map((r) => (
              <RemoteAudio
                key={r.userId}
                stream={r.stream}
                volume={state.speakerVolume}
                muted={state.speakerMuted}
              />
            ))}
            {ringing ? (
              <>
                <AudioAvatar
                  name={peer?.username || title}
                  avatarUrl={peer?.avatarUrl}
                />
                <p className="im-call-overlay__wait">
                  {connecting ? '正在连接…' : '正在呼叫对方…'}
                </p>
              </>
            ) : (
              <>
                <AudioAvatar name={selfName} avatarUrl={selfAvatar} speaking={!state.muted} />
                {room.participants
                  .filter((p) => p.userId !== callController.userId && p.state === 'joined')
                  .map((p) => (
                    <AudioAvatar
                      key={p.userId}
                      name={p.username}
                      avatarUrl={p.avatarUrl}
                      speaking={p.audio}
                    />
                  ))}
              </>
            )}
          </div>
        )}
      </div>

      <div className="im-call-overlay__bar im-call-overlay__bar--live">
        <button
          type="button"
          className={
            state.muted
              ? 'im-call-ctrl im-call-ctrl--labeled is-off'
              : 'im-call-ctrl im-call-ctrl--labeled'
          }
          title={state.muted ? '取消静音' : '静音'}
          onClick={() => void callController.toggleMute()}
        >
          {state.muted ? <SoundMute1Icon size="24px" /> : <Microphone1Icon size="24px" />}
          <span className="im-call-ctrl__label">{state.muted ? '已静音' : '静音'}</span>
        </button>
        <button
          type="button"
          className={
            state.speakerMuted
              ? 'im-call-ctrl im-call-ctrl--labeled is-off'
              : 'im-call-ctrl im-call-ctrl--labeled'
          }
          title={state.speakerMuted ? '打开扬声器' : '扬声器'}
          onClick={() => callController.toggleSpeaker()}
        >
          {state.speakerMuted ? <SoundMuteIcon size="24px" /> : <LoudspeakerIcon size="24px" />}
          <span className="im-call-ctrl__label">
            {state.speakerMuted ? '听筒' : '扬声器'}
          </span>
        </button>
        <button
          type="button"
          className="im-call-ctrl im-call-ctrl--hangup im-call-ctrl--labeled"
          title={ringing || connecting ? '取消' : '挂断'}
          onClick={() => void callController.hangup()}
        >
          <CallOffIcon size="28px" />
          <span className="im-call-ctrl__label">
            {ringing || connecting ? '取消' : '挂断'}
          </span>
        </button>
        {isVideo && (
          <button
            type="button"
            className={
              state.cameraOff
                ? 'im-call-ctrl im-call-ctrl--labeled is-off'
                : 'im-call-ctrl im-call-ctrl--labeled'
            }
            title={state.cameraOff ? '打开摄像头' : '关闭摄像头'}
            onClick={() => void callController.toggleCamera()}
          >
            {state.cameraOff ? <CameraOffIcon size="24px" /> : <VideoCamera1Icon size="24px" />}
            <span className="im-call-ctrl__label">
              {state.cameraOff ? '摄像头关' : '摄像头'}
            </span>
          </button>
        )}
        {isVideo && (
          <button
            type="button"
            className="im-call-ctrl im-call-ctrl--labeled"
            title="切换摄像头"
            aria-label="切换摄像头"
            onClick={() => void callController.switchCamera()}
          >
            <Camera2Icon size="24px" />
            <span className="im-call-ctrl__label">翻转</span>
          </button>
        )}
      </div>
    </div>
  )
}

export function IncomingCallModal({
  onOpenChat,
}: {
  onOpenChat?: (conversationId: string) => void
}) {
  const state = useCallState()
  const incoming = state.incoming
  const [accepting, setAccepting] = useState(false)

  useEffect(() => {
    if (incoming && !state.connecting && !accepting) {
      ringtone.start('incoming')
      return () => ringtone.stop()
    }
    ringtone.stop()
    return undefined
  }, [incoming?.id, state.connecting, accepting])

  useEffect(() => {
    if (!incoming) setAccepting(false)
  }, [incoming?.id])

  if (!incoming) return null
  const host = incoming.participants.find((p) => p.userId === incoming.hostId)
  const label = incoming.kind === 'video' ? '邀请你视频通话' : '邀请你语音通话'
  return (
    <div className="im-call-incoming">
      <div className="im-call-incoming__card">
        <Avatar name={host?.username || '来电'} src={host?.avatarUrl} size="lg" />
        <div className="im-call-incoming__meta">
          <strong>{host?.username || '好友'}</strong>
          <span>{accepting || state.connecting ? '正在接听…' : label}</span>
        </div>
        <div className="im-call-incoming__actions">
          <Button
            theme="danger"
            shape="round"
            disabled={accepting || state.connecting}
            onClick={() => void callController.rejectIncoming()}
          >
            拒绝
          </Button>
          <Button
            theme="success"
            shape="round"
            icon={<CallIcon />}
            loading={accepting || state.connecting}
            disabled={accepting || state.connecting}
            onClick={() => {
              setAccepting(true)
              ringtone.stop()
              onOpenChat?.(incoming.conversationId)
              void callController.acceptIncoming({ cameraOff: true }).catch(() => {
                setAccepting(false)
              })
            }}
          >
            接听
          </Button>
        </div>
      </div>
    </div>
  )
}
