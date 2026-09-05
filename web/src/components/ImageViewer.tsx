import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { loadOriginalImage, peekCachedOriginal } from '../lib/imageCache'

type Props = {
  open: boolean
  thumbUrl: string
  originalUrl: string
  onClose: () => void
}

export function ImageViewer({ open, thumbUrl, originalUrl, onClose }: Props) {
  const [src, setSrc] = useState(() => peekCachedOriginal(originalUrl) || thumbUrl)
  const [loading, setLoading] = useState(!peekCachedOriginal(originalUrl))
  const [error, setError] = useState('')

  useEffect(() => {
    if (!open) return
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
    }
    window.addEventListener('keydown', onKey)
    return () => {
      document.body.style.overflow = prev
      window.removeEventListener('keydown', onKey)
    }
  }, [open, onClose])

  if (!open) return null

  return createPortal(
    <div
      className="im-img-viewer"
      role="dialog"
      aria-modal
      onClick={onClose}
      onKeyDown={(e) => e.key === 'Escape' && onClose()}
    >
      <button type="button" className="im-img-viewer__close" onClick={onClose}>
        ✕
      </button>
      {loading && <div className="im-img-viewer__hint">加载原图…</div>}
      {error && <div className="im-img-viewer__hint">{error}</div>}
      <img
        className="im-img-viewer__img"
        src={src}
        alt=""
        onClick={(e) => e.stopPropagation()}
      />
    </div>,
    document.body,
  )
}
