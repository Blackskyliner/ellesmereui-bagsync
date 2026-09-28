#!/usr/bin/env python3
"""Draws the addon icon: a sack like the game's bag icons with a refresh sign
in it (the bags of all characters, kept in sync), in EllesmereUI's flat
accent-green line style (its own logo is a 64x64 TGA glyph of that kind).

Writes
  EllesmereUIBags_Alts/media/icon.tga   64x64, the TOC's ## IconTexture (in game)
  docs/media/icon-400.png               400x400 on a dark tile, the project avatar
  docs/media/icon-64.png                preview of the in-game icon

Run with the project venv (Pillow): .tools/venv/bin/python scripts/make-icon.py
"""
import os

import math

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GREEN = (0x0C, 0xD2, 0x9F)          # EllesmereUI's default accent colour
TILE = (0x14, 0x16, 0x18)            # avatar background, EUI's dark panel tone
SS = 8                               # supersampling factor


def bezier(p0, p1, p2, p3, n=48):
    """Points of a cubic Bezier curve."""
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def stroke(draw, points, width, colour):
    """A round-capped line along points, stamped as dots: Pillow's own joints
    leave hairline spikes on curves made of many short segments."""
    r = width / 2
    step = max(1.0, width / 6)
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0) / step))
        for i in range(n + 1):
            x, y = x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n
            draw.ellipse((x - r, y - r, x + r, y + r), fill=colour)


def sack(draw, s, ox, oy, width, colour):
    """The sack in unit coordinates scaled by s: a round body gathered at the
    neck, a tie around it and the open mouth above."""
    P = lambda x, y: (ox + x * s, oy + y * s)
    body = (bezier(P(0.40, 0.36), P(0.14, 0.42), P(0.06, 0.66), P(0.16, 0.82))
            + bezier(P(0.16, 0.82), P(0.26, 0.97), P(0.74, 0.97), P(0.84, 0.82))[1:]
            + bezier(P(0.84, 0.82), P(0.94, 0.66), P(0.86, 0.42), P(0.60, 0.36))[1:])
    curves = [
        body,
        bezier(P(0.40, 0.29), P(0.36, 0.22), P(0.26, 0.17), P(0.24, 0.10)),
        bezier(P(0.24, 0.10), P(0.40, 0.15), P(0.60, 0.15), P(0.76, 0.10)),
        bezier(P(0.76, 0.10), P(0.74, 0.17), P(0.64, 0.22), P(0.60, 0.29)),
    ]
    for curve in curves:
        stroke(draw, curve, width, colour)
    # the tie around the neck
    x0, y0 = P(0.33, 0.28)
    x1, y1 = P(0.67, 0.37)
    draw.rounded_rectangle((x0, y0, x1, y1), radius=(y1 - y0) / 2, fill=colour)


def refresh(draw, cx, cy, radius, width, colour):
    """Two arrows chasing each other round a circle (the sync sign)."""
    half = 1.15 * width                  # half the arrow head's base
    reach = 1.7 * width                  # tip ahead of the base, along the circle
    for start in (200, 20):
        span = 125
        box = (cx - radius, cy - radius, cx + radius, cy + radius)
        draw.arc(box, start=start, end=start + span, fill=colour, width=width)
        # arrow head at the end of the arc, pointing along it (clockwise)
        a = math.radians(start + span)
        mid = radius - width / 2
        base = (cx + mid * math.cos(a), cy + mid * math.sin(a))
        nx, ny = math.cos(a), math.sin(a)          # outward normal at the base
        tx, ty = -math.sin(a), math.cos(a)         # clockwise tangent at the base
        tip = (base[0] + tx * reach, base[1] + ty * reach)
        draw.polygon([tip, (base[0] + nx * half, base[1] + ny * half),
                      (base[0] - nx * half, base[1] - ny * half)], fill=colour)
        # round the tail
        t = math.radians(start)
        tail = (cx + mid * math.cos(t), cy + mid * math.sin(t))
        r = width / 2
        draw.ellipse((tail[0] - r, tail[1] - r, tail[0] + r, tail[1] + r), fill=colour)


def glyph(size, padding):
    """Sack and refresh sign on a transparent square of `size` px."""
    s = size * SS
    inner = s - 2 * padding * SS
    stroke = max(1, round(0.075 * inner))
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    ox = oy = padding * SS
    sack(draw, inner, ox, oy, stroke, GREEN + (255,))
    refresh(draw, ox + 0.50 * inner, oy + 0.645 * inner, 0.165 * inner, round(0.8 * stroke), GREEN + (255,))
    return img.resize((size, size), Image.LANCZOS)


def main():
    media = os.path.join(ROOT, "EllesmereUIBags_Alts", "media")
    docs = os.path.join(ROOT, "docs", "media")
    os.makedirs(media, exist_ok=True)
    os.makedirs(docs, exist_ok=True)

    icon = glyph(64, 3)
    # Uncompressed 32-bit, origin top-left: the same layout as EllesmereUI's logo.
    icon.save(os.path.join(media, "icon.tga"), compression=None, orientation=1)
    icon.save(os.path.join(docs, "icon-64.png"))

    avatar = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
    tile = Image.new("RGBA", (400 * SS, 400 * SS), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle((0, 0, 400 * SS - 1, 400 * SS - 1), radius=72 * SS, fill=TILE + (255,))
    avatar.alpha_composite(tile.resize((400, 400), Image.LANCZOS))
    avatar.alpha_composite(glyph(400, 56))
    avatar.save(os.path.join(docs, "icon-400.png"))
    print("wrote media/icon.tga, docs/media/icon-400.png, docs/media/icon-64.png")


if __name__ == "__main__":
    main()
