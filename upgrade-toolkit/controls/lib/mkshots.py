#!/usr/bin/env python3
"""mkshots.py OUT: synthetic journey screenshots for the shotdiff controls (pure Python, no PIL).

OUT/old       shots-Administrator/{login,dashboard}-Administrator-step1.png: a header bar, a title and three filled charts
OUT/same      the same pages, a few pixels of the title text differ (rendering noise)              -> PASS
OUT/empty     dashboard with the charts gone (the E4 / E5b empty-chart regression)                  -> REVIEW
OUT/missing   only the login page                                                                   -> INVALID
OUT/notreach  dashboard saved as ...-NOT-REACHED.png                                                -> INVALID
OUT/taller    dashboard 200 px taller (page grew)                                                   -> REVIEW
OUT/loading   dashboard is the Mendix progress bar in a white box (the E6-17 MonitoringDashboard shot) -> INVALID
OUT/loadname  dashboard saved as ...-LOADING.png (smokewalk/engine settle wait ran out)            -> INVALID
OUT/divider-old, OUT/divider-new: a white page with a full-width thin divider line (must not look loading)  -> PASS
OUT/barboth-old, OUT/barboth-new: the same progress-bar look on both sides, images equal (T5-18, T6-15)  -> REVIEW
OUT/barmoved-new: the bar on both sides, but the NEW page also has charts (pair changed)              -> INVALID
OUT/stuck     dashboard saved as ...-STUCK.png (settle.js: indicator stayed, DOM still, T7-22)       -> INVALID, closable
OUT/stuckeq-old/-new, stuckeq-newside-new, stuckeq-loading-new, stuckdiff-old/-new: one-sided STUCK (N1-8)
OUT/nrboth-old, OUT/nrboth-new: dashboard NOT-REACHED on both sides (T1-24, used to PASS)            -> INVALID BASELINE DEFECT
OUT/runid-a, OUT/runid-b: the "empty" dashboard with a per-run id block at x 300-359, y 60-75 that differs
              between the two runs (B4T2-17); OUT/runid-moved: run b with the title changed too (outside the mask)
"""
import os, struct, sys, zlib

W, H = 480, 360


