import { useEffect, useRef, useState } from 'react'
import {
  CallIcon,
  CameraOffIcon,
  Microphone1Icon,
  SoundMute1Icon,
  VideoCamera1Icon,
} from 'tdesign-icons-react'
import { Button, Dialog, MessagePlugin } from 'tdesign-react'
import type { CallKind } from '../api'
import { Avatar } from './Avatar'

export type CallSetupResult = {
  kind: CallKind
  muted: boolean
  cameraOff: boolean
  stream: MediaStream
}

type Props = {
  visible: boolean
  kind: CallKind
  title: string
  selfName: string
  selfAvatar?: string | null
  busy?: boolean
  onCancel: () => void
  onConfirm: (result: CallSetupResult) => void
}

export function CallSetupDialog({
  visible,
  kind,
  title,
  selfName,
  selfAvatar,
  busy,
  onCancel,
  onConfirm,
}: Props) {
  const isVideo = kind === 'video'
  const [muted, setMuted] = useState(false)
  const [cameraOff, setCameraOff] = useState(false)
  const [stream, setStream] = useState<MediaStream | null>(null)
  const [prepError, setPrepError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)

  const stopStream = (s: MediaStream | null) => {
    s?.getTracks().forEach((t) => t.stop())
  }

  useEffect(() => {
    if (!visible) {
      stopStream(streamRef.current)
      streamRef.current = null
      setStream(null)
      setPrepError(null)
      setMuted(false)
      setCameraOff(false)
      setLoading(false)
      return
    }

    let cancelled = false
    setLoading(true)
    setPrepError(null)
    void navigator.mediaDevices
      .getUserMedia({ audio: true, video: isVideo })
      .then((s) => {
        if (cancelled) {
          stopStream(s)
          return
        }
        streamRef.current = s
        setStream(s)
        setLoading(false)
      })
      .catch(() => {
        if (cancelled) return
        setPrepError(isVideo ? '无法访问麦克风或摄像头' : '无法访问麦克风')
        setLoading(false)
      })

    return () => {
      cancelled = true
      stopStream(streamRef.current)
      streamRef.current = null
    }
  }, [visible, isVideo])

  useEffect(() => {
    const el = videoRef.current
    if (!el) return
    el.srcObject = stream
  }, [stream])

  useEffect(() => {
    if (!stream) return
    for (const t of stream.getAudioTracks()) t.enabled = !muted
  }, [stream, muted])

  useEffect(() => {
    if (!stream) return
    for (const t of stream.getVideoTracks()) t.enabled = !cameraOff
  }, [stream, cameraOff])

  const handleCancel = () => {
    stopStream(streamRef.current)
    streamRef.current = null
    setStream(null)
    onCancel()
  }

  const handleConfirm = () => {
    const s = streamRef.current
    if (!s) {
      MessagePlugin.warning(prepError || '请先允许媒体权限')
      return
    }
    // 移交轨道所有权给通话控制器，对话框不再 stop
    streamRef.current = null
    setStream(null)
    onConfirm({ kind, muted, cameraOff, stream: s })
  }

  return (
    <Dialog
      visible={visible}
      header={isVideo ? '发起视频通话' : '发起语音通话'}
      width={400}
      destroyOnClose
      onClose={handleCancel}
      footer={
        <div className="im-call-setup__footer">
          <Button variant="outline" disabled={busy} onClick={handleCancel}>
            取消
          </Button>
          <Button
            theme="primary"
            loading={busy || loading}
            disabled={!!prepError || !stream}
            icon={<CallIcon />}
            onClick={handleConfirm}
          >
            发起通话
          </Button>
        </div>
      }
    >
      <div className="im-call-setup">
        <p className="im-call-setup__to">将呼叫：{title}</p>

        <div className={isVideo ? 'im-call-setup__preview im-call-setup__preview--video' : 'im-call-setup__preview'}>
          {isVideo ? (
            cameraOff || !stream ? (
              <div className="im-call-setup__avatar-wrap">
                <Avatar name={selfName} src={selfAvatar} size="xl" />
                <span>{cameraOff ? '摄像头已关闭' : loading ? '正在开启摄像头…' : '无预览'}</span>
              </div>
            ) : (
              <video ref={videoRef} className="im-call-setup__video is-mirror" autoPlay playsInline muted />
            )
          ) : (
            <div className="im-call-setup__avatar-wrap">
              <Avatar name={selfName} src={selfAvatar} size="xl" />
              <span>{selfName}</span>
            </div>
          )}
        </div>

        {prepError && <p className="im-call-setup__err">{prepError}</p>}

        <div className="im-call-setup__toggles">
          <button
            type="button"
            className={muted ? 'im-call-setup__tog is-off' : 'im-call-setup__tog'}
            title={muted ? '打开麦克风' : '关闭麦克风'}
            disabled={!stream}
            onClick={() => setMuted((v) => !v)}
          >
            {muted ? <SoundMute1Icon size="22px" /> : <Microphone1Icon size="22px" />}
            <span>{muted ? '麦克风关' : '麦克风开'}</span>
          </button>
          {isVideo && (
            <button
              type="button"
              className={cameraOff ? 'im-call-setup__tog is-off' : 'im-call-setup__tog'}
              title={cameraOff ? '打开摄像头' : '关闭摄像头'}
              disabled={!stream}
              onClick={() => setCameraOff((v) => !v)}
            >
              {cameraOff ? <CameraOffIcon size="22px" /> : <VideoCamera1Icon size="22px" />}
              <span>{cameraOff ? '摄像头关' : '摄像头开'}</span>
            </button>
          )}
        </div>
      </div>
    </Dialog>
  )
}
