/** 原图请求去重 + 内存缓存，避免重复拉同一 URL */

const memory = new Map<string, string>()
const inflight = new Map<string, Promise<string>>()

/** 返回可用于 <img src> 的地址；已缓存则直接返回，进行中则复用同一 Promise。 */
export function loadOriginalImage(url: string): Promise<string> {
  const key = url.trim()
  if (!key) return Promise.reject(new Error('empty url'))
  const hit = memory.get(key)
  if (hit) return Promise.resolve(hit)
  const pending = inflight.get(key)
  if (pending) return pending

  const job = (async () => {
    try {
      const res = await fetch(key, { credentials: 'same-origin' })
      if (!res.ok) throw new Error(`http ${res.status}`)
      const blob = await res.blob()
      const objectUrl = URL.createObjectURL(blob)
      memory.set(key, objectUrl)
      return objectUrl
    } finally {
      inflight.delete(key)
    }
  })()

  inflight.set(key, job)
  return job
}

export function peekCachedOriginal(url: string): string | null {
  return memory.get(url.trim()) || null
}
