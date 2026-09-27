#!/usr/bin/env python3
"""Crop, compare and report the renders of scripts/visual-test.sh.

  visual-compare.py [--update] OUT_DIR BASELINE_DIR scenario...

For every mode directory in OUT_DIR (eui, noeui) and scenario:
  * the target frame's screen rect is read from the --dump-tree log of the
    same run and the full-screen render is cropped to it;
  * the crop is compared with BASELINE_DIR/<mode>/<scenario>.webp (lossless): a pixel
    counts as different when a channel differs by more than CHANNEL_TOL
    (WebP is lossy); the scenario fails above PIXEL_TOL of its pixels or on a
    size change;
  * --update writes the crop as the new baseline instead.
Writes <scenario>.png, <scenario>-diff.png and report.html into OUT_DIR.
Exit code 1 on any failure (missing baseline, size change, difference, Lua
error during the scenario).
"""
import html
import os
import re
import sys

from PIL import Image, ImageChops

CHANNEL_TOL = 24        # per channel, 0..255
PIXEL_TOL = 0.001       # share of pixels allowed to differ
MODES = ("eui", "noeui")


def frame_rect(log_path, frame):
    pat = re.compile(r"^" + re.escape(frame) + r" \[\w+\] \((\d+)x(\d+)\) .*?x=(-?\d+), y=(-?\d+)")
    with open(log_path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            m = pat.match(line)
            if m:
                w, h, x, y = (int(v) for v in m.groups())
                return x, y, w, h
    return None


def lua_errors(log_path):
    with open(log_path, encoding="utf-8", errors="ignore") as fh:
        return [l.strip() for l in fh if l.startswith("[exec-lua] error")]


def diff_image(a, b):
    """-> (differing pixel count, highlight image)"""
    delta = ImageChops.difference(a, b)
    bands = delta.split()
    peak = bands[0]
    for band in bands[1:]:
        peak = ImageChops.lighter(peak, band)
    mask = peak.point(lambda v: 255 if v > CHANNEL_TOL else 0)
    count = sum(1 for v in mask.getdata() if v)
    faded = Image.blend(b, Image.new("RGB", b.size, (0, 0, 0)), 0.7)
    red = Image.new("RGB", b.size, (255, 0, 64))
    return count, Image.composite(red, faded, mask)


def main(argv):
    update = argv[:1] == ["--update"]
    if update:
        argv = argv[1:]
    out_dir, base_dir, scenarios = argv[0], argv[1], argv[2:]
    rows, failures = [], 0
    for mode in MODES:
        for name in scenarios:
            prefix = os.path.join(out_dir, mode, name)
            if not os.path.exists(prefix + ".webp"):
                continue
            with open(prefix + ".frame") as fh:
                frame = fh.read().strip()
            status, detail = "ok", ""
            errors = lua_errors(prefix + ".log")
            rect = frame_rect(prefix + ".log", frame)
            base_path = os.path.join(base_dir, mode, name + ".webp")
            if errors:
                status, detail = "error", "; ".join(errors)
            elif not rect or rect[2] <= 0 or rect[3] <= 0:
                status, detail = "error", "frame %s not rendered" % frame
            else:
                x, y, w, h = rect
                current = Image.open(prefix + ".webp").convert("RGB").crop((x, y, x + w, y + h))
                current.save(prefix + ".png")
                if update:
                    os.makedirs(os.path.dirname(base_path), exist_ok=True)
                    current.save(base_path, "WEBP", lossless=True, method=6)
                    status, detail = "updated", "%dx%d" % (w, h)
                elif not os.path.exists(base_path):
                    status, detail = "missing", "no baseline (run with --update)"
                else:
                    base = Image.open(base_path).convert("RGB")
                    if base.size != current.size:
                        status, detail = "size", "baseline %dx%d, now %dx%d" % (base.size + current.size)
                    else:
                        count, highlight = diff_image(base, current)
                        share = count / float(w * h)
                        detail = "%d px differ (%.3f%%)" % (count, share * 100)
                        if count:
                            highlight.save(prefix + "-diff.png")
                        if share > PIXEL_TOL:
                            status = "diff"
            if status not in ("ok", "updated"):
                failures += 1
            rows.append((mode, name, status, detail, base_path))
            print("%-8s %-6s %-22s %s" % (status.upper(), mode, name, detail))
    write_report(out_dir, rows)
    print("\n%d scenario renders, %d failed. Report: %s" % (len(rows), failures, os.path.join(out_dir, "report.html")))
    return 1 if failures else 0


def write_report(out_dir, rows):
    def img(path):
        if not os.path.exists(path):
            return "<em>-</em>"
        return '<img src="file://%s">' % html.escape(os.path.abspath(path))
    parts = ["<!doctype html><meta charset='utf-8'><title>Visual test report</title>",
             "<style>body{font:13px sans-serif;background:#1b1b1f;color:#ddd}td{vertical-align:top;padding:6px}"
             "img{max-width:460px;border:1px solid #444}.fail{color:#ff6b6b}.ok{color:#7bd88f}</style>",
             "<table><tr><th>scenario</th><th>baseline</th><th>current</th><th>diff</th></tr>"]
    for mode, name, status, detail, base_path in sorted(rows, key=lambda r: (r[2] in ("ok", "updated"), r[0], r[1])):
        prefix = os.path.join(out_dir, mode, name)
        cls = "ok" if status in ("ok", "updated") else "fail"
        parts.append("<tr><td><b>%s/%s</b><br><span class='%s'>%s</span><br>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (
            mode, name, cls, status, html.escape(detail), img(base_path), img(prefix + ".png"), img(prefix + "-diff.png")))
    parts.append("</table>")
    with open(os.path.join(out_dir, "report.html"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(parts))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
