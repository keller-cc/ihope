# Manila board config & generation

## Source of truth (editable)

**`boardConfig.json`** — synced at:

- `web/src/games/manila/boardConfig.json` (imported by TS)
- `web/public/games/manila/board/boardConfig.json` (asset / docs copy)

Each entry records **perspective** + **what to show**:

| Section | Key fields |
|---------|------------|
| `spots.*` | `rules` (cost/payout/…), `pad.quad_pct` (TL→TR→BR→BL %), `pad.display` (cost/pay badges, beside side, role_tag) |
| `berths.*` | `quad_pct`, `ship_orient` (`port`/`yard`) |
| `market` | `panel_quad_pct`, `wares`, `value_rows`, UV `layout`, `display` flags |
| `ship_seats` | local hull seat % for cargo ships |

Edit `quad_pct` / `display` / `market.panel_quad_pct` directly, then refresh the app. Rebuild compose art with `_rebuild_spots.py` when you want baked preview JPGs.

## Badges

| Kind | Face | Placement |
|------|------|-----------|
| Cost | Orange disc | ON pad (`display.cost_badge`) |
| Payout | Yellow disc | BESIDE pad (`display.pay_beside`) |

Font: Georgia Bold.

## Scripts

- `_rebuild_spots.py` — detect pads, write `anchors.json`, compose JPGs, then `_build_board_config.py`
- `_build_board_config.py` — merge anchors + rules → `boardConfig.json`

## TS entry points

- `boardConfig.ts` — typed accessors, UV→% for market, `boardSpotDefs()`
- `spotCatalog.ts` — init runtime state from config
- `quadWarp.ts` — `matrix3d` / `padSpotStyle` / `berthShipStyle`
