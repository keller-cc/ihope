export const JOIN_MODE_OPTIONS = [
  { value: 'anyone', label: '允许任何人加入', desc: '通过群号即可直接入群' },
  { value: 'verify', label: '需要验证信息', desc: '申请后需群主/管理员同意' },
  { value: 'deny', label: '不允许任何人加入', desc: '仅群主/管理员可邀请入群' },
] as const

export type JoinMode = (typeof JOIN_MODE_OPTIONS)[number]['value']

export function joinModeLabel(mode?: string): string {
  return JOIN_MODE_OPTIONS.find((o) => o.value === mode)?.label || '需要验证信息'
}

/** Resolve join policy; prefer joinMode, never map deny→anyone via legacy flag. */
export function resolveJoinMode(group: {
  joinMode?: string | null
  inviteRequiresApproval?: boolean
}): JoinMode {
  if (group.joinMode === 'anyone' || group.joinMode === 'verify' || group.joinMode === 'deny') {
    return group.joinMode
  }
  // Legacy-only: true means verify. false is ambiguous (anyone vs deny vs unset) → verify.
  if (group.inviteRequiresApproval === true) return 'verify'
  return 'verify'
}
