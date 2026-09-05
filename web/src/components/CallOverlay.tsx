import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import {
  CallIcon,
  CallOffIcon,
  CameraOffIcon,
  Microphone1Icon,
  SoundMute1Icon,
  VideoCamera1Icon,
} from 'tdesign-icons-react'
import { Button } from 'tdesign-react'
import { Avatar } from './Avatar'
import { callController, type CallUIState } from '../lib/call/CallController'
import type { RemoteMedia } from '../lib/call/types'
import { ringtone } from '../lib/call/ringtone'

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
  label,
  mirror,
  className = '',
  showLabel = true,
}: {
  stream: MediaStream | null
  muted?: boolean
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

function RemoteAudio({ stream }: { stream: MediaStream }) {
  const ref = useRef<HTMLAudioElement>(null)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    el.srcObject = stream
  }, [stream])
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
  label,
  mirror,
}: {
  stream: MediaStream | null
  muted?: boolean
  label: string
  mirror?: boolean
}) {
  const ref = useRef<HTMLVideoElement>(null)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    el.srcObject = stream
  }, [stream])
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
  const hasRemote = state.remotes.length > 0

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
    if (room && ringing) {
      ringtone.start('outgoing')
      return () => ringtone.stop()
    }
    ringtone.stop()
    return undefined
  }, [room?.id, ringing])

  if (!room) return null

  const peer = room.participants.find((p) => p.userId !== callController.userId)
  const title =
    resolveTitle?.(room.conversationId) ||
    (room.convType === 'group' ? '群通话' : peer?.username || '通话')
  const mm = String(Math.floor(elapsed / 60)).padStart(2, '0')
  const ss = String(elapsed % 60).padStart(2, '0')
  const statusText = ringing ? '等待对方接听…' : `${mm}:${ss}`

  const focusedRemote: RemoteMedia | null =
    state.remotes.find((r) => r.userId === focusRemoteId) || state.remotes[0] || null
  const otherRemotes = state.remotes.filter((r) => r.userId !== focusedRemote?.userId)

  const swapMainPip = () => setSelfOnMain((v) => !v)

  return (
    <div className={isVideo ? 'im-call-overlay im-call-overlay--video' : 'im-call-overlay'}>
      <div className="im-call-overlay__head">
        <strong>{title}</strong>
        <span>
          {room.kind === 'video' ? '视频通话' : '语音通话'} · {statusText}
        </span>
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
                        <PipVideoBody stream={r.stream} label={r.username || '对方'} />
                      </button>
                    ))}
                  </>
                ) : (
                  focusedRemote && (
                    <VideoTile
                      stream={focusedRemote.stream}
                      label={focusedRemote.username || '对方'}
                      className="im-call-tile--main"
                    />
                  )
                )}
              </div>
              <DraggablePip onSwap={swapMainPip}>
                {selfOnMain && focusedRemote ? (
                  <PipVideoBody
                    stream={focusedRemote.stream}
                    label={focusedRemote.username || '对方'}
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
                {ringing ? '正在呼叫…' : '连接中…'}
              </div>
            </>
          )
        ) : (
          <div className="im-call-overlay__voices">
            {state.remotes.map((r) => (
              <RemoteAudio key={r.userId} stream={r.stream} />
            ))}
            {ringing ? (
              <>
                <AudioAvatar
                  name={peer?.username || title}
                  avatarUrl={peer?.avatarUrl}
                />
                <p className="im-call-overlay__wait">正在呼叫对方…</p>
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

      <div className="im-call-overlay__bar">
        <button
          type="button"
          className="im-call-ctrl"
          title={state.muted ? '取消静音' : '静音'}
          onClick={() => void callController.toggleMute()}
        >
          {state.muted ? <SoundMute1Icon size="22px" /> : <Microphone1Icon size="22px" />}
        </button>
        {isVideo && (
          <button
            type="button"
            className="im-call-ctrl"
            title={state.cameraOff ? '打开摄像头' : '关闭摄像头'}
            onClick={() => void callController.toggleCamera()}
          >
            {state.cameraOff ? <CameraOffIcon size="22px" /> : <VideoCamera1Icon size="22px" />}
          </button>
        )}
        <button
          type="button"
          className="im-call-ctrl im-call-ctrl--hangup"
          title="挂断"
          onClick={() => void callController.hangup()}
        >
          <CallOffIcon size="24px" />
        </button>
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

  useEffect(() => {
    if (incoming) {
      ringtone.start('incoming')
      return () => ringtone.stop()
    }
    return undefined
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
          <span>{label}</span>
        </div>
        <div className="im-call-incoming__actions">
          <Button
            theme="danger"
            shape="round"
            onClick={() => void callController.rejectIncoming()}
          >
            拒绝
          </Button>
          <Button
            theme="success"
            shape="round"
            icon={<CallIcon />}
            onClick={() => {
              onOpenChat?.(incoming.conversationId)
              void callController.acceptIncoming().catch(() => undefined)
            }}
          >
            接听
          </Button>
        </div>
      </div>
    </div>
  )
}
