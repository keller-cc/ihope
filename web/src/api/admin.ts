const ADMIN_TOKEN_KEY = 'ihope_web_admin_token'

export function getAdminToken(): string | null {
  return sessionStorage.getItem(ADMIN_TOKEN_KEY)
}

export function setAdminToken(token: string | null) {
  if (token) sessionStorage.setItem(ADMIN_TOKEN_KEY, token)
  else sessionStorage.removeItem(ADMIN_TOKEN_KEY)
}

/** 合并进行中的相同 GET（含管理端）。 */
const inflightAdminGets = new Map<string, Promise<unknown>>()

async function adminRequest<T>(path: string, init: RequestInit = {}): Promise<T> {
  const method = (init.method || 'GET').toUpperCase()
  const dedupe = method === 'GET' && init.body == null
  if (dedupe) {
    const hit = inflightAdminGets.get(path)
    if (hit) return hit as Promise<T>
  }

  const run = (async () => {
    const headers = new Headers(init.headers)
    if (!headers.has('Content-Type') && init.body) {
      headers.set('Content-Type', 'application/json')
    }
    const token = getAdminToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)
    const res = await fetch(path, { ...init, headers })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      const err = new Error((data as { error?: string }).error || res.statusText) as Error & {
        code?: string
      }
      err.code = (data as { error?: string }).error
      throw err
    }
    return data as T
  })()

  if (dedupe) {
    inflightAdminGets.set(path, run)
    void run.finally(() => {
      if (inflightAdminGets.get(path) === run) inflightAdminGets.delete(path)
    })
  }
  return run
}

export type AdminUser = {
  id: string
  email: string
  username: string
  hopeId?: string | null
  emailVerified: boolean
  createdAt: string
  qqBound?: boolean
  qqOpenId?: string | null
  fellowshipId?: string | null
  fellowshipCode?: string | null
  fellowshipName?: string | null
  domainId?: string | null
  domainName?: string | null
}

export type AdminDomain = {
  id: string
  name: string
  createdAt: string
  fellowshipCount: number
}

export type AdminFellowship = {
  id: string
  code: string
  name: string
  domainId: string
  domainName: string
  createdAt: string
  userCount: number
}

export type AdminConversation = {
  id: string
  type: string
  title: string
  memberCount: number
  createdAt: string
  members: string
}

export type AdminQQBinding = {
  userId: string
  username: string
  email: string
  hopeId?: string | null
  qqOpenId: string
  doorbellEnabled: boolean
  boundAt: string
}

export const adminApi = {
  listUsers: () => adminRequest<{ users: AdminUser[] }>('/api/admin/users'),
  deleteUser: (id: string) =>
    adminRequest<{ message: string }>(`/api/admin/users/${id}`, { method: 'DELETE' }),
  setUserFellowship: (id: string, fellowshipId: string) =>
    adminRequest<{ message: string }>(`/api/admin/users/${id}`, {
      method: 'PATCH',
      body: JSON.stringify({ fellowshipId }),
    }),
  listConversations: () =>
    adminRequest<{ conversations: AdminConversation[] }>('/api/admin/conversations'),
  deleteConversation: (id: string) =>
    adminRequest<{ message: string }>(`/api/admin/conversations/${id}`, {
      method: 'DELETE',
    }),
  listQQBindings: () =>
    adminRequest<{
      botEnabled: boolean
      bindings: AdminQQBinding[]
      botAddHint?: string
    }>('/api/admin/qq-bindings'),
  createQQBindCode: (userId: string) =>
    adminRequest<{ code: string; expiresAt: string; botAddHint: string }>(
      `/api/admin/users/${userId}/qq-bind-code`,
      { method: 'POST' },
    ),
  unbindQQ: (userId: string) =>
    adminRequest<{ message: string }>(`/api/admin/users/${userId}/qq-bot`, {
      method: 'DELETE',
    }),
  listDomains: () => adminRequest<{ domains: AdminDomain[] }>('/api/admin/domains'),
  createDomain: (name: string) =>
    adminRequest<AdminDomain>('/api/admin/domains', {
      method: 'POST',
      body: JSON.stringify({ name }),
    }),
  updateDomain: (id: string, name: string) =>
    adminRequest<AdminDomain>(`/api/admin/domains/${id}`, {
      method: 'PATCH',
      body: JSON.stringify({ name }),
    }),
  deleteDomain: (id: string) =>
    adminRequest<{ message: string }>(`/api/admin/domains/${id}`, { method: 'DELETE' }),
  listFellowships: () =>
    adminRequest<{ fellowships: AdminFellowship[] }>('/api/admin/fellowships'),
  createFellowship: (payload: { code: string; name: string; domainId: string }) =>
    adminRequest<AdminFellowship>('/api/admin/fellowships', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
  updateFellowship: (
    id: string,
    payload: { code: string; name: string; domainId: string },
  ) =>
    adminRequest<AdminFellowship>(`/api/admin/fellowships/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(payload),
    }),
  deleteFellowship: (id: string) =>
    adminRequest<{ message: string }>(`/api/admin/fellowships/${id}`, {
      method: 'DELETE',
    }),
}
