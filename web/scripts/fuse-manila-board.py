#!/usr/bin/env python3
"""Build a playable Manila board plate: soft base + feathered landmarks + uniform pads + digits."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "public" / "games" / "manila" / "board"
BLOCKS = BOARD / "blocks"
ASSETS = Path(r"C:\Users\micro\.cursor\projects\d-IHope\assets")
OUT = BOARD / "board.jpg"

W, H = 1080, 1920
PAD_R = 28  # identical pad radius in px


def is_magenta(r: int, g: int, b: int) -> bool:
    if r >= 150 and g <= 120 and (r - g) >= 70 and b >= 40 and b <= 220:
        if g < 90 or (r >= 180 and (r - g) >= 90):
            return True
    if r >= 160 and b >= 140 and g <= 110 and (r - g) >= 50 and (b - g) >= 40:
        return True
    return False


def chroma_key(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    mask = [[False] * w for _ in range(h)]
    stack: list[tuple[int, int]] = []
    for x in range(w):
        for y in (0, h - 1):
            r, g, b, _ = px[x, y]
            if is_magenta(r, g, b):
                stack.append((x, y))
                mask[y][x] = True
    for y in range(h):
        for x in (0, w - 1):
            r, g, b, _ = px[x, y]
            if is_magenta(r, g, b):
                stack.append((x, y))
                mask[y][x] = True
    while stack:
        x, y = stack.pop()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not mask[ny][nx]:
                r, g, b, _ = px[nx, ny]
                if is_magenta(r, g, b):
                    mask[ny][nx] = True
                    stack.append((nx, ny))
    for y in range(h):
        for x in range(w):
            if mask[y][x]:
                r, g, b, _ = px[x, y]
                px[x, y] = (r, g, b, 0)
            else:
                r, g, b, a = px[x, y]
                if not is_magenta(r, g, b):
                    continue
                keyed = 0
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h and mask[ny][nx]:
                        keyed += 1
                if keyed >= 2:
                    px[x, y] = (r, g, b, 0)
    return im


def feather_alpha(im: Image.Image, radius: int = 10) -> Image.Image:
    """Soften silhouette so landmarks melt into the plate."""
    im = im.convert("RGBA")
    r, g, b, a = im.split()
    a = a.filter(ImageFilter.GaussianBlur(radius=radius))
    return Image.merge("RGBA", (r, g, b, a))


def fit(im: Image.Image, max_w: int, max_h: int) -> Image.Image:
    ratio = min(max_w / im.width, max_h / im.height)
    return im.resize(
        (max(1, int(im.width * ratio)), max(1, int(im.height * ratio))),
        Image.Resampling.LANCZOS,
    )


def paste_center(base: Image.Image, overlay: Image.Image, cx: float, cy: float) -> None:
    x = int(cx / 100 * base.width - overlay.width / 2)
    y = int(cy / 100 * base.height - overlay.height / 2)
    base.alpha_composite(overlay, (max(0, x), max(0, y)))


def track_y(pos: int) -> float:
    open_y, at5, finish = 78.0, 54.0, 20.0
    p = max(0, min(13, pos))
    if p <= 5:
        return open_y + (p / 5.0) * (at5 - open_y)
    return at5 + ((p - 5) / 8.0) * (finish - at5)


def make_pad() -> Image.Image:
    d = PAD_R * 2 + 8
    im = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    c = d // 2
    # soft shadow
    draw.ellipse((c - PAD_R + 2, c - PAD_R + 3, c + PAD_R + 2, c + PAD_R + 3), fill=(40, 50, 60, 70))
    # stone/foam pad
    draw.ellipse((c - PAD_R, c - PAD_R, c + PAD_R, c + PAD_R), fill=(235, 232, 220, 245))
    draw.ellipse((c - PAD_R + 4, c - PAD_R + 4, c + PAD_R - 4, c + PAD_R - 4), fill=(248, 246, 238, 255))
    return im.filter(ImageFilter.GaussianBlur(radius=0.6))


def load_base() -> Image.Image:
    candidates = [
        ASSETS / "manila-board-base-organic-v1.jpg",
        ASSETS / "manila-board-base-empty-v1.jpg",
        ASSETS / "manila-board-gameplate-v2.jpg",
        BLOCKS / "sea-13rows.jpg",
    ]
    for path in candidates:
        if path.exists():
            im = Image.open(path).convert("RGBA").resize((W, H), Image.Resampling.LANCZOS)
            return im
    raise FileNotFoundError("no base plate found")


def main() -> None:
    canvas = load_base()

    # Soft landmarks on SIDE gutters only (center channel clear)
    pirate = feather_alpha(fit(chroma_key(Image.open(BLOCKS / "pirate-h3.jpg")), int(W * 0.26), int(H * 0.12)), 12)
    paste_center(canvas, pirate, 18, 28)

    pilots = feather_alpha(fit(chroma_key(Image.open(BLOCKS / "pilots-2.jpg")), int(W * 0.30), int(H * 0.14)), 14)
    paste_center(canvas, pilots, 16, 74)

    insurance = feather_alpha(fit(chroma_key(Image.open(BLOCKS / "insurance-1.jpg")), int(W * 0.18), int(H * 0.12)), 12)
    paste_center(canvas, insurance, 86, 74)

    # Uniform pads — vertical stacks on sides + pirate deck + pilots + insurance
    pad = make_pad()
    pads: list[tuple[float, float]] = [
        # left port vertical (斜靠岸)
        (12, 36),
        (13, 46),
        (12, 56),
        # right yard vertical
        (88, 36),
        (87, 46),
        (88, 56),
        # pirate deck (bow toward center = rightward seats)
        (14, 26),
        (18, 27),
        (22, 26),
        # pilots
        (18, 78),
        (24, 80),
        # insurance
        (84, 80),
    ]
    for cx, cy in pads:
        paste_center(canvas, pad, cx, cy)

    # Digits 1–13 beside channel (not on sailing mid-line)
    for n in range(1, 14):
        path = BLOCKS / "digits" / f"{n:02d}.jpg"
        d = feather_alpha(fit(chroma_key(Image.open(path)), int(W * 0.05), int(H * 0.04)), 2)
        d = ImageEnhance.Brightness(d).enhance(1.1)
        paste_center(canvas, d, 64, track_y(n))

    # Light overall grain soften so it reads as one plate
    rgb = canvas.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(1.05)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.02)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    rgb.save(OUT, "JPEG", quality=93, optimize=True)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes) pads={len(pads)}")


if __name__ == "__main__":
    main()
