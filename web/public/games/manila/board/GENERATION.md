# Manila board config & generation

## Source of truth (editable)

**`web/src/games/manila/boardConfig.json`** — imported by TypeScript.

Synced copy for docs / scripts:

- `web/public/games/manila/board/boardConfig.json`

Each entry records **perspective** + **what to show**:

| Section | Key fields |
|---------|------------|
| `spots.*` | `rules` (cost/payout/…), `pad.quad_pct` (TL→TR→BR→BL %), `pad.display` (cost/pay badges, beside side, role_tag) |
| `berths.*` | `quad_pct`, `ship_orient` (`port`/`yard`) |
| `market` | `panel_quad_pct`, `wares`, `value_rows`, UV `layout`, `display` flags |
| `ship_seats` | local hull seat % for cargo ships |

Edit `quad_pct` / `display` / `market.panel_quad_pct` directly, then refresh the app. Rebuild compose art with `_rebuild_spots.py` when you want baked preview JPGs (`board-costs-only.jpg`, `board-effect.jpg`).

## Badges

| Kind | Face | Placement |
|------|------|-----------|
| Cost | Orange disc | ON pad (`display.cost_badge`) |
| Payout | Yellow disc | BESIDE pad (`display.pay_beside`) |

Font: Georgia Bold.

## Scripts

- `_rebuild_spots.py` — detect pads, write `anchors.json` (public only), compose preview JPGs, then `_build_board_config.py`
- `_build_board_config.py` — merge anchors + rules → `boardConfig.json` (src + public)

## TS entry points

- `boardConfig.ts` — typed accessors for spots / berths / market panel
- `boardLayout.ts` — sea lanes, pirate seats, loan constants, asset URLs
- `assets.ts` — piece / badge / meeple URLs (`ASSET_V` cache bust)
- `quadWarp.ts` — `matrix3d` / `padSpotStyle` / `coverBerthStyle`
