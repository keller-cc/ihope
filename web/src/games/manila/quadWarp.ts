/**
 * Perspective helpers — map a unit rectangle onto an anchors/boardConfig quad
 * so ships / badges / market panel follow isometric bend.
 */

export type PctPos = { x: number; y: number }
export type QuadPct = [[number, number], [number, number], [number, number], [number, number]]

export type PctBox = { x: number; y: number; w: number; h: number }

export function quadBBox(quad: QuadPct): PctBox {
  const xs = quad.map((p) => p[0])
  const ys = quad.map((p) => p[1])
  const minX = Math.min(...xs)
  const maxX = Math.max(...xs)
  const minY = Math.min(...ys)
  const maxY = Math.max(...ys)
  return { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
}

/** Solve Ax=b (8 unknowns) for perspective map from src→dst 4-corners. */
function solvePerspective(
  src: [number, number][],
  dst: [number, number][],
): number[] {
  const A: number[][] = []
  const b: number[] = []
  for (let i = 0; i < 4; i++) {
    const [x, y] = src[i]
    const [u, v] = dst[i]
    A.push([x, y, 1, 0, 0, 0, -x * u, -y * u])
    b.push(u)
    A.push([0, 0, 0, x, y, 1, -x * v, -y * v])
    b.push(v)
  }
  // Gaussian elimination
  const n = 8
  const M = A.map((row, i) => [...row, b[i]])
  for (let col = 0; col < n; col++) {
    let piv = col
    for (let r = col + 1; r < n; r++) {
      if (Math.abs(M[r][col]) > Math.abs(M[piv][col])) piv = r
    }
    ;[M[col], M[piv]] = [M[piv], M[col]]
    const div = M[col][col] || 1e-12
    for (let c = col; c <= n; c++) M[col][c] /= div
    for (let r = 0; r < n; r++) {
      if (r === col) continue
      const f = M[r][col]
      for (let c = col; c <= n; c++) M[r][c] -= f * M[col][c]
    }
  }
  return M.map((row) => row[n])
}

/**
 * CSS matrix3d that maps the element's local box (0..w × 0..h)
 * onto `quad` expressed in the same local coordinate space
 * (quad already converted relative to bbox origin, in px or %).
 *
 * Use with a wrapper sized to quadBBox; transform-origin: 0 0.
 */
export function matrix3dForQuad(quadLocal: [number, number][], w: number, h: number): string {
  const src: [number, number][] = [
    [0, 0],
    [w, 0],
    [w, h],
    [0, h],
  ]
  const h8 = solvePerspective(src, quadLocal as [number, number][])
  // CSS matrix3d is column-major 4×4
  const [a, b, c, d, e, f, g, hh] = h8
  const m = [
    a, d, 0, g,
    b, e, 0, hh,
    0, 0, 1, 0,
    c, f, 0, 1,
  ]
  return `matrix3d(${m.map((v) => Number(v.toFixed(6))).join(',')})`
}

/** Berth ship style: absolute box + perspective warp onto quad.
 * Pass board size in CSS px so matrix maps element pixels correctly under zoom. */
export function berthShipStyle(
  quad: QuadPct,
  boardW = 0,
  boardH = 0,
): {
  left: string
  top: string
  width: string
  height: string
  transform: string
  transformOrigin: string
} {
  const box = quadBBox(quad)
  if (boardW < 2 || boardH < 2) {
    return {
      left: `${box.x}%`,
      top: `${box.y}%`,
      width: `${box.w}%`,
      height: `${box.h}%`,
      transform: 'none',
      transformOrigin: '0 0',
    }
  }
  const pxW = (box.w / 100) * boardW
  const pxH = (box.h / 100) * boardH
  const local: [number, number][] = quad.map(
    ([x, y]) =>
      [((x - box.x) / 100) * boardW, ((y - box.y) / 100) * boardH] as [number, number],
  )
  return {
    left: `${box.x}%`,
    top: `${box.y}%`,
    width: `${box.w}%`,
    height: `${box.h}%`,
    transform: matrix3dForQuad(local, pxW, pxH),
    transformOrigin: '0 0',
  }
}

/** Translate a pad quad by board % — used for pay badges (same plane as cost). */
export function shiftQuad(quad: QuadPct, dxPct: number, dyPct: number): QuadPct {
  return quad.map(([x, y]) => [x + dxPct, y + dyPct]) as QuadPct
}

/** Cover berth: fixed ship size everywhere; only position + heading change. */
export function coverBerthStyle(
  quad: QuadPct,
  orient: 'port' | 'yard' | 'sea',
  rotDeg?: number,
): {
  left: string
  top: string
  transform: string
  transformOrigin: string
  ['--ship-rot']?: string
} {
  const box = quadBBox(quad)
  const cx = box.x + box.w / 2
  const cy = box.y + box.h / 2
  const fallback = orient === 'port' ? -82 : orient === 'yard' ? 28 : 4
  const rot = rotDeg ?? fallback
  return {
    left: `${cx}%`,
    top: `${cy}%`,
    transform: `translate(-50%, -50%) rotate(${rot}deg)`,
    transformOrigin: 'center center',
    ['--ship-rot']: `${rot}deg`,
  }
}

/** Cost-pad spot: same perspective box so badge sits on the mat plane. */
export function padSpotStyle(
  quad: QuadPct,
  boardW = 0,
  boardH = 0,
): {
  left: string
  top: string
  width: string
  height: string
  transform: string
  transformOrigin: string
} {
  return berthShipStyle(quad, boardW, boardH)
}
