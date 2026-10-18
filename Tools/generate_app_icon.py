#!/usr/bin/env python3
"""Build the NeoSound app icon as an Icon Composer `.icon` bundle, the way NeoBili does:
a white solid background with one glass layer, a crescent moon in the app's accent orange.

Usage: python3 -I Tools/generate_app_icon.py
"""
from pathlib import Path
import json
import math

ROOT = Path(__file__).resolve().parents[1]
ACCENT = "FF9F0A"  # Assets.xcassets/AccentColor

# Crescent = outer disc minus a second disc shifted toward the upper right.
OUTER = (540.0, 500.0, 300.0)   # cx, cy, r
INNER = (680.0, 380.0, 255.0)


def intersections(a, b):
    (x0, y0, r0), (x1, y1, r1) = a, b
    d = math.hypot(x1 - x0, y1 - y0)
    along = (r0 * r0 - r1 * r1 + d * d) / (2 * d)
    h = math.sqrt(r0 * r0 - along * along)
    mx, my = x0 + along * (x1 - x0) / d, y0 + along * (y1 - y0) / d
    ox, oy = h * (y1 - y0) / d, -h * (x1 - x0) / d
    return (mx + ox, my + oy), (mx - ox, my - oy)


def crescent_path():
    p, q = intersections(OUTER, INNER)
    r0, r1 = OUTER[2], INNER[2]
    f = lambda v: f"{v:.1f}"
    # Outer edge: the long way round from p to q, away from the inner disc.
    # Inner edge: back from q to p along the inner disc, bulging into the crescent.
    return (f"M {f(p[0])} {f(p[1])} "
            f"A {f(r0)} {f(r0)} 0 1 0 {f(q[0])} {f(q[1])} "
            f"A {f(r1)} {f(r1)} 0 0 1 {f(p[0])} {f(p[1])} Z")


MARK = f'<path d="{crescent_path()}"'
destination = ROOT / "NeoSound/Resources/AppIcons/NeoSoundIcon.icon"
(destination / "Assets").mkdir(parents=True, exist_ok=True)
(destination / "Assets/Moon.svg").write_text(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
    f'viewBox="0 0 1024 1024">{MARK} fill="#{ACCENT}"/></svg>\n'
)
document = {
    "fill": {"solid": "srgb:1.00000,1.00000,1.00000,1.00000"},
    "groups": [{
        "layers": [{
            "blend-mode": "normal",
            "fill": "automatic",
            "glass": True,
            "hidden": False,
            "image-name": "Moon.svg",
            "name": "Moon",
        }],
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": True, "value": 0.3},
    }],
    "supported-platforms": {"squares": "shared"},
}
document_path = destination / "icon.json"
if document_path.exists():
    # Keep material settings edited in Icon Composer; only the background and artwork are owned here.
    edited = json.loads(document_path.read_text())
    edited["fill"] = document["fill"]
    edited["groups"][0]["layers"][0]["image-name"] = "Moon.svg"
    document = edited
document_path.write_text(json.dumps(document, indent=2) + "\n")

# Flat, editable master for vector tools and previews.
master = ROOT / "Docs/AppIcon/Moon-white-master.svg"
master.parent.mkdir(parents=True, exist_ok=True)
master.write_text(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
    '<rect width="1024" height="1024" fill="#FFFFFF"/>\n'
    f'{MARK} id="moon" fill="#{ACCENT}"/>\n'
    "</svg>\n"
)
print(f"Wrote {destination.relative_to(ROOT)} and {master.relative_to(ROOT)}")
