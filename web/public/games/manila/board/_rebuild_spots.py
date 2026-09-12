"""
Align region spots on straight lines, fix pay sides, pilots, pirates, insurance;
compose without ship perspective (rotate+cover berths only).
"""
from __future__ import annotations

import json
import math
import subprocess
import sys
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(r"d:\IHope\web\public\games\manila")
BOARD = ROOT / "board"
PIECES = ROOT / "pieces"
ASSETS = Path(r"C:\Users\micro\.cursor\projects\d-IHope\assets")
SRC = Path(r"d:\IHope\web\src\games\manila")
SIZE = 1024

REGION_PAD = {
    "port": {"w": 5.0, "h": 3.0, "top_scale": 0.88, "shear": 0.06},
    "yard": {"w": 4.8, "h": 4.6, "skew": 0.08, "top_scale": 0.94, "slant": True},
    "shore": {"w": 4.8, "h": 4.4, "top_scale": 0.92, "shear": 0.03},
    "pirate": {"w": 3.4, "h": 2.6, "top_scale": 0.95, "shear": 0.0},
}
REGION_BERTH = {
    # edge_drop: right side lower — matches painted glass cascade 走势
    "berth_port": {"top_scale": 0.9, "kind": "h_berth", "edge_drop": 0.10},
    "berth_yard": {"skew": 0.18, "top_scale": 0.92, "kind": "yard_slant"},
}

# Ship hull size (uniform length; width optionally slimmed). Overlays use fixed px.
SHIP_ROT_DEG = {"port": -82, "yard": 28, "sea": 4}
SHIP_FIXED_LEN_PX = 168
SHIP_WIDTH_FRAC = 0.78  # slimmer than natural hull aspect
# Deck chrome — fixed board px so meeple/cargo/cost don't shrink with hull
SHIP_MEEPLE_H_PX = 42
SHIP_BADGE_D_PX = 30
SHIP_CARGO_PX = 36
SHIP_PROFIT_H_PX = 24
# Flat stock panel — fill BR under insurance (insurance pad bottom ≈81.3)
MARKET_PANEL_QUAD = [[62.0, 82.6], [100.0, 82.6], [100.0, 100.0], [62.0, 100.0]]
# A·B·C same size on every berth (px @1024)
BERTH_LETTER_PX = 46
# Insurance: square pad (no landscape squash / fake perspective)
INSURANCE_PAD_SIZE = 3.2
# Port ships only — slight vertical spread; cost pads stay on painted mats
PORT_BERTH_Y = {"port_C": 12.6, "port_B": 18.5, "port_A": 24.4}
WARE_PROFIT = {"nutmeg": 24, "silk": 18, "ginseng": 30, "jade": 36}

SPOT_RULES = {
    "port_C": {"region": "port", "cost": 2, "payout": 15},
    "port_B": {"region": "port", "cost": 3, "payout": 8},
    "port_A": {"region": "port", "cost": 4, "payout": 6},
    "yard_A": {"region": "yard", "cost": 4, "payout": 6},
    "yard_B": {"region": "yard", "cost": 3, "payout": 8},
    "yard_C": {"region": "yard", "cost": 2, "payout": 15},
    "pilot_small": {"region": "shore", "cost": 2, "payout": 0},
    "pilot_large": {"region": "shore", "cost": 5, "payout": 0},
    "insurance": {"region": "shore", "cost": 0, "payout": 10},
    "pirate_0": {"region": "pirate", "cost": 5, "payout": 0},
    "pirate_1": {"region": "pirate", "cost": 5, "payout": 0},
    "pirate_2": {"region": "pirate", "cost": 5, "payout": 0},
}