def png(path, rows):
    h, w = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(t, b):
        return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xFFFFFFFF)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def page(charts=True, noise=False, height=H):
    rows = [[245] * W for _ in range(height)]
    for y in range(0, 30):                       # header bar
        rows[y] = [30] * W
    for y in range(45, 55):                      # title "text": dashes
        for x in range(20, 200):
            rows[y][x] = 40 if (x // 6) % 2 == 0 else 245
    if noise:
        for x in range(20, 26):
            rows[50][x] = 245
    if charts:
        for i in range(3):                       # three bar charts with axes
            x0 = 20 + i * 155
            for y in range(90, 300):
                rows[y][x0] = 60
            for x in range(x0, x0 + 140):
                rows[300][x] = 60
            for b in range(5):
                top = 290 - (b * 37 + i * 13) % 180
                for y in range(top, 300):
                    for x in range(x0 + 10 + b * 26, x0 + 30 + b * 26):
                        rows[y][x] = 90 + b * 25
    return rows


def loading_page():
    """Header, title, then the progress indicator: white 250x42 box at the centre, 2 px bar, dark moving part."""
    rows = page(charts=False)
    for y in range(90, 132):
        for x in range(W // 2 - 125, W // 2 + 125):
            rows[y][x] = 255
    for y in (110, 111):
        for x in range(W // 2 - 108, W // 2 + 108):
            rows[y][x] = 248 if x < W // 2 + 54 else 114
    return rows


def divider_page():
    rows = [[255] * W for _ in range(H)]
    for y in range(0, 30):
        rows[y] = [30] * W
    for x in range(W):
        rows[120][x] = 120
    return rows


def text_pairs(out, sd):
    """NR1-25: identical images, only the visible text beside them (NAME.txt) differs.
    textold/textsame -> PASS; textlost ("Status" became "Select") and textdup (paging text twice) -> REVIEW;
    textnone: an image with no .txt on one side -> pixels only, PASS."""
    base = "Status Search Currently showing 0 to 0 of 0\nCreated 12 Oct 2026 14:03 id 4711\n"
    texts = {"textold": base, "textsame": base.replace("12 Oct 2026 14:03 id 4711", "13 Oct 2026 09:41 id 4999"),
             "textlost": base.replace("Status", "Select"),
             "textdup": base + "Currently showing 0 to 0 of 0\n"}
    for v, t in texts.items():
        png(f"{out}/{v}/{sd}/overview-Administrator-step1.png", page())
        open(f"{out}/{v}/{sd}/overview-Administrator-step1.txt", "w").write(t)
    png(f"{out}/textnone/{sd}/overview-Administrator-step1.png", page())


def main():
    out = sys.argv[1]
    sd = "shots-Administrator"
    text_pairs(out, sd)
    login = page(charts=False)
    for v in ("old", "same", "empty", "missing", "notreach", "taller", "loading", "loadname"):
        png(f"{out}/{v}/{sd}/login-Administrator-step1.png", login)
    png(f"{out}/old/{sd}/dashboard-Administrator-step1.png", page())
    png(f"{out}/same/{sd}/dashboard-Administrator-step1.png", page(noise=True))
    png(f"{out}/empty/{sd}/dashboard-Administrator-step1.png", page(charts=False))
    png(f"{out}/notreach/{sd}/dashboard-Administrator-step1-NOT-REACHED.png", page(charts=False))
    png(f"{out}/taller/{sd}/dashboard-Administrator-step1.png", page(height=H + 200))
    png(f"{out}/loading/{sd}/dashboard-Administrator-step1.png", loading_page())
    png(f"{out}/loadname/{sd}/dashboard-Administrator-step1-LOADING.png", page())
    for v in ("divider-old", "divider-new"):
        png(f"{out}/{v}/{sd}/divider-Administrator-step1.png", divider_page())
    for v in ("barboth-old", "barboth-new"):
        png(f"{out}/{v}/{sd}/dashboard-Administrator-step1.png", loading_page())
    moved = loading_page()
    for y in range(180, 340):                    # a filled block under the bar: the NEW page changed
        for x in range(20, 460):
            moved[y][x] = 70 + (x // 20) % 4 * 30
    png(f"{out}/barmoved-new/{sd}/dashboard-Administrator-step1.png", moved)
    png(f"{out}/stuck/{sd}/dashboard-Administrator-step1-STUCK.png", page(charts=False))
    png(f"{out}/stuck/{sd}/login-Administrator-step1.png", login)
    # N1-8: stuckeq-old is named -STUCK, stuckeq-new is settled; same page, only the top 10 px differ (theme top bar)
    topbar = page()
    for y in range(0, 6):
        topbar[y] = [200] * W
    png(f"{out}/stuckeq-old/{sd}/dashboard-Administrator-step1-STUCK.png", topbar)
    png(f"{out}/stuckeq-new/{sd}/dashboard-Administrator-step1.png", page())
    for v in ("stuckeq-old", "stuckeq-new", "stuckdiff-old", "stuckdiff-new"):
        png(f"{out}/{v}/{sd}/login-Administrator-step1.png", login)
    # same one-sided STUCK name, but the page content differs below the band (real STUCK: empty grid) -> INVALID
    png(f"{out}/stuckdiff-old/{sd}/dashboard-Administrator-step1-STUCK.png", page(charts=False))
    png(f"{out}/stuckdiff-new/{sd}/dashboard-Administrator-step1.png", page())
    # NEW side named -STUCK, OLD settled, otherwise equal
    png(f"{out}/stuckeq-newside-new/{sd}/dashboard-Administrator-step1-STUCK.png", page())
    png(f"{out}/stuckeq-newside-new/{sd}/login-Administrator-step1.png", login)
    # a -LOADING name on a pixel-identical pair must still be INVALID
    png(f"{out}/stuckeq-loading-new/{sd}/dashboard-Administrator-step1-LOADING.png", page())
    png(f"{out}/stuckeq-loading-new/{sd}/login-Administrator-step1.png", login)
    for v in ("nrboth-old", "nrboth-new"):
        png(f"{out}/{v}/{sd}/dashboard-Administrator-step1-NOT-REACHED.png", page(charts=False))
    # B4T2-17: a created row's id differs per run; everything else is the same REVIEW page
    for v, seed in (("runid-a", 1), ("runid-b", 2), ("runid-moved", 2)):
        rows = page(charts=False)
        for y in range(60, 76):
            for x in range(300, 360):
                rows[y][x] = 40 if ((x * seed) // 5 + y) % 3 == 0 else 245
        if v == "runid-moved":
            for y in range(45, 55):
                rows[y][20:200] = [245] * 180
        png(f"{out}/{v}/{sd}/dashboard-Administrator-step1.png", rows)
        png(f"{out}/{v}/{sd}/login-Administrator-step1.png", login)
    print(out)


if __name__ == "__main__":
    main()
