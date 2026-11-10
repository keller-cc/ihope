import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { loadOriginalImage, peekCachedOriginal } from '@/lib/imageCache'
import { useIsMobile } from '@/hooks/useIsMobile'

/** Photo-viewer style curved rotate arrow (ccw when mirrored). */
function RotateArrowIcon({ mirrored }: { mirrored?: boolean }) {
  return (
    <svg
      width="22"
      height="22"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden
      style={mirrored ? { transform: 'scaleX(-1)' } : undefined}
    >
      <path
        d="M20 10a8 8 0 1 0 1.7 6.5"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
      <path
        d="M20 4v6h-6"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

type Props = {
  open: boolean
  thumbUrl: string
  originalUrl: string
  onClose: () => void
}

function touchAngle(a: Touch, b: Touch): number {
  return (Math.atan2(b.clientY - a.clientY, b.clientX - a.clientX) * 180) / Math.PI
}

function snap90(deg: number): number {
  const n = ((Math.round(deg / 90) % 4) + 4) % 4
  return n * 90
}

export function ImageViewer({ open, thumbUrl, originalUrl, onClose }: Props) {
  const isMobile = useIsMobile()
  const [src, setSrc] = useState(() => peekCachedOriginal(originalUrl) || thumbUrl)
  const [loading, setLoading] = useState(!peekCachedOriginal(originalUrl))
  const [error, setError] = useState('')
  const [rotation, setRotation] = useState(0)
  const rotationRef = useRef(0)
  rotationRef.current = rotation
  const gesture = useRef<{
    startAngle: number
    baseRotation: number
  } | null>(null)

  useEffect(() => {
    if (!open) return
    setRotation(0)
    rotationRef.current = 0
    gesture.current = null
    const cached = peekCachedOriginal(originalUrl)
    if (cached) {
      setSrc(cached)
      setLoading(false)
      setError('')
      return
    }
    setSrc(thumbUrl)
    setLoading(true)
    setError('')
    let cancelled = false
    void loadOriginalImage(originalUrl)
      .then((u) => {
        if (!cancelled) {
          setSrc(u)
          setLoading(false)
        }
      })
      .catch(() => {
        if (!cancelled) {
          setLoading(false)
          setError('原图加载失败')
        }
      })
    return () => {
      cancelled = true
    }
  }, [open, originalUrl, thumbUrl])

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
      if (e.key === 'r' || e.key === 'R') {
        setRotation((deg) => (deg + 90) % 360)
      }
      if (e.key === 'l' || e.key === 'L') {
        setRotation((deg) => (deg + 270) % 360)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => {
      document.body.style.overflow = prev
      window.removeEventListener('keydown', onKey)
    }
  }, [open, onClose])

  if (!open) return null

  const sideways = rotation % 180 !== 0

  const onTouchStart = (e: React.TouchEvent) => {
    if (e.touches.length === 2) {
      gesture.current = {
        startAngle: touchAngle(e.touches[0], e.touches[1]),
        baseRotation: rotationRef.current,
      }
    }
  }

  const onTouchMove = (e: React.TouchEvent) => {
    if (e.touches.length !== 2 || !gesture.current) return
    e.preventDefault()
    const ang = touchAngle(e.touches[0], e.touches[1])
    const delta = ang - gesture.current.startAngle
    setRotation(gesture.current.baseRotation + delta)
  }

  const onTouchEnd = (e: React.TouchEvent) => {
    if (e.touches.length >= 2) return
    if (gesture.current) {
      setRotation((deg) => snap90(deg))
      gesture.current = null
    }
  }

  return createPortal(
    <div
      className="im-img-viewer"
      role="dialog"
      aria-modal
      onClick={onClose}
      onKeyDown={(e) => e.key === 'Escape' && onClose()}
    >
      <button type="button" className="im-img-viewer__close" onClick={onClose} aria-label="关闭">
        ✕
      </button>
      {loading && <div className="im-img-viewer__hint">加载原图…</div>}
      {error && <div className="im-img-viewer__hint">{error}</div>}

      <div
        className="im-img-viewer__stage"
        onClick={(e) => e.stopPropagation()}
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
        onTouchCancel={onTouchEnd}
      >
        <img
          className="im-img-viewer__img"
          src={src}
          alt=""
          draggable={false}
          style={{
            transform: `rotate(${rotation}deg)`,
            maxWidth: sideways ? 'min(90vh, 100%)' : undefined,
            maxHeight: sideways ? 'min(96vw, 100%)' : undefined,
          }}
        />
        {isMobile && (
          <p className="im-img-viewer__gesture-tip">双指旋转可调整方向</p>
        )}
      </div>

      {!isMobile && (
        <div
          className="im-img-viewer__dock"
          onClick={(e) => e.stopPropagation()}
        >
          <button
            type="button"
            className="im-img-viewer__dock-btn"
            title="逆时针"
            aria-label="逆时针"
            onClick={() => setRotation((deg) => (deg + 270) % 360)}
          >
            <RotateArrowIcon mirrored />
          </button>
          <button
            type="button"
            className="im-img-viewer__dock-btn"
            title="顺时针"
            aria-label="顺时针"
            onClick={() => setRotation((deg) => (deg + 90) % 360)}
          >
            <RotateArrowIcon />
          </button>
        </div>
      )}
    </div>,
    document.body,
  )
}