def key_bg(im: Image.Image) -> Image.Image:
    a = np.array(im.convert("RGBA"))
    h, w = a.shape[:2]
    rgb = a[:, :, :3].astype(np.int16)
    lum = rgb.mean(2)
    chroma = rgb.max(2) - rgb.min(2)
    corners = [lum[0, 0], lum[0, -1], lum[-1, 0], lum[-1, -1]]
    mode = "white" if sum(corners) / 4 > 200 else "black"
    bg_seed = (lum >= 235) & (chroma <= 25) if mode == "white" else (lum <= 28) & (chroma <= 22)
    bg = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg_seed[y, x]:
                bg[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bg_seed[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and bg_seed[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                q.append((ny, nx))
    a[:, :, 3] = np.where(bg, 0, 255).astype(np.uint8)
    out = Image.fromarray(a)
    bbox = out.getbbox()
    return out.crop(bbox) if bbox else out


def clean_meeple(im: Image.Image) -> Image.Image:
    """Key black bg + strip white/gray glow fringe that shows as blank on board."""
    a = np.array(im.convert("RGBA"))
    h, w = a.shape[:2]
    rgb = a[:, :, :3].astype(np.float32)
    al = a[:, :, 3].astype(np.float32)
    lum = rgb.mean(2)
    chroma = rgb.max(2) - rgb.min(2)

    def dilate(mask: np.ndarray, n: int = 1) -> np.ndarray:
        m = mask.copy()
        for _ in range(n):
            p = np.pad(m, 1, constant_values=False)
            m = m | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
        return m

    bg_seed = ((lum <= 42) & (chroma <= 32)) | (al < 10)
    bg = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg_seed[y, x]:
                bg[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bg_seed[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and bg_seed[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                q.append((ny, nx))
    fringe = (lum >= 145) & (chroma <= 60) & (np.min(rgb, 2) >= 120)
    fringe = dilate(fringe, 2)
    edge = dilate(a[:, :, 3] < 16, 2) & (a[:, :, 3] > 0) & (lum >= 130) & (chroma <= 70)
    kill = bg | fringe | edge
    a[:, :, 3] = np.where(kill, 0, a[:, :, 3]).astype(np.uint8)
    a[a[:, :, 3] == 0, :3] = 0
    out = Image.fromarray(a)
    bbox = out.getbbox()
    if not bbox:
        return out
    x0, y0, x1, y1 = bbox
    return out.crop((max(0, x0 - 1), max(0, y0 - 1), min(w, x1 + 1), min(h, y1 + 1)))


def comps(mask, min_area, min_w, min_h, max_asp=99):
    H, W = mask.shape
    vis = np.zeros_like(mask)
    out = []
    for y in range(H):
        for x in range(W):
            if not mask[y, x] or vis[y, x]:
                continue
            q = deque([(y, x)])
            vis[y, x] = True
            cells = []
            while q:
                cy, cx = q.popleft()
                cells.append((cy, cx))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not vis[ny, nx]:
                        vis[ny, nx] = True
                        q.append((ny, nx))
            if len(cells) < min_area:
                continue
            ys = [c[0] for c in cells]
            xs = [c[1] for c in cells]
            y0, y1, x0, x1 = min(ys), max(ys), min(xs), max(xs)
            bw, bh = x1 - x0 + 1, y1 - y0 + 1
            asp = max(bw, bh) / max(1, min(bw, bh))
            if bw < min_w or bh < min_h or asp > max_asp:
                continue
            out.append(
                {
                    "cx": (x0 + x1) / 2 / W * 100,
                    "cy": (y0 + y1) / 2 / H * 100,
                    "bw": bw,
                    "bh": bh,
                    "box": [x0, y0, x1, y1],
                    "asp": asp,
                }
            )
    return sorted(out, key=lambda c: (c["cy"], c["cx"]))


def colinearize(pts: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Snap points onto best-fit line, keep order by projection, equal-ish spacing preserved by projection."""
    if len(pts) < 2:
        return pts
    xs = np.array([p[0] for p in pts], float)
    ys = np.array([p[1] for p in pts], float)
    # PCA direction
    mx, my = xs.mean(), ys.mean()
    X = np.column_stack([xs - mx, ys - my])
    _, _, vt = np.linalg.svd(X, full_matrices=False)
    d = vt[0]
    t = X @ d
    out = []
    for ti in t:
        out.append((round(float(mx + ti * d[0]), 2), round(float(my + ti * d[1]), 2)))
    return out


def quad_at_center(cx: float, cy: float, plane: dict) -> list[list[float]]:
    hw, hh = plane["w"] / 2, plane["h"] / 2
    if plane.get("slant"):
        skew = plane["w"] * plane.get("skew", 0.12)
        tl = (cx - hw + skew * 0.5, cy - hh)
        tr = (cx + hw + skew * 0.2, cy - hh + plane["h"] * 0.02)
        br = (cx + hw - skew * 0.1, cy + hh)
        bl = (cx - hw - skew * 0.35, cy + hh - plane["h"] * 0.02)
    else:
        top_scale = plane.get("top_scale", 0.9)
        shear = plane["h"] * plane.get("shear", 0.05)
        tl = (cx - hw * top_scale + shear, cy - hh)
        tr = (cx + hw * top_scale + shear, cy - hh)
        br = (cx + hw - shear * 0.25, cy + hh)
        bl = (cx - hw - shear * 0.25, cy + hh)
    return [[round(p[0], 2), round(p[1], 2)] for p in (tl, tr, br, bl)]


def quad_from_detected_box(box, inset: float = 0.12) -> list[list[float]]:
    """Axis-aligned inset quad from detected pad box (stable for shore/insurance)."""
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0
    x0i, x1i = x0 + bw * inset, x1 - bw * inset
    y0i, y1i = y0 + bh * inset, y1 - bh * inset

    def pct(x, y):
        return [round(x / SIZE * 100, 2), round(y / SIZE * 100, 2)]

    return [pct(x0i, y0i), pct(x1i, y0i), pct(x1i, y1i), pct(x0i, y1i)]


def quad_from_box(box, plane: dict) -> list[list[float]]:
    x0, y0, x1, y1 = box
    inset = 0.06
    bw, bh = x1 - x0, y1 - y0
    x0i, x1i = x0 + bw * inset, x1 - bw * inset
    y0i, y1i = y0 + bh * inset, y1 - bh * inset
    kind = plane.get("kind", "h_berth")
    if kind == "yard_slant":
        skew = bw * plane.get("skew", 0.10)
        tl = (x0i + skew, y0i)
        tr = (x1i + skew * 0.35, y0i + bh * 0.02)
        br = (x1i - skew * 0.15, y1i)
        bl = (x0i - skew * 0.45, y1i - bh * 0.02)
    else:
        mid = (x0i + x1i) / 2
        half_bot = (x1i - x0i) / 2
        half_top = half_bot * plane.get("top_scale", 0.94)
        # Right side drops to follow painted glass / pier 走势
        drop = bw * plane.get("edge_drop", 0.0)
        tl = (mid - half_top, y0i)
        tr = (mid + half_top, y0i + drop)
        br = (mid + half_bot, y1i + drop)
        bl = (mid - half_bot, y1i)

    def pct(p):
        return [round(p[0] / SIZE * 100, 2), round(p[1] / SIZE * 100, 2)]

    return [pct(tl), pct(tr), pct(br), pct(bl)]


def square_quad_at(cx: float, cy: float, size: float) -> list[list[float]]:
    h = size / 2
    return [
        [round(cx - h, 2), round(cy - h, 2)],
        [round(cx + h, 2), round(cy - h, 2)],
        [round(cx + h, 2), round(cy + h, 2)],
        [round(cx - h, 2), round(cy + h, 2)],
    ]


def paste_badge_centered(canvas: Image.Image, badge: Image.Image, cx: float, cy: float, diam: int):
    """Place circular badge without perspective warp (insurance etc.)."""
    sp = badge.resize((diam, diam), Image.Resampling.LANCZOS)
    px = int(cx / 100 * SIZE - diam / 2)
    py = int(cy / 100 * SIZE - diam / 2)
    canvas.alpha_composite(sp, (px, py))


def nearest(pool, ex, ey, used):
    best, bd, bi = None, 1e9, -1
    for i, c in enumerate(pool):
        if i in used:
            continue
        d = (c["cx"] - ex) ** 2 + (c["cy"] - ey) ** 2
        if d < bd:
            bd, best, bi = d, c, i
    used.add(bi)
    return best


def find_coeffs(src, dst):
    matrix = []
    for s, d in zip(src, dst):
        matrix.append([d[0], d[1], 1, 0, 0, 0, -s[0] * d[0], -s[0] * d[1]])
        matrix.append([0, 0, 0, d[0], d[1], 1, -s[1] * d[0], -s[1] * d[1]])
    A = np.array(matrix, float)
    B = np.array([v for pair in src for v in pair], float)
    return np.linalg.lstsq(A, B, rcond=None)[0].tolist()


def font(size: int):
    for name in (
        "C:/Windows/Fonts/georgiab.ttf",
        "C:/Windows/Fonts/georgia.ttf",
        "C:/Windows/Fonts/cambriab.ttf",
    ):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def market_num_font(size: int):
    """Narrower face for stock values (Georgia reads too wide at small sizes)."""
    for name in (
        "C:/Windows/Fonts/seguisb.ttf",  # Segoe UI Semibold
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return font(size)


def make_badge(art: Image.Image, text: str, diam: int, fill) -> Image.Image:
    sp = art.copy().resize((diam, diam), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(sp)
    f = font(max(40, diam // 2))
    try:
        draw.text(
            (diam / 2 + 1.2, diam / 2 + 1.2),
            text,
            font=f,
            fill=(30, 12, 4, 140),
            anchor="mm",
        )
        draw.text((diam / 2, diam / 2), text, font=f, fill=fill, anchor="mm")
    except TypeError:
        bbox = draw.textbbox((0, 0), text, font=f)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        cx, cy = (diam - tw) / 2 - bbox[0], (diam - th) / 2 - bbox[1]
        draw.text((cx + 1.5, cy + 1.5), text, font=f, fill=(30, 12, 4, 140))
        draw.text((cx, cy), text, font=f, fill=fill)
    return sp


def draw_berth_letters(canvas: Image.Image, berths: dict) -> None:
    """Paint A·B·C on port/yard water slips — same size everywhere."""
    draw = ImageDraw.Draw(canvas)
    letter_for = {
        "port_C": "C",
        "port_B": "B",
        "port_A": "A",
        "yard_A": "A",
        "yard_B": "B",
        "yard_C": "C",
    }
    f = font(BERTH_LETTER_PX)
    for sid, letter in letter_for.items():
        b = berths.get(sid)
        if not b:
            continue
        cx = b["center"]["x"] / 100 * SIZE
        cy = b["center"]["y"] / 100 * SIZE
        for ox, oy in ((-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (1, 1)):
            draw.text((cx + ox, cy + oy), letter, font=f, fill=(28, 48, 56, 160), anchor="mm")
        draw.text((cx, cy), letter, font=f, fill=(248, 244, 230, 230), anchor="mm")


def paste_on_quad(canvas: Image.Image, badge: Image.Image, quad_pct):
    dst = [(q[0] / 100 * SIZE, q[1] / 100 * SIZE) for q in quad_pct]
    xs, ys = [p[0] for p in dst], [p[1] for p in dst]
    minx, maxx = max(0, int(min(xs)) - 2), min(SIZE, int(max(xs)) + 3)
    miny, maxy = max(0, int(min(ys)) - 2), min(SIZE, int(max(ys)) + 3)
    bw, bh = maxx - minx, maxy - miny
    if bw < 4 or bh < 4:
        return
    local = [(x - minx, y - miny) for x, y in dst]
    src = [(0, 0), (badge.size[0], 0), (badge.size[0], badge.size[1]), (0, badge.size[1])]
    coeffs = find_coeffs(src, local)
    warped = badge.transform((bw, bh), Image.Transform.PERSPECTIVE, coeffs, Image.Resampling.BICUBIC)
    canvas.alpha_composite(warped, (minx, miny))


def paste_meeple(canvas: Image.Image, art: Image.Image, x_pct: float, y_pct: float, h_px: int):
    """Place meeple so its opaque content center sits on (x_pct, y_pct)."""
    sp = art.convert("RGBA")
    bb = sp.getbbox()
    if bb:
        sp = sp.crop(bb)
    nw = max(1, int(round(sp.size[0] * (h_px / max(1, sp.size[1])))))
    sp = sp.resize((nw, h_px), Image.Resampling.LANCZOS)
    arr = np.array(sp)
    ys, xs = np.where(arr[:, :, 3] > 40)
    if len(xs):
        ocx = float(xs.mean())
        ocy = float(ys.mean())
    else:
        ocx, ocy = nw / 2.0, h_px / 2.0
    cx = int(SIZE * x_pct / 100)
    cy = int(SIZE * y_pct / 100)
    canvas.alpha_composite(sp, (int(round(cx - ocx)), int(round(cy - ocy))))


def meeple_resized_centered(art: Image.Image, h_px: int) -> tuple[Image.Image, float, float]:
    """Resize meeple; return (sprite, opaque_cx, opaque_cy) in sprite pixels."""
    sp = art.convert("RGBA")
    bb = sp.getbbox()
    if bb:
        sp = sp.crop(bb)
    nw = max(1, int(round(sp.size[0] * (h_px / max(1, sp.size[1])))))
    sp = sp.resize((nw, h_px), Image.Resampling.LANCZOS)
    arr = np.array(sp)
    ys, xs = np.where(arr[:, :, 3] > 40)
    if len(xs):
        return sp, float(xs.mean()), float(ys.mean())
    return sp, nw / 2.0, h_px / 2.0


def paste_flat_rect(canvas: Image.Image, art: Image.Image, quad_pct) -> None:
    """Axis-aligned opaque paste into the quad's bounding box."""
    xs = [p[0] for p in quad_pct]
    ys = [p[1] for p in quad_pct]
    x0 = int(min(xs) / 100 * SIZE)
    y0 = int(min(ys) / 100 * SIZE)
    x1 = int(max(xs) / 100 * SIZE)
    y1 = int(max(ys) / 100 * SIZE)
    w, h = max(4, x1 - x0), max(4, y1 - y0)
    # Solid fill first so nothing from the board shows through
    ImageDraw.Draw(canvas).rectangle([x0, y0, x1 - 1, y1 - 1], fill=(72, 44, 24, 255))
    resized = art.convert("RGBA").resize((w, h), Image.Resampling.LANCZOS)
    canvas.alpha_composite(resized, (x0, y0))


def paste_cover_berth(
    canvas: Image.Image,
    sprite: Image.Image,
    box_px,
    orient: str,
    fixed_len_px: int = SHIP_FIXED_LEN_PX,
    fixed_w_px: int | None = None,
):
    """Place ship token at berth center with rotation only (sprite already sized)."""
    x0, y0, x1, y1 = box_px
    bb = sprite.getbbox() or (0, 0, sprite.size[0], sprite.size[1])
    ship = sprite.crop(bb)
    # If caller passed raw hull, scale length; bake_ship already sizes fully
    if abs(ship.size[1] - fixed_len_px) > 8:
        scale = fixed_len_px / max(1, ship.size[1])
        tw = max(8, int(round(ship.size[0] * scale * SHIP_WIDTH_FRAC)))
        th = max(8, int(round(ship.size[1] * scale)))
        ship = ship.resize((tw, th), Image.Resampling.LANCZOS)
    css_deg = SHIP_ROT_DEG.get(orient, 0)
    if css_deg:
        ship = ship.rotate(-css_deg, expand=True, resample=Image.Resampling.BICUBIC)
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2
    canvas.alpha_composite(ship, (cx - ship.size[0] // 2, cy - ship.size[1] // 2))


def fit_contain(im: Image.Image, box: int) -> Image.Image:
    """Uniform scale into a box×box envelope (no stretch)."""
    sp = im.convert("RGBA")
    bb = sp.getbbox()
    if bb:
        sp = sp.crop(bb)
    cw, ch = sp.size
    s = box / max(1, max(cw, ch))
    nw = max(1, int(round(cw * s)))
    nh = max(1, int(round(ch * s)))
    return sp.resize((nw, nh), Image.Resampling.LANCZOS)


def shift_box_cy(box, new_cy_pct: float) -> list[int]:
    """Keep box size; move so center Y = new_cy_pct."""
    x0, y0, x1, y1 = box
    h = y1 - y0
    ncy = int(new_cy_pct / 100 * SIZE)
    ny0 = max(0, ncy - h // 2)
    ny1 = min(SIZE, ny0 + h)
    return [x0, ny0, x1, ny1]


def pay_offset(region: str, sid: str) -> tuple[float, float]:
    """Return (dx, dy) in % for pay badge relative to cost center."""
    if region == "port":
        return (-4.4, 0.0)
    if region == "yard":
        return (1.6, -5.0)  # further upper-left from prior up-right
    if sid == "insurance":
        return (0.0, 0.0)
    return (3.5, 0.0)


def build_anchors():
    im = Image.open(BOARD / "board.jpg").convert("RGB").resize((SIZE, SIZE))
    a = np.array(im)
    r, g, b = [a[:, :, i].astype(int) for i in range(3)]
    lum = (r + g + b) / 3
    chroma = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    white = (lum > 160) & (chroma < 45) & (b > 140)
    frost = (lum > 155) & (chroma < 55) & (b > 140)
    cyan = (b > r + 12) & (b > g - 12) & (lum > 115) & (lum < 215) & (g > 95)
    squares = comps(white, 150, 14, 14, max_asp=3.0)

    # Port pads (left of harbor) — detect then colinearize
    port_raw = []
    used: set[int] = set()
    for sid, ex, ey in [("port_C", 28.1, 13.5), ("port_B", 25.6, 17.7), ("port_A", 23.7, 23.0)]:
        c = nearest(squares, ex, ey, used)
        port_raw.append((sid, c))
    port_line = colinearize([(c["cx"], c["cy"]) for _, c in port_raw])

    # Yard pads — detect then colinearize
    yard_raw = []
    for sid, ex, ey in [("yard_A", 79.0, 31.9), ("yard_B", 79.9, 45.5), ("yard_C", 80.2, 60.9)]:
        c = nearest(squares, ex, ey, used)
        yard_raw.append((sid, c))
    yard_line = colinearize([(c["cx"], c["cy"]) for _, c in yard_raw])

    cost_pads = {}
    for (sid, c), (cx, cy) in zip(port_raw, port_line):
        rules = SPOT_RULES[sid]
        plane = REGION_PAD["port"]
        # Cost/pay stay on painted pads (do not shift with ship berth spacing)
        cost_pads[sid] = {
            "id": sid,
            "region": "port",
            "center": {"x": round(cx, 2), "y": round(cy, 2)},
            "box_px": c["box"],
            "quad_pct": quad_at_center(cx, cy, plane),
            "plane": plane,
            "cost": rules["cost"],
            "payout": rules["payout"],
            "pay_beside": "left",
            "pay_offset_pct": list(pay_offset("port", sid)),
        }
    for (sid, c), (cx, cy) in zip(yard_raw, yard_line):
        rules = SPOT_RULES[sid]
        plane = REGION_PAD["yard"]
        cost_pads[sid] = {
            "id": sid,
            "region": "yard",
            "center": {"x": cx, "y": cy},
            "box_px": c["box"],
            "quad_pct": quad_at_center(cx, cy, plane),
            "plane": plane,
            "cost": rules["cost"],
            "payout": rules["payout"],
            "pay_beside": "up-right",
            "pay_offset_pct": list(pay_offset("yard", sid)),
        }

    # Pilots: cost5 (large) stays; cost2 moves to pier pad ~66.6 (not glass ~50)
    pilot_large = nearest(squares, 22.1, 74.1, used)
    pilot_small = nearest(squares, 23.8, 66.6, used)
    for sid, c in [("pilot_small", pilot_small), ("pilot_large", pilot_large)]:
        rules = SPOT_RULES[sid]
        plane = REGION_PAD["shore"]
        cx, cy = round(c["cx"], 2), round(c["cy"], 2)
        cost_pads[sid] = {
            "id": sid,
            "region": "shore",
            "center": {"x": cx, "y": cy},
            "box_px": c["box"],
            "quad_pct": quad_from_detected_box(c["box"]),
            "plane": plane,
            "cost": rules["cost"],
            "payout": 0,
            "pay_beside": "none",
            "pay_offset_pct": [0, 0],
        }

    # Insurance: square pad under gazebo — no landscape squash (透视过头)
    ins = nearest(squares, 77.9, 79.7, used)
    plane = {"w": INSURANCE_PAD_SIZE, "h": INSURANCE_PAD_SIZE, "top_scale": 1.0, "shear": 0.0}
    cx, cy = round(ins["cx"], 2), round(ins["cy"], 2)
    cost_pads["insurance"] = {
        "id": "insurance",
        "region": "shore",
        "center": {"x": cx, "y": cy},
        "box_px": ins["box"],
        "quad_pct": square_quad_at(cx, cy, INSURANCE_PAD_SIZE),
        "plane": plane,
        "cost": 0,
        "payout": 10,
        "pay_beside": "on",
        "pay_offset_pct": [0, 0],
        "paste_mode": "centered",
    }

    # Pirate seats: on painted deck pads (auto-detected gray pad centers)
    for pid, x, y in [("pirate_0", 35.3, 43.4), ("pirate_1", 31.5, 43.1), ("pirate_2", 27.8, 42.8)]:
        plane = REGION_PAD["pirate"]
        cost_pads[pid] = {
            "id": pid,
            "region": "pirate",
            "center": {"x": x, "y": y},
            "quad_pct": quad_at_center(x, y, plane),
            "plane": plane,
            "cost": 5,
            "payout": 0,
            "pay_beside": "none",
            "pay_offset_pct": [0, 0],
        }

    # Berths
    band = frost.copy()
    band[: int(0.05 * SIZE), :] = False
    band[int(0.30 * SIZE) :, :] = False
    band[:, : int(0.30 * SIZE)] = False
    band[:, int(0.72 * SIZE) :] = False
    top_frost = comps(band, 180, 60, 14, max_asp=8)
    top_bits = [c for c in top_frost if c["cy"] < 15.5]
    mid = [c for c in top_frost if 15.5 <= c["cy"] < 21]
    bot = [c for c in top_frost if 21 <= c["cy"] < 28]

    def merge_boxes(items):
        if not items:
            return None
        x0 = min(c["box"][0] for c in items)
        y0 = min(c["box"][1] for c in items)
        x1 = max(c["box"][2] for c in items)
        y1 = max(c["box"][3] for c in items)
        return {
            "cx": (x0 + x1) / 2 / SIZE * 100,
            "cy": (y0 + y1) / 2 / SIZE * 100,
            "box": [x0, y0, x1, y1],
        }

    port_C = merge_boxes(top_bits) or nearest(comps(frost, 400, 80, 18, 8), 46.0, 13.0, set())
    port_B = merge_boxes(mid) or nearest(comps(frost, 400, 80, 18, 8), 45.7, 18.2, set())
    port_A = merge_boxes(bot) or nearest(comps(frost, 400, 80, 18, 8), 44.9, 23.5, set())

    yard_slips = [
        c for c in comps(cyan | frost, 800, 55, 70, max_asp=2.2) if 68 < c["cx"] < 78 and 24 < c["cy"] < 65
    ]
    used_y: set[int] = set()
    yard_A = nearest(yard_slips or comps(cyan, 800, 50, 60, 2.5), 73.0, 27.7, used_y)
    yard_B = nearest(yard_slips or comps(cyan, 800, 50, 60, 2.5), 73.7, 41.2, used_y)
    yard_C = nearest(yard_slips or comps(cyan, 800, 50, 60, 2.5), 74.4, 55.1, used_y)

    # Start lane pads (bottom) — for covering with ships at start
    start_pads = [
        c for c in comps(frost | white, 600, 40, 80, max_asp=6) if 30 < c["cx"] < 65 and c["cy"] > 75
    ]
    start_pads = sorted(start_pads, key=lambda c: c["cx"])[:3]

    berths = {}
    for sid, c, plane_key in [
        ("port_C", port_C, "berth_port"),
        ("port_B", port_B, "berth_port"),
        ("port_A", port_A, "berth_port"),
        ("yard_A", yard_A, "berth_yard"),
        ("yard_B", yard_B, "berth_yard"),
        ("yard_C", yard_C, "berth_yard"),
    ]:
        plane = REGION_BERTH[plane_key]
        box = c["box"]
        cx, cy = c["cx"], c["cy"]
        if sid in PORT_BERTH_Y:
            cy = PORT_BERTH_Y[sid]
            box = shift_box_cy(box, cy)
            cx = (box[0] + box[2]) / 2 / SIZE * 100
        berths[sid] = {
            "id": sid,
            "region": plane_key,
            "center": {"x": round(cx, 2), "y": round(cy, 2)},
            "box_px": box,
            "quad_pct": quad_from_box(box, plane),
            "plane": plane,
            "ship_orient": "port" if plane_key == "berth_port" else "yard",
            "ship_rot_deg": SHIP_ROT_DEG["port"] if plane_key == "berth_port" else SHIP_ROT_DEG["yard"],
        }
    for i, c in enumerate(start_pads):
        sid = f"start_{i}"
        berths[sid] = {
            "id": sid,
            "region": "berth_start",
            "center": {"x": round(c["cx"], 2), "y": round(c["cy"], 2)},
            "box_px": c["box"],
            "quad_pct": quad_from_box(c["box"], {"kind": "h_berth", "top_scale": 0.95}),
            "plane": {"kind": "start"},
            "ship_orient": "sea",
            "ship_rot_deg": SHIP_ROT_DEG["sea"],
        }

    doc = {
        "board": "board.jpg",
        "board_size_px": [SIZE, SIZE],
        "coord_space": "percent of full plate (0–100), origin top-left",
        "notes": {
            "port_pay": "left of cost",
            "yard_pay": "upper-right of cost",
            "pirate": "deck pads left-down along hull",
            "berth_letters": "A·B·C same size on water slips",
            "ships": "one size from start berths; rot only differs by berth",
            "insurance": "square centered badge — no perspective squash",
            "market": "flat panel over BR frost glass + area to its right",
        },
        "region_pad": REGION_PAD,
        "region_berth": REGION_BERTH,
        "cost_pads": cost_pads,
        "berths": berths,
        "market_panel_quad_pct": MARKET_PANEL_QUAD,
        "ship_seats": {
            "seat_x_pct": 50.0,
            "hull3_y_pct": [24.5, 41.0, 58.0],
            "hull4_y_pct": [23.5, 39.5, 55.5, 71.5],
            "badge_diameter_frac_of_hull_width": 0.58,
            "ware_costs": {
                "nutmeg": [3, 4, 5],
                "silk": [3, 4, 5],
                "ginseng": [2, 3, 4],
                "jade": [2, 3, 4, 5],
            },
            "fixed_len_px": SHIP_FIXED_LEN_PX,
            "width_frac": SHIP_WIDTH_FRAC,
            "meeple_h_px": SHIP_MEEPLE_H_PX,
            "badge_d_px": SHIP_BADGE_D_PX,
            "cargo_px": SHIP_CARGO_PX,
            "rot_deg": SHIP_ROT_DEG,
        },
    }
    text = json.dumps(doc, ensure_ascii=False, indent=2)
    (BOARD / "anchors.json").write_text(text, encoding="utf-8")
    (SRC / "anchors.json").write_text(text, encoding="utf-8")
    return doc


def main():
    cost_src = ASSETS / "manila-cost-orange-blank.png"
    pay_src = ASSETS / "manila-pay-yellow-blank.png"
    if not cost_src.exists():
        cost_src = ASSETS / "spot-badge-cost.png"
    if not pay_src.exists():
        pay_src = ASSETS / "spot-badge-pay.png"
    cost = key_bg(Image.open(cost_src))
    pay = key_bg(Image.open(pay_src))
    cost.save(PIECES / "spot-badge-cost.png")
    pay.save(PIECES / "spot-badge-pay.png")

    doc = build_anchors()
    canvas = Image.open(BOARD / "board.jpg").convert("RGBA").resize((SIZE, SIZE))
    cost_art = Image.open(PIECES / "spot-badge-cost.png").convert("RGBA")
    pay_art = Image.open(PIECES / "spot-badge-pay.png").convert("RGBA")
    hull3 = Image.open(BOARD / "hull-3.png").convert("RGBA")
    hull4 = Image.open(BOARD / "hull-4.png").convert("RGBA")

    # Letters under ships / cost badges — match physical board A·B·C slips
    draw_berth_letters(canvas, doc["berths"])

    for sid, pad in doc["cost_pads"].items():
        cval = pad.get("cost") or 0
        pval = pad.get("payout") or 0
        beside = pad.get("pay_beside", "none")
        centered = pad.get("paste_mode") == "centered"
        if cval > 0:
            badge = make_badge(cost_art, str(cval), 320, (45, 18, 6, 255))
            if centered:
                paste_badge_centered(canvas, badge, pad["center"]["x"], pad["center"]["y"], 56)
            else:
                paste_on_quad(canvas, badge, pad["quad_pct"])
        if pval > 0:
            badge = make_badge(pay_art, f"+{pval}", 300, (55, 30, 5, 255))
            if beside == "on" or centered:
                paste_badge_centered(canvas, badge, pad["center"]["x"], pad["center"]["y"], 56)
            else:
                dx, dy = pad.get("pay_offset_pct") or pay_offset(pad.get("region", ""), sid)
                q2 = [[p[0] + dx, p[1] + dy] for p in pad["quad_pct"]]
                paste_on_quad(canvas, badge, q2)

    ss = doc["ship_seats"]
    ware_costs = ss.get("ware_costs") or {
        "nutmeg": [3, 4, 5],
        "silk": [3, 4, 5],
        "ginseng": [2, 3, 4],
        "jade": [2, 3, 4, 5],
    }
    fixed_len = int(ss.get("fixed_len_px") or SHIP_FIXED_LEN_PX)
    ss["fixed_len_px"] = fixed_len
    ss["width_frac"] = SHIP_WIDTH_FRAC

    meeple_arts = {
        c: clean_meeple(Image.open(PIECES / f"meeple-{c}.png"))
        for c in ("red", "blue", "green", "yellow", "purple")
        if (PIECES / f"meeple-{c}.png").exists()
    }
    meeple_list = list(meeple_arts.values()) or []

    def bake_ship(hull, ware: str, ys, costs, occupied=(), orient: str = "sea"):
        """Hull sized first; meeple/cargo/cost use fixed px (not scaled with hull).
        Meeples are pre-counter-rotated so they stay upright after ship rotation."""
        bb = hull.getbbox() or (0, 0, hull.size[0], hull.size[1])
        cropped = hull.crop(bb)
        scale = fixed_len / max(1, cropped.size[1])
        th = fixed_len
        tw = max(8, int(round(cropped.size[0] * scale * SHIP_WIDTH_FRAC)))
        hull_s = cropped.resize((tw, th), Image.Resampling.LANCZOS)
        ship = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
        ship.alpha_composite(hull_s, (0, 0))
        draw = ImageDraw.Draw(ship)
        profit = WARE_PROFIT.get(ware, 0)
        css_deg = float(SHIP_ROT_DEG.get(orient, 0))
        # Fixed-size bow profit
        ph = SHIP_PROFIT_H_PX
        pw = max(ph + 8, int(tw * 0.9))
        px0, py0 = (tw - pw) // 2, max(1, int(th * 0.02))
        draw.rounded_rectangle(
            [px0, py0, px0 + pw, py0 + ph],
            radius=5,
            fill=(255, 210, 80, 255),
            outline=(122, 63, 12, 255),
            width=2,
        )
        draw.text(
            (tw // 2, py0 + ph // 2),
            f"+{profit}",
            font=font(max(14, ph - 6)),
            fill=(28, 10, 2, 255),
            anchor="mm",
        )
        # Fixed-size stern cargo (under seats)
        cargo_path = PIECES / f"share-{ware}.png"
        if cargo_path.exists():
            cargo_cy = 0.88 if len(ys) >= 4 else 0.795
            cargo = fit_contain(Image.open(cargo_path), SHIP_CARGO_PX)
            ship.alpha_composite(
                cargo,
                (tw // 2 - cargo.size[0] // 2, int(th * cargo_cy) - cargo.size[1] // 2),
            )
        diam = SHIP_BADGE_D_PX
        for i, (y_pct, cval) in enumerate(zip(ys, costs)):
            cx = int(tw * ss["seat_x_pct"] / 100)
            cy = int(th * y_pct / 100)
            if i in occupied and meeple_list:
                mp = meeple_list[i % len(meeple_list)]
                sp, ocx, ocy = meeple_resized_centered(mp, SHIP_MEEPLE_H_PX)
                if css_deg:
                    # Ship later: PIL.rotate(-css_deg). Pre-rotate meeple +css_deg → upright in world.
                    sp = sp.rotate(css_deg, expand=True, resample=Image.Resampling.BICUBIC)
                    arr = np.array(sp)
                    ys_a, xs_a = np.where(arr[:, :, 3] > 40)
                    if len(xs_a):
                        ocx, ocy = float(xs_a.mean()), float(ys_a.mean())
                    else:
                        ocx, ocy = sp.size[0] / 2.0, sp.size[1] / 2.0
                ship.alpha_composite(sp, (int(round(cx - ocx)), int(round(cy - ocy))))
            else:
                badge = make_badge(cost_art, str(cval), 280, (45, 18, 6, 255)).resize(
                    (diam, int(diam * 0.78)), Image.Resampling.LANCZOS
                )
                ship.alpha_composite(badge, (cx - badge.size[0] // 2, cy - badge.size[1] // 2))
        return ship

    def place_ship(hull_art, ware, ys, costs, berth_id, orient, occupied=()):
        paste_cover_berth(
            canvas,
            bake_ship(hull_art, ware, ys, costs, occupied, orient=orient),
            doc["berths"][berth_id]["box_px"],
            orient,
            fixed_len,
            None,
        )

    # All berths — full tokens (profit + cargo + some meeples)
    place_ship(hull3, "ginseng", ss["hull3_y_pct"], ware_costs["ginseng"], "port_C", "port", occupied=(0,))
    place_ship(hull3, "silk", ss["hull3_y_pct"], ware_costs["silk"], "port_B", "port", occupied=(1,))
    place_ship(hull4, "jade", ss["hull4_y_pct"], ware_costs["jade"], "port_A", "port", occupied=(0, 2))
    place_ship(hull3, "nutmeg", ss["hull3_y_pct"], ware_costs["nutmeg"], "yard_A", "yard", occupied=(2,))
    place_ship(hull3, "silk", ss["hull3_y_pct"], ware_costs["silk"], "yard_B", "yard")
    place_ship(hull4, "jade", ss["hull4_y_pct"], ware_costs["jade"], "yard_C", "yard", occupied=(1, 3))
    for i, ware in enumerate(("nutmeg", "ginseng", "silk")):
        sid = f"start_{i}"
        if sid in doc["berths"]:
            occ = (0,) if i == 0 else ((1,) if i == 1 else ())
            place_ship(hull3, ware, ss["hull3_y_pct"], ware_costs[ware], sid, "sea", occupied=occ)

    # Meeples on some shore / port / yard cost pads
    pad_meeples = [
        ("port_B", "red", 46),
        ("port_A", "blue", 46),
        ("yard_A", "green", 48),
        ("yard_C", "yellow", 48),
        ("pilot_small", "purple", 50),
        ("pirate_0", "red", 44),
        ("pirate_2", "blue", 44),
        ("insurance", "green", 48),
    ]
    for sid, color, hpx in pad_meeples:
        pad = doc["cost_pads"].get(sid)
        art = meeple_arts.get(color)
        if not pad or not art:
            continue
        paste_meeple(canvas, art, pad["center"]["x"], pad["center"]["y"], hpx)

    # Flat stock panel — fully opaque; icons + values only
    market_quad = doc.get("market_panel_quad_pct") or MARKET_PANEL_QUAD
    mw = max(4, int((max(p[0] for p in market_quad) - min(p[0] for p in market_quad)) / 100 * SIZE))
    mh = max(4, int((max(p[1] for p in market_quad) - min(p[1] for p in market_quad)) / 100 * SIZE))
    panel = Image.new("RGBA", (mw, mh), (72, 44, 24, 255))
    pd = ImageDraw.Draw(panel)
    pd.rounded_rectangle(
        [1, 1, mw - 2, mh - 2],
        radius=10,
        fill=(72, 44, 24, 255),
        outline=(232, 196, 140, 255),
        width=3,
    )
    ware_ids = ["nutmeg", "silk", "ginseng", "jade"]
    vals = [0, 5, 10, 20, 30]
    pad = 6
    body_h = mh - pad * 2
    row_h = body_h / 4
    icon_s = max(36, int(row_h * 0.78))
    val_f = market_num_font(max(18, int(row_h * 0.40)))
    for ri, wid in enumerate(ware_ids):
        y0 = pad + int(row_h * ri)
        y_mid = y0 + int(row_h * 0.5)
        if ri % 2 == 1:
            pd.rounded_rectangle(
                [4, y0 + 1, mw - 5, y0 + int(row_h) - 1],
                radius=5,
                fill=(48, 28, 14, 255),
            )
        icon_path = PIECES / f"share-{wid}.png"
        if icon_path.exists():
            ic = Image.open(icon_path).convert("RGBA").resize((icon_s, icon_s), Image.Resampling.LANCZOS)
            panel.alpha_composite(ic, (8, y_mid - icon_s // 2))
        track_x0 = 8 + icon_s + 10
        track_w = mw - track_x0 - 8
        cell_w = track_w / 5
        for ci, v in enumerate(vals):
            cx = int(track_x0 + cell_w * (ci + 0.5))
            x0 = int(track_x0 + cell_w * ci + 2)
            x1 = int(track_x0 + cell_w * (ci + 1) - 2)
            y1 = y_mid - int(row_h * 0.32)
            y2 = y_mid + int(row_h * 0.32)
            pd.rounded_rectangle(
                [x0, y1, x1, y2],
                radius=4,
                fill=(28, 16, 8, 255),
                outline=(255, 236, 200, 90),
            )
            pd.text((cx, y_mid), str(v), font=val_f, fill=(255, 244, 220, 255), anchor="mm")
    paste_flat_rect(canvas, panel, market_quad)

    canvas.convert("RGB").save(BOARD / "board-effect.jpg", quality=93)
    canvas.save(BOARD / "board-effect.png")

    costs_only = Image.open(BOARD / "board.jpg").convert("RGBA").resize((SIZE, SIZE))
    draw_berth_letters(costs_only, doc["berths"])
    for sid, pad in doc["cost_pads"].items():
        cval = pad.get("cost") or 0
        pval = pad.get("payout") or 0
        beside = pad.get("pay_beside", "none")
        centered = pad.get("paste_mode") == "centered"
        if cval > 0:
            badge = make_badge(cost_art, str(cval), 320, (45, 18, 6, 255))
            if centered:
                paste_badge_centered(costs_only, badge, pad["center"]["x"], pad["center"]["y"], 56)
            else:
                paste_on_quad(costs_only, badge, pad["quad_pct"])
        if pval > 0:
            badge = make_badge(pay_art, f"+{pval}", 300, (55, 30, 5, 255))
            if beside == "on" or centered:
                paste_badge_centered(costs_only, badge, pad["center"]["x"], pad["center"]["y"], 56)
            else:
                dx, dy = pad.get("pay_offset_pct") or [0, 0]
                q2 = [[p[0] + dx, p[1] + dy] for p in pad["quad_pct"]]
                paste_on_quad(costs_only, badge, q2)
    costs_only.convert("RGB").save(BOARD / "board-costs-only.jpg", quality=93)

    print("centers:")
    for sid, p in doc["cost_pads"].items():
        print(f"  {sid}: ({p['center']['x']},{p['center']['y']}) pay={p.get('pay_beside')}")
    subprocess.check_call([sys.executable, str(BOARD / "_build_board_config.py")])


if __name__ == "__main__":
    main()
