/** Case- and whitespace-tolerant substring match (add-friend / list filters). */
export function fuzzyIncludes(haystack: string, needle: string): boolean {
  const h = haystack.replace(/\s+/g, '').toLowerCase()
  const n = needle.replace(/\s+/g, '').toLowerCase()
  if (!n) return true
  return h.includes(n)
}
