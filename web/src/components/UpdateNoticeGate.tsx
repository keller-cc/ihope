import { useEffect, useState } from 'react'
import { MessagePlugin } from 'tdesign-react'
import { api, apiErrorMessage, type UpdateNotice } from '@/api'
import { UpdateNoticeDialog } from './UpdateNoticeUI'

/** Shows the latest unread admin notice once after login (QQ/WeChat style). */
export function UpdateNoticeGate() {
  const [notice, setNotice] = useState<UpdateNotice | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let cancelled = false
    void api
      .updateNoticePending()
      .then((r) => {
        if (!cancelled && r.notice) setNotice(r.notice)
      })
      .catch(() => {
        /* ignore — non-critical */
      })
    return () => {
      cancelled = true
    }
  }, [])

  const dismiss = async () => {
    if (!notice) return
    setBusy(true)
    try {
      await api.ackUpdateNotice(notice.id)
      setNotice(null)
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '关闭失败'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <UpdateNoticeDialog
      notice={notice}
      confirmText="知道了"
      confirmLoading={busy}
      closeOnOverlayClick={false}
      onClose={() => void dismiss()}
      onConfirm={() => void dismiss()}
    />
  )
}
