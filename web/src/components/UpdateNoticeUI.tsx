import type { ReactNode } from 'react'
import { ChevronRightIcon } from 'tdesign-icons-react'
import { Button, Dialog } from 'tdesign-react'
import type { UpdateNotice } from '@/api'

export type NoticeListItem = Pick<
  UpdateNotice,
  'id' | 'title' | 'body' | 'published' | 'publishedAt' | 'createdAt'
>

export function noticeDateLabel(n: NoticeListItem): string {
  const raw = n.publishedAt || n.createdAt || ''
  return raw.slice(0, 10) || '—'
}

/** First three non-empty lines of notice body for list preview. */
export function noticeBodyPreview(body: string, maxLines = 3): string {
  const lines = String(body || '')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean)
  if (lines.length === 0) return ''
  return lines.slice(0, maxLines).join('\n')
}

type ListProps = {
  notices: NoticeListItem[]
  loading?: boolean
  emptyText?: string
  onSelect: (notice: NoticeListItem) => void
}

/** Settings-style notice list with title + 3-line body preview. */
export function UpdateNoticeList({
  notices,
  loading,
  emptyText = '暂无更新公告',
  onSelect,
}: ListProps) {
  if (loading) {
    return (
      <p className="im-muted" style={{ padding: 16 }}>
        加载中…
      </p>
    )
  }
  if (notices.length === 0) {
    return (
      <p className="im-muted" style={{ padding: 16 }}>
        {emptyText}
      </p>
    )
  }
  return (
    <div className="im-set-group">
      {notices.map((n) => {
        const preview = noticeBodyPreview(n.body)
        return (
          <button
            key={n.id}
            type="button"
            className="im-set-cell im-set-cell--notice"
            onClick={() => onSelect(n)}
          >
            <span className="im-set-cell__notice-main">
              <span className="im-set-cell__notice-title">{n.title}</span>
              {preview ? (
                <span className="im-set-cell__notice-preview">{preview}</span>
              ) : null}
              <span className="im-set-cell__notice-date">{noticeDateLabel(n)}</span>
            </span>
            <ChevronRightIcon size="16px" className="im-set-cell__arrow" />
          </button>
        )
      })}
    </div>
  )
}

type DialogProps = {
  notice: NoticeListItem | null
  confirmText?: string
  confirmLoading?: boolean
  closeOnOverlayClick?: boolean
  /** When set, replaces the default confirm button row. */
  footer?: ReactNode
  showStatus?: boolean
  onClose: () => void
  onConfirm?: () => void
}

/** Shared read dialog (first-entry gate, settings, admin preview). */
export function UpdateNoticeDialog({
  notice,
  confirmText = '知道了',
  confirmLoading,
  closeOnOverlayClick = true,
  footer,
  showStatus,
  onClose,
  onConfirm,
}: DialogProps) {
  return (
    <Dialog
      visible={!!notice}
      header={notice?.title || '更新公告'}
      confirmBtn={
        footer
          ? null
          : onConfirm
            ? { content: confirmText, loading: !!confirmLoading }
            : { content: '关闭' }
      }
      cancelBtn={null}
      closeOnOverlayClick={closeOnOverlayClick}
      closeOnEscKeydown={closeOnOverlayClick}
      onClose={onClose}
      onConfirm={() => (onConfirm ? onConfirm() : onClose())}
      className="im-update-notice-dialog"
      footer={footer ?? undefined}
    >
      {notice && (
        <>
          <p className="im-muted" style={{ fontSize: 12, margin: '0 0 12px' }}>
            {noticeDateLabel(notice)}
            {showStatus ? ` · ${notice.published ? '已发布' : '草稿'}` : ''}
          </p>
          <pre className="im-update-notice-body">{notice.body}</pre>
        </>
      )}
    </Dialog>
  )
}

type AdminFooterProps = {
  notice: NoticeListItem
  busy?: boolean
  onEdit: () => void
  onTogglePublish: () => void
  onDelete: () => void
  onClose: () => void
}

export function UpdateNoticeAdminFooter({
  notice,
  busy,
  onEdit,
  onTogglePublish,
  onDelete,
  onClose,
}: AdminFooterProps) {
  return (
    <div className="im-update-notice-footer">
      <Button size="small" variant="outline" theme="danger" disabled={busy} onClick={onDelete}>
        删除
      </Button>
      <div style={{ flex: 1 }} />
      <Button size="small" variant="outline" disabled={busy} onClick={onTogglePublish}>
        {notice.published ? '撤回' : '发布'}
      </Button>
      <Button size="small" variant="outline" disabled={busy} onClick={onEdit}>
        编辑
      </Button>
      <Button size="small" theme="primary" disabled={busy} onClick={onClose}>
        关闭
      </Button>
    </div>
  )
}
