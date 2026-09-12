"""
Build boardConfig.json from current anchors.json + spot rules + market panel.
This is the editable source of truth: each entry has transform (quad) + display.
"""
from __future__ import annotations

import json
from pathlib import Path

BOARD = Path(r"d:\IHope\web\public\games\manila\board")
SRC = Path(r"d:\IHope\web\src\games\manila")

LABELS = {
    "port_A": "港口 A",
    "port_B": "港口 B",
    "port_C": "港口 C",
    "yard_A": "修船厂 A",
    "yard_B": "修船厂 B",
    "yard_C": "修船厂 C",
    "pirate_0": "海盗船长",
    "pirate_1": "海盗水手",
    "pirate_2": "海盗水手",
    "pilot_small": "小领航",
    "pilot_large": "大领航",
    "insurance": "保险",
}

KIND = {
    "port_A": "port",
    "port_B": "port",
    "port_C": "port",
    "yard_A": "shipyard",
    "yard_B": "shipyard",
    "yard_C": "shipyard",
    "pirate_0": "pirate",
    "pirate_1": "pirate",
    "pirate_2": "pirate",
    "pilot_small": "pilot",
    "pilot_large": "pilot",
    "insurance": "insurance",
}

SLOT_ID = {
    "yard_A": "shipyard_A",
    "yard_B": "shipyard_B",
    "yard_C": "shipyard_C",
}


def pay_beside(region: str, sid: str, pad: dict) -> str:
    if "pay_beside" in pad:
        return pad["pay_beside"]
    if sid == "insurance":
        return "on"
    if region == "port":
        return "left"
    if region == "yard":
        return "up-right"
    return "none"


def role_tag(sid: str):
    if sid in ("pilot_small", "pilot_large", "insurance"):
        return sid
    return None


def main():
    anc = json.loads((BOARD / "anchors.json").read_text(encoding="utf-8"))
    spots = {}
    for sid, pad in anc["cost_pads"].items():
        region = pad.get("region", "shore")
        cost = pad.get("cost") or 0
        payout = pad.get("payout") or 0
        slot_id = SLOT_ID.get(sid, sid)
        entry = {
            "id": slot_id,
            "anchor_id": sid,
            "kind": KIND.get(sid, "port"),
            "region": region,
            "label": LABELS.get(sid, sid),
            "rules": {
                "cost": cost,
                "payout": payout,
            },
            "pad": {
                "center": pad["center"],
                "quad_pct": pad["quad_pct"],
                "plane": pad.get("plane"),
                "display": {
                    "cost_badge": cost > 0,
                    "cost_value": cost if cost > 0 else None,
                    "pay_badge": payout > 0,
                    "pay_value": payout if payout > 0 else None,
                    "pay_beside": pay_beside(region, sid, pad),
                    "pay_offset_pct": pad.get("pay_offset_pct") or [0, 0],
                    "role_tag": role_tag(sid),
                },
            },
        }
        if sid.startswith("port_"):
            entry["rules"]["berth"] = sid[-1]
            entry["linked_berth"] = sid
        if sid.startswith("yard_"):
            entry["rules"]["berth"] = sid[-1]
            entry["linked_berth"] = sid
        if sid.startswith("pirate_"):
            entry["rules"]["pirate_rank"] = int(sid[-1])
        if sid == "pilot_small":
            entry["rules"]["pilot_size"] = "small"
        if sid == "pilot_large":
            entry["rules"]["pilot_size"] = "large"
        spots[slot_id] = entry

    berths = {}
    for bid, b in anc["berths"].items():
        region = b.get("region", "")
        orient = "port" if region == "berth_port" else "yard"
        letter = None
        if bid.startswith("port_") or bid.startswith("yard_"):
            letter = bid[-1]
        berths[bid] = {
            "id": bid,
            "region": region,
            "center": b["center"],
            "quad_pct": b["quad_pct"],
            "plane": b.get("plane"),
            "ship_orient": orient,
            "ship_rot_deg": b.get("ship_rot_deg"),
            "display": {
                "accepts_ship": True,
                "perspective": False,
                "letter": letter,
            },
        }

    # Stock / black-market panel — frost pad on sand (from anchors / board.jpg).
    market_quad = anc.get("market_panel_quad_pct") or [
        [67.2, 85.2],
        [88.6, 85.5],
        [88.8, 94.4],
        [66.3, 94.2],
    ]
    market = {
        "id": "black_market",
        "label": "黑市行情",
        "orientation": "landscape",
        "panel_quad_pct": market_quad,
        "wares": ["nutmeg", "silk", "ginseng", "jade"],
        "value_rows": [30, 20, 10, 5, 0],
        "track_values": [0, 5, 10, 20, 30],
        "layout": {
            "tag_x": 0.12,
            "first_value_x": 0.38,
            "col_w": 0.12,
            "row_pad_y": 0.16,
            "row_h": 0.2,
        },
        "display": {
            "show_ware_tags": True,
            "show_value_labels": True,
            "show_price_markers": True,
            "panel_wood": True,
        },
    }

    doc = {
        "$schema_note": "Editable board layout. Each spot/berth/market records perspective quad_pct + display content. Re-run compose after edits; keep public/ and src/ copies in sync.",
        "board": "board.jpg",
        "board_size_px": [1024, 1024],
        "coord_space": "percent of full plate (0–100), origin top-left; quad_pct = [TL, TR, BR, BL]",
        "assets": {
            "cost_badge": "pieces/spot-badge-cost.png",
            "pay_badge": "pieces/spot-badge-pay.png",
            "panel_wood": "board/panel-wood.png",
        },
        "region_pad": anc.get("region_pad"),
        "region_berth": anc.get("region_berth"),
        "spots": spots,
        "berths": berths,
        "market": market,
        "ship_seats": anc.get("ship_seats"),
    }

    text = json.dumps(doc, ensure_ascii=False, indent=2)
    (BOARD / "boardConfig.json").write_text(text, encoding="utf-8")
    (SRC / "boardConfig.json").write_text(text, encoding="utf-8")
    # Keep anchors.json as a thin projection for older scripts
    print("wrote boardConfig.json", len(spots), "spots,", len(berths), "berths")


if __name__ == "__main__":
    main()
