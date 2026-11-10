# -*- coding: utf-8 -*-
"""Scaled design drawings of the base camp (docs/design/*.png), generated from tools/design/params.py.\nRun:  python -X utf8 tools/draw_design.py\nPlans are north-up unless the title says otherwise (plot X = world x, plot Y = -world z). Units: metres."""
import math
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Arc, Circle, FancyBboxPatch, Polygon, Rectangle, Wedge

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "design"))
import params as P  # noqa: E402

matplotlib.rcParams["font.family"] = ["Malgun Gothic", "Arial"]
matplotlib.rcParams["axes.unicode_minus"] = False

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "design")
os.makedirs(OUT, exist_ok=True)

K = "#222222"; HULL = "#c9ced6"; INFL = "#e3dac6"; FLOOR = "#f4f4f4"; EQ = "#a9bfe0"; EQ2 = "#c7d7ee"
DIM = "#b03020"; REGO = "#cfc6b6"; WATER = "#7fb2e0"; HATCHC = "#e07b22"; GLASS = "#8fd0f0"; PIT = "#777777"
QUIET = "#cfdcf6"; BUF = "#e4e9ec"; NOISY = "#f6d9b8"; GREEN = "#d6ecc9"


# ------------------------------------------------------------------ helpers
def new_sheet(figsize, xlim, ylim, title, code):
    fig, ax = plt.subplots(figsize=figsize)
    ax.set_aspect("equal"); ax.axis("off"); ax.set_xlim(*xlim); ax.set_ylim(*ylim)
    fig.suptitle(f"{code}   {title}", fontsize=13, weight="bold", x=0.02, ha="left", y=0.985)
    fig.text(0.98, 0.985, "단위 m · tools/design/params.py 에서 생성 · 2026-11", ha="right", va="top", fontsize=7, color="#555555")
    return fig, ax


def save(fig, name, note=""):
    if note:
        fig.text(0.02, 0.008, note, ha="left", va="bottom", fontsize=6.8, color="#444444")
    path = os.path.join(OUT, name)
    fig.savefig(path, dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("wrote", path)


def txt(ax, x, y, s, fs=6.5, color=K, ha="center", va="center", rot=0, weight="normal", bg=None, z=20):
    kw = dict(fontsize=fs, color=color, ha=ha, va=va, rotation=rot, weight=weight, zorder=z)
    if bg:
        kw["bbox"] = dict(boxstyle="round,pad=0.12", fc=bg, ec="none", alpha=0.85)
    ax.text(x, y, s, **kw)


def dim(ax, p0, p1, off, text=None, fs=6.3, color=DIM, ext=True, tside=1):
    """Dimension between p0 and p1, drawn parallel at perpendicular offset `off` (positive = left of p0->p1)."""
    x0, y0 = p0; x1, y1 = p1
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy)
    if L < 1e-9:
        return
    ux, uy = dx / L, dy / L
    nx, ny = -uy, ux
    a = (x0 + nx * off, y0 + ny * off); b = (x1 + nx * off, y1 + ny * off)
    ax.annotate("", a, b, arrowprops=dict(arrowstyle="<->", color=color, lw=0.6, shrinkA=0, shrinkB=0, mutation_scale=6), zorder=15)
    if ext:
        for (px, py), (qx, qy) in ((p0, a), (p1, b)):
            ax.plot([px, qx + nx * 0.06 * (1 if off >= 0 else -1)], [py, qy + ny * 0.06 * (1 if off >= 0 else -1)], color=color, lw=0.35, zorder=14)
    ang = math.degrees(math.atan2(dy, dx))
    if ang > 90 or ang <= -90:
        ang += 180
    s = text if text is not None else ("%.2f" % L)
    g = 0.012 * (ax.get_ylim()[1] - ax.get_ylim()[0]) * tside
    r = math.radians(ang + 90)
    ax.text((a[0] + b[0]) / 2 + math.cos(r) * g, (a[1] + b[1]) / 2 + math.sin(r) * g, s, fontsize=fs, color=color,
            ha="center", va="center", rotation=ang, zorder=16)


def chain(ax, pts, off, fs=6.0, axis="h", base=0.0, labels=None):
    """Chain of dimensions along a horizontal (axis='h', pts = x values at y=base) or vertical line."""
    run = 0
    for i in range(len(pts) - 1):
        lab = None if labels is None else labels[i]
        seg = abs(pts[i + 1] - pts[i])
        if seg < 0.7:
            run += 1
            side = (-1.0 if run % 2 == 1 else 1.0) * (2.3 if seg < 0.2 else 1.0)
        else:
            run = 0
            side = 1.0
        if axis == "h":
            dim(ax, (pts[i], base), (pts[i + 1], base), off, lab, fs=fs, tside=side)
        else:
            dim(ax, (base, pts[i]), (base, pts[i + 1]), off, lab, fs=fs, tside=side)


def leader(ax, xy, xytext, s, fs=6.3, color=K, ha="left"):
    ax.annotate(s, xy, xytext, fontsize=fs, color=color, ha=ha, va="center", zorder=20,
                arrowprops=dict(arrowstyle="-", color=color, lw=0.45, shrinkA=1, shrinkB=0))


def rect(ax, x0, y0, x1, y1, fc="none", ec=K, lw=0.7, z=3, ls="-", alpha=1.0, hatch=None):
    ax.add_patch(Rectangle((min(x0, x1), min(y0, y1)), abs(x1 - x0), abs(y1 - y0), fc=fc, ec=ec, lw=lw, zorder=z, ls=ls, alpha=alpha, hatch=hatch))


def polar_box(c, az, r, tang, rad):
    """Plan corners (plot coords) of a box whose centre sits at azimuth/radius from c, long side tangential."""
    a = math.radians(az)
    ux, uy = math.cos(a), math.sin(a)          # radial (plot coords: north up)
    tx, ty = -uy, ux
    cx, cy = c[0] + ux * r, c[1] + uy * r
    return [(cx + sx * tx * tang / 2 + sr * ux * rad / 2, cy + sx * ty * tang / 2 + sr * uy * rad / 2)
            for sx, sr in ((-1, -1), (1, -1), (1, 1), (-1, 1))], (cx, cy)


def ppt(c, az, r):
    a = math.radians(az)
    return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


def north(ax, x, y, s=1.2, ang=90):
    a = math.radians(ang)
    ax.annotate("", (x + math.cos(a) * s, y + math.sin(a) * s), (x, y), arrowprops=dict(arrowstyle="-|>", color=K, lw=1.1))
    txt(ax, x + math.cos(a) * (s + 0.35), y + math.sin(a) * (s + 0.35), "N", fs=9, weight="bold")


def scalebar(ax, x, y, n=5):
    for i in range(n):
        rect(ax, x + i, y, x + i + 1, y + 0.12, fc=K if i % 2 == 0 else "white", lw=0.5)
    for i in range(n + 1):
        txt(ax, x + i, y - 0.28, str(i), fs=5.5)
    txt(ax, x + n + 0.45, y + 0.06, "m", fs=6)


def hatch_plan(ax, x, y, normal_az, label=None, lab_off=(0, 0)):
    """Hatch plate in plan: plate d2.10 as a bar across the port, clear opening 1.02 left open."""
    a = math.radians(normal_az)
    tx, ty = -math.sin(a), math.cos(a)
    R = P.RING["d_in"] / 2; h = P.HATCH["w"] / 2
    for s0, s1 in ((-R, -h), (h, R)):
        ax.plot([x + tx * s0, x + tx * s1], [y + ty * s0, y + ty * s1], color=HATCHC, lw=2.6, solid_capstyle="butt", zorder=12)
    ax.plot([x - tx * h, x + tx * h], [y - ty * h, y + ty * h], color=HATCHC, lw=0.7, ls=":", zorder=12)
    if label:
        txt(ax, x + lab_off[0], y + lab_off[1], label, fs=5.8, color=HATCHC, weight="bold", bg="white")


def w2p(x, z):
    """World (x, z) -> north-up plot coords."""
    return (x, -z)


# ------------------------------------------------------------------ G-01 general arrangement plan
def g01():
    fig, ax = new_sheet((15, 16.5), (-26.5, 7.5), (-7.5, 27.5), "전체 배치 평면도  General arrangement plan  (북쪽 위)", "G-01")
    Ac = w2p(*P.A["c"]); Dc = w2p(*P.D["c"]); Cc = w2p(*P.C["c"]); bx = P.B["x"]
    # berm, pits
    ax.add_patch(Wedge(Cc, P.BERM["r_toe"], P.BERM["az0"], P.BERM["az1"], width=P.BERM["r_toe"] - P.BERM["r0"], fc=REGO, ec=PIT, lw=0.5, alpha=0.75, zorder=1))
    ax.add_patch(Wedge(Cc, P.BERM["r_crest"], P.BERM["az0"], P.BERM["az1"], width=P.BERM["crest_w"], fc="#b8ad9a", ec=PIT, lw=0.4, zorder=1.1))
    txt(ax, Cc[0] - 6.3, Cc[1] + 6.4, "레골리스 성토 (방위 55°~305°)\n마루 높이 3.00, 마루 폭 0.60\n경사 1:1.5, 끝자락 R 9.05", fs=6.3, color="#5a5246")
    for az in (P.BERM["az0"], P.BERM["az1"]):
        a, b = ppt(Cc, az, P.BERM["r0"]), ppt(Cc, az, P.BERM["r_toe"])
        ax.plot([a[0], b[0]], [a[1], b[1]], color="#5a5246", lw=1.6, zorder=2)
    txt(ax, *ppt(Cc, 49, 7.6), "돌망태 옹벽", fs=5.6, color="#5a5246", rot=55)
    tw = P.PITS["B_trench_w"] / 2
    rect(ax, bx - tw, -P.ST["B-U ring S face"] - 0.2, bx + tw, -P.ST["EV ring face"], ec=PIT, ls="--", lw=0.6, z=1.5)
    txt(ax, bx - tw - 0.25, 17.6, "B 트렌치 폭 5.4 · 깊이 1.40 (바닥을 지면 높이에)", fs=5.8, color=PIT, rot=90)
    # A
    ax.add_patch(Circle(Ac, P.A["r_infl"], fc=INFL, ec=K, lw=1.0, zorder=3)); ax.add_patch(Circle(Ac, P.A["r_metal"], fc=HULL, ec=K, lw=0.8, zorder=3.1))
    ax.add_patch(Circle(Ac, P.A["r_core"], fc="none", ec=K, lw=0.5, ls="--", zorder=3.2))
    txt(ax, Ac[0] + 0.3, Ac[1] + 0.5, "A 코어 타워", fs=9, weight="bold"); txt(ax, Ac[0] + 0.3, Ac[1] - 0.35, "기존 모델\n금속 Ø4.40 / 인플 Ø6.50\n(0.00, 0.00)", fs=6)
    # D
    ax.add_patch(Circle(Dc, P.D["r_out"], fc=HULL, ec=K, lw=1.0, zorder=3)); ax.add_patch(Circle(Dc, P.D["r_in"], fc=FLOOR, ec=K, lw=0.4, zorder=3.1))
    txt(ax, Dc[0], Dc[1] + 0.45, "D 허브", fs=9, weight="bold"); txt(ax, Dc[0], Dc[1] - 0.4, "Ø4.40\n(%.2f, 0.00)" % P.D["c"][0], fs=6)
    # C
    ax.add_patch(Circle(Cc, P.C["r_out"], fc=INFL, ec=K, lw=1.0, zorder=3)); ax.add_patch(Circle(Cc, P.C["r_in"], fc=FLOOR, ec=K, lw=0.4, zorder=3.1))
    ax.add_patch(Circle(Cc, P.C["lobby_r"], fc="none", ec=K, lw=0.5, ls="--", zorder=3.2))
    txt(ax, Cc[0], Cc[1] + 2.2, "C 거주 모듈", fs=9, weight="bold"); txt(ax, Cc[0], Cc[1] - 2.3, "인플레이터블 Ø7.50, 2층\n(%.2f, 0.00)" % P.C["c"][0], fs=6)
    # B hull
    ro = P.B["r_out"]; rr = P.RING["d_out"] / 2
    def seg(zs_cone0, zs_cyl, zn_cyl, zn_cone1, name, sub):
        pts = [(bx - rr, -zs_cone0), (bx - ro, -zs_cyl), (bx - ro, -zn_cyl), (bx - rr, -zn_cone1), (bx + rr, -zn_cone1), (bx + ro, -zn_cyl), (bx + ro, -zs_cyl), (bx + rr, -zs_cone0)]
        ax.add_patch(Polygon(pts, closed=True, fc=HULL, ec=K, lw=1.0, zorder=3))
        txt(ax, bx, -(zs_cyl + zn_cyl) / 2 + 0.5, name, fs=9, weight="bold"); txt(ax, bx, -(zs_cyl + zn_cyl) / 2 - 0.45, sub, fs=6)
    S = P.ST
    seg(S["B-U cone S start"], S["B-U cyl S"], S["B-U cyl N"], S["B-U cone N end"], "B-U", "유틸리티 세그먼트\nØ4.40 × 8.90\n물류 · 전력 · ECLSS")
    seg(S["B-M cone S start"], S["B-M cyl S"], S["B-M cyl N"], S["B-M cone N end"], "B-M", "정비·EVA 세그먼트\nØ4.40 × 8.15\n공방 · 수트실 · 크루락")
    # rings + tunnels
    for name, x0, z0, x1, z1 in P.tunnels():
        r = P.TUNNEL["d_out"] / 2
        if abs(z1 - z0) < 1e-6:
            rect(ax, x0, -z0 - r, x1, -z0 + r, fc="#dfe3e8", lw=0.8, z=4)
            txt(ax, (x0 + x1) / 2, -z0 + r + 0.38, name, fs=6.2, weight="bold")
        else:
            rect(ax, x0 - r, -z0, x0 + r, -z1, fc="#dfe3e8", lw=0.8, z=4)
            txt(ax, x0 + r + 0.75, -(z0 + z1) / 2, name.split(" ")[0], fs=6.2, weight="bold")
    rg = P.RING["d_out"] / 2; L = P.RING["length"]
    ring_sites = [(-P.A["r_metal"] - L, 0.0, "x"), (P.D["c"][0] + P.D["r_out"], 0.0, "x"), (P.D["c"][0] - P.D["r_out"] - L, 0.0, "x"), (P.C["c"][0] + P.C["r_out"], 0.0, "x"),
                  (bx, -P.D["r_out"] - L, "z"), (bx, S["B-U ring S face"] - L, "z"), (bx, S["B-U cone N end"] - L, "z"), (bx, S["B-U ring N face"] - L, "z"), (bx, S["B-M cone N end"] - L, "z"),
                  (bx, P.D["r_out"], "z"), (bx, P.D["r_out"] + L + P.ROVER_STUB, "z")]
    for x, z, ax_ in ring_sites:
        if ax_ == "x":
            rect(ax, x, -z - rg, x + L, -z + rg, fc="#9aa3ad", lw=0.6, z=5)
        else:
            rect(ax, x - rg, -z, x + rg, -(z + L), fc="#9aa3ad", lw=0.6, z=5)
    labs = {"H-01": (0.0, 1.55), "H-02": (0.0, -1.55), "H-03": (0.0, -1.55), "H-04": (-1.9, 0.0), "H-05": (-1.9, 0.0), "H-06": (0.0, 1.55), "H-07": (1.9, 0.0),
            "H-08": (-1.9, 0.25), "H-09": (-1.9, -0.25), "H-10": (2.9, 0.0), "H-11": (1.9, 0.0), "H-12": (1.9, 0.0)}
    for hid, desc, x, z, az, kind in P.ports():
        hatch_plan(ax, x, -z, az, hid, labs[hid])
    # porch, externals
    pz = S["EV ring face"]
    rect(ax, bx - P.PORCH["width"] / 2, -pz, bx + P.PORCH["width"] / 2, -(pz - P.PORCH["length"]), fc="#eeeeee", ec=K, lw=0.6, hatch="++", z=2)
    txt(ax, bx, -(pz - P.PORCH["length"]) + 0.45, "EVA 포치 2.40 × 2.40 (지면 높이 격자판)", fs=6)
    for nm, x0, z0, x1, z1, y0, y1 in P.B_EXTERNAL:
        rect(ax, x0, -z0, x1, -z1, fc="#b5c7b0" if "tank" in nm else "#8c93b8", lw=0.5, z=6)
    txt(ax, bx - 3.45, 10.9, "고압 O₂ 탱크 ×2\n(외부)", fs=5.6, ha="right"); txt(ax, bx + 3.45, 10.9, "고압 N₂ 탱크 ×2\n(외부)", fs=5.6, ha="left")
    txt(ax, bx - 0.6, 5.4, "방열기 2장\n(지붕, 수직)", fs=5.2, rot=90, color="#3b4270")
    lt = P.SITE["ltv"]; rect(ax, lt[0] - 1.6, -lt[1] - 1.0, lt[0] + 1.6, -lt[1] + 1.0, fc="#c8c8d8", lw=0.5, z=2); txt(ax, lt[0], -lt[1], "LTV 주차", fs=6)
    txt(ax, -25.8, 24.9, "도면 범위 밖: 안테나 (12, −14) · 태양전지 타워 (−30, −45), (20, −45) · 착륙 패드 (150, 10) · 원자로 FSP (−60, −800)", fs=6, ha="left")
    # dims
    dim(ax, Dc, Ac, -5.2, "A–D 중심 6.40"); dim(ax, Cc, Dc, -5.2, "D–C 중심 7.95")
    dim(ax, (P.D["c"][0] + P.D["r_out"], 0), (-P.A["r_metal"], 0), -2.7, "선체 간격 2.00", fs=5.6)
    txt(ax, -3.2, -3.25, "(링 0.25 + 터널 1.50 + 링 0.25)", fs=5.2, color=DIM)
    xs = bx + 4.35
    zc = [S["D hull N"], S["B-U cone S start"], S["B-U cyl S"], S["B-U cyl N"], S["B-U cone N end"], S["B-M cone S start"], S["B-M cyl S"], S["B-M cyl N"], S["B-M cone N end"], S["EV ring face"]]
    chain(ax, [-z for z in zc], -0.0, axis="v", base=xs, fs=5.6)
    dim(ax, (xs + 1.9, -S["B-U cone S start"]), (xs + 1.9, -S["EV ring face"]), 0.0, "B 전체 17.80")
    dim(ax, (bx - ro, 26.3), (bx + ro, 26.3), 0, "Ø4.40", ext=False)
    dim(ax, (Cc[0] - P.C["r_out"], -5.6), (Cc[0] + P.C["r_out"], -5.6), 0, "Ø7.50", ext=False)
    for (x, y, s) in ((Dc[0], -2.9, ""),):
        pass
    txt(ax, -25.8, 26.6, "좌표계: x 동(+), z 남(+) → 도면 Y = −z. 기준 높이 y = 0 = 모든 지상층 바닥 윗면.\n포트·해치·터널 축 높이 y = 0.90. 주황색 = 해치판(H-01~H-12).", fs=6.5, ha="left", va="top")
    north(ax, 5.6, 23.5); scalebar(ax, -2.0, -6.6)
    save(fig, "G-01_general_arrangement_plan.png", "A: NASA Artemis Surface Habitat 참조 설계(기존 모델). B·C·D 배치와 치수는 본 프로젝트 설계안. 해치 규격 근거: NASA ICES-2025-294 (40 × 60 in).")


# ------------------------------------------------------------------ G-02 sections
def c_profile(side=1, outer=False, n=60):
    """Profile points (r, y) of the C shell from bottom cap to top cap. side unused."""
    pts = []
    t = P.C["shell_t"] if outer else 0.0
    a = P.C["r_in"] - P.C["cap_r"]
    b0 = -P.C["bottom"]; b1 = P.C["top"] - P.C["wall_top"]
    pts.append((0.0, P.C["bottom"] - t))
    for i in range(n + 1):
        th = math.pi / 2 * i / n            # from bottom cap edge to wall
        pts.append((P.C["cap_r"] + (a + t) * math.sin(th), -(b0 + t) * math.cos(th)))
    for i in range(n + 1):
        th = math.pi / 2 * i / n
        pts.append((P.C["cap_r"] + (a + t) * math.cos(th), P.C["wall_top"] + (b1 + t) * math.sin(th)))
    pts.append((0.0, P.C["top"] + t))
    return pts


def draw_hatch_elev_line(ax, x, y0=None):
    """Hatch plate seen edge-on in a section: plate from tunnel bottom to top with the opening left clear."""
    r = P.RING["d_in"] / 2; h = P.HATCH
    ax.plot([x, x], [P.PORT_H - r, h["sill"]], color=HATCHC, lw=2.4, zorder=12, solid_capstyle="butt")
    ax.plot([x, x], [h["sill"] + h["h"], P.PORT_H + r], color=HATCHC, lw=2.4, zorder=12, solid_capstyle="butt")


def g02():
    fig, (a1, a2) = plt.subplots(2, 1, figsize=(17, 13.5), gridspec_kw=dict(height_ratios=[1, 1]))
    fig.suptitle("G-02   종단면도  Longitudinal sections", fontsize=13, weight="bold", x=0.02, ha="left", y=0.985)
    for ax in (a1, a2):
        ax.set_aspect("equal"); ax.axis("off")
    # ---- (a) E-W section through z = 0, looking north
    ax = a1; ax.set_xlim(-25.5, 5.5); ax.set_ylim(-2.6, 9.6)
    txt(ax, -25.3, 9.2, "(a) 동서 단면 · z = 0 · 북쪽을 봄  (A – D – C)", fs=9, weight="bold", ha="left")
    ax.plot([-25.5, 5.5], [0, 0], color=REGO, lw=1.0, zorder=0); txt(ax, 4.6, -0.22, "지면 y=0", fs=5.8, color="#6b6355")
    # A (schematic outline of the existing tower)
    rect(ax, -P.A["r_metal"], -1.1, P.A["r_metal"], 2.6, fc=HULL, lw=1.0, z=3)
    pts = [(-P.A["r_infl"], 2.6), (-P.A["r_infl"], 7.0)] + [(-P.A["r_infl"] * math.cos(t), 7.0 + 0.8 * math.sin(t)) for t in [i * math.pi / 40 for i in range(41)]] + [(P.A["r_infl"], 7.0), (P.A["r_infl"], 2.6)]
    ax.add_patch(Polygon(pts, closed=True, fc=INFL, ec=K, lw=1.0, zorder=3))
    for y in P.A["decks"]:
        w = P.A["r_metal"] if y < 2.6 else P.A["r_infl"]
        ax.plot([-w + 0.1, w - 0.1], [y, y], color=K, lw=1.6, zorder=4)
    rect(ax, -P.A["r_core"], 0, P.A["r_core"], 7.8, ec=K, ls="--", lw=0.5, z=4)
    txt(ax, 0, 6.3, "A 코어 타워 (기존 모델, 외형만)", fs=7, weight="bold"); txt(ax, 0, 1.3, "L1", fs=7); txt(ax, 0, 3.9, "L2", fs=7); txt(ax, 2.3, 5.75, "L3", fs=7)
    txt(ax, 0, -0.6, "하부 구조 (지면 아래)", fs=5.6, color="#555555")
    # D
    dx = P.D["c"][0]; ro = P.D["r_out"]; ri = P.D["r_in"]
    body = [(dx - ro, -P.D["floor_t"]), (dx - ro, P.D["h_clear"] + P.D["ceil_t"])]
    top = [(dx - ro * math.cos(t), P.D["h_clear"] + P.D["ceil_t"] + P.D["head"] * math.sin(t)) for t in [i * math.pi / 40 for i in range(41)]]
    bot = [(dx + ro * math.cos(t), -P.D["floor_t"] - P.D["head"] * math.sin(t)) for t in [i * math.pi / 40 for i in range(41)]]
    ax.add_patch(Polygon(body + top + [(dx + ro, -P.D["floor_t"])] + bot, closed=True, fc=HULL, ec=K, lw=1.0, zorder=3))
    rect(ax, dx - ri, 0, dx + ri, P.D["h_clear"], fc=FLOOR, lw=0.5, z=3.5)
    ax.plot([dx - ri, dx + ri], [0, 0], color=K, lw=1.6, zorder=4)
    txt(ax, dx, 1.55, "D 허브", fs=8, weight="bold"); txt(ax, dx, 1.05, "천장 2.40", fs=6)
    # tunnels along x
    for name, x0, z0, x1, z1 in P.tunnels()[:2]:
        r = P.TUNNEL["d_out"] / 2; ri2 = P.TUNNEL["d_in"] / 2
        rect(ax, x0, P.PORT_H - r, x1, P.PORT_H + r, fc="#dfe3e8", lw=0.8, z=3)
        rect(ax, x0, 0, x1, P.PORT_H + ri2, fc=FLOOR, lw=0.4, z=3.4)
        ax.plot([x0, x1], [0, 0], color=K, lw=1.2, zorder=4)
        txt(ax, (x0 + x1) / 2, 2.35, name, fs=6.2, weight="bold")
    Lr = P.RING["length"]; rg = P.RING["d_out"] / 2
    for x in (-P.A["r_metal"] - Lr, dx + ro, dx - ro - Lr, P.C["c"][0] + P.C["r_out"]):
        rect(ax, x, P.PORT_H - rg, x + Lr, P.PORT_H + rg, fc="#9aa3ad", lw=0.6, z=5)
    for hid, desc, x, z, az, kind in P.ports():
        if abs(z) < 1e-6 and hid in ("H-01", "H-02", "H-03", "H-06"):
            draw_hatch_elev_line(ax, x); txt(ax, x, P.PORT_H + 1.55, hid, fs=5.6, color=HATCHC, weight="bold")
    # C
    cx = P.C["c"][0]
    outer = c_profile(outer=True); inner = c_profile()
    for sgn in (-1, 1):
        ax.add_patch(Polygon([(cx + sgn * r, y) for r, y in outer], closed=False, fc=INFL, ec=K, lw=1.0, zorder=3))
        ax.add_patch(Polygon([(cx + sgn * r, y) for r, y in inner], closed=False, fc=FLOOR, ec=K, lw=0.5, zorder=3.3))
    ax.plot([cx - P.C["r_in"], cx + P.C["r_in"]], [0, 0], color=K, lw=1.6, zorder=4)
    rect(ax, cx - P.C["r_in"], P.C["deck2"] - P.C["deck_t"], cx + P.C["r_in"], P.C["deck2"], fc="#bbbbbb", lw=0.6, z=4)
    lo = P.C_LADDER["opening"]; rect(ax, cx + lo[0], P.C["deck2"] - P.C["deck_t"] - 0.01, cx + lo[2], P.C["deck2"] + 0.01, fc=FLOOR, ec="none", z=4.1)
    for sgn in (-1, 1):
        ax.plot([cx + sgn * P.C["lobby_r"]] * 2, [0, P.C["clear1"]], color=K, lw=0.5, ls="--", zorder=4)
    rect(ax, cx + P.C_LADDER["x"] - 0.3, 0, cx + P.C_LADDER["x"] + 0.3, P.C["deck2"], fc="#f5d58a", lw=0.4, z=4.2); txt(ax, cx + P.C_LADDER["x"], 1.3, "사다리", fs=5.5, rot=90)
    # port throat east
    rect(ax, cx + P.C["r_in"] - 0.02, P.PORT_H - 1.05, cx + P.C["r_out"] + Lr, P.PORT_H + 1.05, fc=FLOOR, lw=0.5, z=4.3)
    ax.plot([cx + P.C["r_in"], cx + P.C["r_out"] + Lr], [0, 0], color=K, lw=1.2, zorder=4.4)
    # berm west
    b = P.BERM
    ax.add_patch(Polygon([(cx - b["r0"], 0), (cx - b["r0"], b["height"]), (cx - b["r_crest"], b["height"]), (cx - b["r_toe"], 0)], closed=True, fc=REGO, ec=PIT, lw=0.6, zorder=2))
    txt(ax, cx - 6.4, 1.0, "성토\n1:1.5", fs=6, color="#5a5246")
    # UWMS toilet (west), medical bed (east) on deck 2, bunk + canopy projected
    rect(ax, cx - 3.25, 0, cx - 2.65, 0.8, fc=EQ, lw=0.4, z=5); txt(ax, cx - 2.35, 1.5, "화장실\n(az 180°)", fs=5.5)
    rect(ax, cx + 2.175, P.C["deck2"], cx + 2.925, P.C["deck2"] + 0.8, fc=EQ, lw=0.4, z=5); txt(ax, cx + 2.5, P.C["deck2"] + 1.2, "의무 침대", fs=5.5)
    rect(ax, cx - 3.15, P.C["deck2"], cx - 2.55, P.C["deck2"] + 0.9, fc=EQ, lw=0.4, z=5); txt(ax, cx - 2.3, P.C["deck2"] + 1.3, "갤리 조리대", fs=5.5)
    rect(ax, cx + 2.345, 0, cx + 3.195, 0.5, ec="#555555", ls="--", lw=0.5, z=5); rect(ax, cx + 2.345, 2.25, cx + 3.195, 2.35, fc=WATER, ec="#555555", ls="--", lw=0.4, z=5)
    txt(ax, cx + 2.35, 1.35, "침상 0.50 +\n물 캐노피 0.10\n(투영, CQ)", fs=5.2, color="#444444")
    txt(ax, cx, 4.0, "C 거주 모듈  2층", fs=8, weight="bold"); txt(ax, cx + 0.3, 0.55, "1층 로비 Ø3.00", fs=6)
    rect(ax, cx - P.C["r_out"] - 0.02, 3.30, cx - P.C["r_in"] + 0.02, 3.90, fc=GLASS, lw=0.4, z=6); leader(ax, (cx - 3.55, 3.6), (cx - 6.3, 4.6), "창 1.00 × 0.60 (y 3.30~3.90, 투영)", fs=5.8, ha="right")
    # pits
    ax.plot([cx - 4.3, cx - 4.3, cx + 4.3, cx + 4.3], [0, -P.PITS["C_depth"], -P.PITS["C_depth"], 0], color=PIT, lw=0.6, ls="--"); txt(ax, cx, -1.75, "C 피트 깊이 1.50", fs=5.8, color=PIT)
    ax.plot([dx - 2.6, dx - 2.6, dx + 2.6, dx + 2.6], [0, -P.PITS["D_depth"], -P.PITS["D_depth"], 0], color=PIT, lw=0.6, ls="--"); txt(ax, dx, -1.1, "D 피트 0.85", fs=5.8, color=PIT)
    # heights
    xh = cx - 10.4
    for y, s in ((P.C["y_bottom_out"], "−1.40 외피 하단"), (0, "0.00 1층 바닥"), (P.C["clear1"], "2.40 1층 천장"), (P.C["deck2"], "2.60 2층 바닥"), (3.0, "3.00 성토 마루"), (P.C["wall_top"], "3.90 수직벽 상단"), (P.C["top"], "5.40 내부 정점"), (P.C["y_top_out"], "5.80 외피 정점")):
        ax.plot([xh + 2.6, cx - 3.9], [y, y], color=DIM, lw=0.3, ls=":"); txt(ax, xh + 2.5, y, s, fs=5.6, color=DIM, ha="right")
    dim(ax, (cx - P.C["r_out"], 7.1), (cx + P.C["r_out"], 7.1), 0, "Ø7.50 (내부 Ø6.70)", ext=False)
    dim(ax, (dx - ro, 4.0), (dx + ro, 4.0), 0, "Ø4.40", ext=False)
    dim(ax, (dx + ro + 0.9, P.D["y_bottom"]), (dx + ro + 0.9, P.D["y_top"]), -0.0, "3.90", fs=5.8)
    dim(ax, (-P.A["r_infl"], 8.6), (P.A["r_infl"], 8.6), 0, "Ø6.50", ext=False)
    dim(ax, (-4.2, -1.9), (0, -1.9), 0, "", ext=False); txt(ax, -3.2, -2.2, "A–D 6.40 · D–C 7.95 (중심 간)", fs=6, color=DIM)
    dim(ax, (-3.0, 0), (-3.0, P.PORT_H), 0.0, "0.90", fs=5.6)
    # ---- (b) N-S section through x = -6.40, looking west (north to the right)
    ax = a2; ax.set_xlim(-6.2, 26.0); ax.set_ylim(-2.6, 7.2)
    txt(ax, -6.0, 6.8, "(b) 남북 단면 · x = −6.40 · 서쪽을 봄  (로버 포트 – D – B-U – B-M – EVA 포치).  가로축 = 북쪽 거리(−z)", fs=9, weight="bold", ha="left")
    S = P.ST; Bq = P.B
    ax.plot([-6.2, 26], [0, 0], color=REGO, lw=1.0, zorder=0)
    # hub
    body = [(-ro, -P.D["floor_t"]), (-ro, P.D["h_clear"] + P.D["ceil_t"])]
    top = [(-ro * math.cos(t), P.D["h_clear"] + P.D["ceil_t"] + P.D["head"] * math.sin(t)) for t in [i * math.pi / 40 for i in range(41)]]
    bot = [(ro * math.cos(t), -P.D["floor_t"] - P.D["head"] * math.sin(t)) for t in [i * math.pi / 40 for i in range(41)]]
    ax.add_patch(Polygon(body + top + [(ro, -P.D["floor_t"])] + bot, closed=True, fc=HULL, ec=K, lw=1.0, zorder=3))
    rect(ax, -ri, 0, ri, P.D["h_clear"], fc=FLOOR, lw=0.5, z=3.5); ax.plot([-ri, ri], [0, 0], color=K, lw=1.6, zorder=4); txt(ax, 0, 1.5, "D 허브", fs=8, weight="bold")
    # tunnels (north and south stub)
    r = P.TUNNEL["d_out"] / 2; ri2 = P.TUNNEL["d_in"] / 2
    for u0, u1, nm in ((-S["D ring N face"], -S["B-U ring S face"], "T-DB"), (-(ro + Lr + P.ROVER_STUB), -(ro + Lr), "T-DS")):
        rect(ax, u0, P.PORT_H - r, u1, P.PORT_H + r, fc="#dfe3e8", lw=0.8, z=3); rect(ax, u0, 0, u1, P.PORT_H + ri2, fc=FLOOR, lw=0.4, z=3.4)
        ax.plot([u0, u1], [0, 0], color=K, lw=1.2, zorder=4); txt(ax, (u0 + u1) / 2, 2.35, nm, fs=6.2, weight="bold")
    for u in (ro, -S["B-U ring S face"], -S["B-U cone N end"], -S["B-U ring N face"], -S["B-M cone N end"], -ro - Lr, -(ro + Lr + P.ROVER_STUB) - Lr):
        rect(ax, u, P.PORT_H - rg, u + Lr, P.PORT_H + rg, fc="#9aa3ad", lw=0.6, z=5)
    # B segments
    ay = Bq["axis_y"]; Ro = Bq["r_out"]; Ri = Bq["r_in"]
    def bseg(c0, cy0, cy1, c1):
        u = [-c0, -cy0, -cy1, -c1]
        ax.add_patch(Polygon([(u[0], ay - rg), (u[1], ay - Ro), (u[2], ay - Ro), (u[3], ay - rg), (u[3], ay + rg), (u[2], ay + Ro), (u[1], ay + Ro), (u[0], ay + rg)], closed=True, fc=HULL, ec=K, lw=1.0, zorder=3))
        ax.add_patch(Polygon([(u[0], 0), (u[1], 0), (u[2], 0), (u[3], 0), (u[3], ay + 1.05), (u[2], ay + Ri), (u[1], ay + Ri), (u[0], ay + 1.05)], closed=True, fc=FLOOR, ec=K, lw=0.4, zorder=3.4))
        ax.add_patch(Polygon([(u[0], 0), (u[1], 0), (u[2], 0), (u[3], 0), (u[3], ay - 1.05), (u[2], ay - Ri), (u[1], ay - Ri), (u[0], ay - 1.05)], closed=True, fc="#e2e2e2", ec=K, lw=0.4, zorder=3.4))
        ax.plot([u[0], u[3]], [0, 0], color=K, lw=1.6, zorder=4)
    bseg(S["B-U cone S start"], S["B-U cyl S"], S["B-U cyl N"], S["B-U cone N end"]); bseg(S["B-M cone S start"], S["B-M cyl S"], S["B-M cyl N"], S["B-M cone N end"])
    for nm, zs, t, kind in P.B_PARTITIONS:
        u0, u1 = -zs, -zs + t
        rect(ax, u0, 0, u1, ay + Ri - 0.02, fc="#666666" if kind == "hatch" else "#aaaaaa", lw=0.3, z=5)
        if kind == "door":
            rect(ax, u0 - 0.01, 0, u1 + 0.01, P.B_DOOR["h"], fc=FLOOR, ec="none", z=5.1)
        else:
            rect(ax, u0 - 0.01, P.HATCH["sill"], u1 + 0.01, P.HATCH["sill"] + P.HATCH["h"], fc=FLOOR, ec="none", z=5.1)
    for name, room, x0, x1, y0, y1, zs, zn in P.b_equip_boxes():
        if x0 < P.B["x"]:            # west wall items are the ones seen looking west
            rect(ax, -zs, y0, -zn, y1, fc=EQ, lw=0.4, z=6)
    for rid, nm, zt, zs, zn in P.B_ROOMS:
        txt(ax, -(zs + zn) / 2, 2.82, f"{rid}", fs=7.5, weight="bold"); txt(ax, -(zs + zn) / 2, 2.56, nm.split(" (")[0], fs=5.4)
    ax.plot([-S["U1 S"], -S["U3 N"]], [Bq["ceil"], Bq["ceil"]], color="#555555", lw=0.4, ls="--"); ax.plot([-S["M1 S"], -S["M3 N"]], [Bq["ceil"], Bq["ceil"]], color="#555555", lw=0.4, ls="--"); txt(ax, -S["U3 N"] - 0.75, Bq["ceil"] - 0.13, "천장 패널 2.40", fs=5.0, color="#555555")
    for hid, desc, x, z, az, kind in P.ports():
        if abs(x - P.B["x"]) < 1e-6 and hid != "H-10":
            draw_hatch_elev_line(ax, -z); txt(ax, -z, P.PORT_H + 1.55, hid, fs=5.6, color=HATCHC, weight="bold")
    txt(ax, -S["M2 N"] + 0.05, 3.25, "H-10", fs=5.6, color=HATCHC, weight="bold")
    leader(ax, (-(S["B-U cone N end"] + S["B-M cone S start"]) / 2, 2.2), (-(S["B-U cone N end"] + S["B-M cone S start"]) / 2 + 0.2, 4.6), "세그먼트 결합부: 링–링 직결, 이중 해치 = 방화·소음 구획", fs=5.8, ha="center")
    # radiators, porch, trench
    rect(ax, -S["U1 S"] + 0.4, 3.15, -S["U3 N"] - 0.4, 5.15, fc="#8c93b8", lw=0.5, z=2, alpha=0.8); txt(ax, -(S["U1 S"] + S["U3 N"]) / 2, 4.15, "방열기 패널 7.9 × 2.0 (2장, 축 양쪽 0.6)", fs=6, color="white")
    pu = -S["EV ring face"]; rect(ax, pu, -0.08, pu + P.PORCH["length"], 0.0, fc="#999999", lw=0.5, z=3); txt(ax, pu + 1.2, 0.35, "EVA 포치", fs=6)
    ax.plot([-S["B-U ring S face"] + 0.2, -S["B-U ring S face"] + 0.2, pu, pu], [0, -P.PITS["B_depth"], -P.PITS["B_depth"], 0], color=PIT, lw=0.6, ls="--"); txt(ax, 12.5, -1.72, "B 트렌치 깊이 1.40 (선체 하단 y = −1.30)", fs=5.8, color=PIT)
    # dims
    zc = [S["D hull N"], S["B-U cone S start"], S["B-U cyl S"], S["U1 N"], S["U2 S"], S["U2 N"], S["U3 S"], S["U3 N"], S["B-U cone N end"], S["B-M cone S start"], S["B-M cyl S"], S["M1 N"], S["M2 S"], S["M2 N"], S["M3 S"], S["M3 N"], S["B-M cone N end"], S["EV ring face"]]
    chain(ax, [-z for z in zc], 0.0, axis="h", base=-2.15, fs=5.4)
    dim(ax, (-S["B-U cone S start"], 5.9), (-S["B-U cone N end"], 5.9), 0, "B-U 8.90", ext=False); dim(ax, (-S["B-M cone S start"], 5.9), (-S["B-M cone N end"], 5.9), 0, "B-M 8.15", ext=False)
    dim(ax, (23.3, Bq["y_bottom"]), (23.3, Bq["y_top"]), 0.0, "Ø4.40"); dim(ax, (24.3, 0), (24.3, ay + Ri), 0.0, "중앙 높이 3.00", fs=5.6); dim(ax, (25.2, 0), (25.2, ay), 0.0, "축 0.90", fs=5.6)
    fig.text(0.98, 0.985, "단위 m · tools/design/params.py 에서 생성 · 2026-11", ha="right", va="top", fontsize=7, color="#555555")
    save(fig, "G-02_longitudinal_sections.png", "모든 지상층 바닥 y = 0. B·D·C 는 트렌치/피트에 앉혀 바닥을 지면에 맞춘다 (A 모델도 바닥 아래로 약 1.1 m 내려가 있음).")


# ------------------------------------------------------------------ B-01 plan of B (north to the right, east down)
def b01():
    S = P.ST; Bq = P.B; bx = Bq["x"]
    fig, ax = new_sheet((19, 10.2), (0.4, 26.3), (-8.4, 4.6), "B 엔지니어링 모듈 평면도  (북쪽 → 오른쪽, 동쪽 ↓)   B-U 유틸리티 + B-M 정비·EVA", "B-01")
    U = lambda z: -z
    V = lambda x: -(x - bx)
    Ro = Bq["r_out"]; fh = Bq["floor_half"]; rg = P.RING["d_out"] / 2
    def seg(c0, cy0, cy1, c1):
        ax.add_patch(Polygon([(U(c0), -rg), (U(cy0), -Ro), (U(cy1), -Ro), (U(c1), -rg), (U(c1), rg), (U(cy1), Ro), (U(cy0), Ro), (U(c0), rg)], closed=True, fc=HULL, ec=K, lw=1.1, zorder=2))
        fl = Bq["floor_half"]; fr = P.TUNNEL["floor_w"] / 2
        ax.add_patch(Polygon([(U(c0), -fr), (U(cy0), -fl), (U(cy1), -fl), (U(c1), -fr), (U(c1), fr), (U(cy1), fl), (U(cy0), fl), (U(c0), fr)], closed=True, fc=FLOOR, ec=K, lw=0.5, zorder=2.5))
    seg(S["B-U cone S start"], S["B-U cyl S"], S["B-U cyl N"], S["B-U cone N end"]); seg(S["B-M cone S start"], S["B-M cyl S"], S["B-M cyl N"], S["B-M cone N end"])
    fills = {"U1": BUF, "U2": NOISY, "U3": NOISY, "M1": NOISY, "M2": NOISY, "M3": "#f2c9a0"}
    for rid, nm, zt, zs, zn in P.B_ROOMS:
        rect(ax, U(zs), -fh, U(zn), fh, fc=fills[rid], ec="none", z=2.6, alpha=0.75)
        txt(ax, (U(zs) + U(zn)) / 2, 0.22, rid, fs=11, weight="bold"); txt(ax, (U(zs) + U(zn)) / 2, -0.25, nm, fs=6.3)
        txt(ax, (U(zs) + U(zn)) / 2, -0.62, "%.2f × %.2f = %.1f m²" % (zs - zn, 2 * fh, (zs - zn) * 2 * fh), fs=5.6, color="#444444")
    for sgn in (-1, 1):
        ax.plot([U(S["U1 S"]), U(S["U3 N"])], [sgn * Bq["rack_face"]] * 2, color="#888888", lw=0.4, ls=":", zorder=3)
        ax.plot([U(S["M1 S"]), U(S["M3 N"])], [sgn * Bq["rack_face"]] * 2, color="#888888", lw=0.4, ls=":", zorder=3)
    for nm, zs, t, kind in P.B_PARTITIONS:
        u0, u1 = U(zs), U(zs) + t
        if kind == "door":
            rect(ax, u0, -fh, u1, -P.B_DOOR["w"] / 2, fc="#888888", lw=0.3, z=5); rect(ax, u0, P.B_DOOR["w"] / 2, u1, fh, fc="#888888", lw=0.3, z=5)
        else:
            rect(ax, u0, -fh, u1, -P.HATCH["w"] / 2, fc="#444444", lw=0.3, z=5); rect(ax, u0, P.HATCH["w"] / 2, u1, fh, fc="#444444", lw=0.3, z=5)
            txt(ax, u0 + 0.05, -2.75, "H-10 압력 격벽 0.10", fs=5.8, color=HATCHC, weight="bold")
    txt(ax, U(S["U1 N"]) + 0.03, 2.62, "P1", fs=5.6); txt(ax, U(S["U2 N"]) + 0.03, 2.62, "P2", fs=5.6); txt(ax, U(S["M1 N"]) + 0.03, 2.62, "P3", fs=5.6)
    # equipment with numbers
    legend = []
    for i, (name, room, x0, x1, y0, y1, zs, zn) in enumerate(P.b_equip_boxes(), start=1):
        rect(ax, U(zs), V(x0), U(zn), V(x1), fc=EQ, lw=0.5, z=6)
        txt(ax, (U(zs) + U(zn)) / 2, (V(x0) + V(x1)) / 2, str(i), fs=6.2, weight="bold")
        legend.append("%2d  %s   %.2f×%.2f×%.2f" % (i, name.split(" | ")[1], zs - zn, x1 - x0, y1 - y0))
    # rings, hatches, tunnel, hub
    Lr = P.RING["length"]
    for z in (S["B-U ring S face"], S["B-U cone N end"], S["B-U ring N face"], S["B-M cone N end"]):
        rect(ax, U(z), -rg, U(z) + Lr, rg, fc="#9aa3ad", lw=0.6, z=5)
    r = P.TUNNEL["d_out"] / 2
    rect(ax, U(S["D ring N face"]), -r, U(S["B-U ring S face"]), r, fc="#dfe3e8", lw=0.8, z=2); txt(ax, (U(S["D ring N face"]) + U(S["B-U ring S face"])) / 2, 0, "T-DB\n1.50", fs=6.2, weight="bold")
    rect(ax, U(S["D hull N"]), -rg, U(S["D ring N face"]), rg, fc="#9aa3ad", lw=0.6, z=5)
    ax.add_patch(Wedge((0, 0), P.D["r_out"], -80, 80, fc=HULL, ec=K, lw=1.0, zorder=1)); txt(ax, 1.25, 0, "D 허브", fs=8, weight="bold")
    for hid, desc, x, z, az, kind in P.ports():
        if abs(x - bx) < 1e-6 and z < -2.0 and hid != "H-10":
            u = U(z)
            for s0, s1 in ((-1.05, -0.51), (0.51, 1.05)):
                ax.plot([u, u], [s0, s1], color=HATCHC, lw=2.6, zorder=12, solid_capstyle="butt")
            txt(ax, u, 1.35, hid, fs=5.8, color=HATCHC, weight="bold", bg="white")
    # externals
    for nm, x0, z0, x1, z1, y0, y1 in P.B_EXTERNAL:
        if "tank" in nm:
            rect(ax, U(z0), V(x0), U(z1), V(x1), fc="#b5c7b0", lw=0.5, z=2)
    txt(ax, U(S["U3 S"]) + 1.7, 3.55, "고압 O₂ 탱크 Ø0.90 × 1.40 ×2 (외부, 서측)", fs=5.8); txt(ax, U(S["U3 S"]) + 1.7, -3.55, "고압 N₂ 탱크 ×2 (외부, 동측)", fs=5.8)
    pu = U(S["EV ring face"]); rect(ax, pu, -P.PORCH["width"] / 2, pu + P.PORCH["length"], P.PORCH["width"] / 2, fc="#eeeeee", lw=0.6, hatch="++", z=2); txt(ax, pu + 1.2, 0, "EVA 포치\n2.40 × 2.40", fs=6.2, bg="white")
    # dims
    zc = [S["B-U ring S face"], S["B-U cone S start"], S["B-U cyl S"], S["U1 N"], S["U2 S"], S["U2 N"], S["U3 S"], S["U3 N"], S["B-U cone N end"], S["B-U ring N face"], S["B-M cone S start"], S["B-M cyl S"], S["M1 N"], S["M2 S"], S["M2 N"], S["M3 S"], S["M3 N"], S["B-M cone N end"], S["EV ring face"]]
    chain(ax, [U(z) for z in zc], 0.0, axis="h", base=-4.3, fs=5.3)
    dim(ax, (U(S["B-U cone S start"]), -4.95), (U(S["B-U cone N end"]), -4.95), 0, "B-U 선체 8.90 (원통 7.70)", ext=False); dim(ax, (U(S["B-M cone S start"]), -4.95), (U(S["B-M cone N end"]), -4.95), 0, "B-M 선체 8.15 (원통 6.95)", ext=False)
    dim(ax, (25.0, -Ro), (25.0, Ro), 0, "외경 4.40"); dim(ax, (25.7, -fh), (25.7, fh), 0, "바닥 폭 3.79", fs=5.8)
    dim(ax, (U(S["U3 S"]) + 0.5, -1.127), (U(S["U3 S"]) + 0.5, 1.127), 0, "통로 2.25", fs=5.6, ext=False)
    dim(ax, (U(S["U3 S"]) + 0.10, 0.98), (U(S["U3 S"]) + 0.87, 0.98), 0, "0.77", fs=5.0, ext=False); dim(ax, (U(S["U3 S"]) + 0.90, 0.98), (U(S["U3 S"]) + 1.70, 0.98), 0, "피치 0.80", fs=5.0, ext=False)
    for i, s in enumerate(legend):
        col, row = divmod(i, 11)
        txt(ax, 3.9 + col * 6.2, -5.75 - row * 0.21, s, fs=5.6, ha="left")
    txt(ax, 3.9, 4.25, "장비 번호 = 길이(남북) × 깊이 × 높이.  장비 높이 ≤ 1.83 (팔레트 규격), 수트 스탠드만 2.00.", fs=5.8, ha="left")
    txt(ax, 3.9, 3.95, "칸막이 P1~P3: 두께 0.05, 개구 1.00 × 2.00 (미닫이). 점선 = 장비 전면선 ±1.05.", fs=5.8, ha="left")
    north(ax, 23.6, 4.0, s=1.0, ang=0)
    save(fig, "B-01_engineering_plan.png", "허브에서 멀어질수록 더럽고 시끄럽다: 물류 → 전력·열 → ECLSS ‖ 이중 해치 ‖ 공방 → 수트실(장비 락) → 크루락 → EVA. 수트실+크루락 구성은 ISS Quest 에어락(장비 락 + 크루 락) 선례.")


# ------------------------------------------------------------------ B-02 cross sections
def b_circle(ax, cx):
    Bq = P.B
    ax.add_patch(Circle((cx, Bq["axis_y"]), Bq["r_out"], fc=HULL, ec=K, lw=1.1, zorder=2)); ax.add_patch(Circle((cx, Bq["axis_y"]), Bq["r_in"], fc=FLOOR, ec=K, lw=0.5, zorder=2.2))
    fh = Bq["floor_half"]
    th0 = math.degrees(math.asin(Bq["axis_y"] / Bq["r_in"]))
    ax.add_patch(Wedge((cx, Bq["axis_y"]), Bq["r_in"], 180 + th0, 360 - th0, fc="#dcdcdc", ec="none", zorder=2.3))
    ax.add_patch(Polygon([(cx - fh, 0), (cx + fh, 0), (cx, Bq["axis_y"])], closed=True, fc=FLOOR, ec="none", zorder=2.25))
    ax.add_patch(Polygon([(cx - fh, 0), (cx + fh, 0), (cx + fh, -0.001), (cx - fh, -0.001)], closed=True, fc=K, ec=K, lw=1.8, zorder=4))
    rect(ax, cx - fh, -0.06, cx + fh, 0.0, fc="#999999", lw=0.4, z=4)
    ax.plot([cx - 2.6, cx + 2.6], [Bq["axis_y"]] * 2, color="#888888", lw=0.3, ls="-.", zorder=3)
    return fh


def b02():
    fig, ax = new_sheet((19, 8.6), (-3.4, 24.6), (-2.6, 5.9), "B 횡단면도  Cross sections  (북쪽을 봄 · 왼쪽 = 서)", "B-02")
    Bq = P.B; ay = Bq["axis_y"]
    # --- (a) U3 ECLSS
    cx = 0.0; fh = b_circle(ax, cx); txt(ax, cx, 5.45, "(a) U3 ECLSS 베이", fs=9, weight="bold")
    for sgn in (-1, 1):
        x0 = cx + sgn * fh; x1 = cx + sgn * (fh - 0.77)
        rect(ax, x0, 0, x1, 1.83, fc=EQ, lw=0.6, z=5); txt(ax, (x0 + x1) / 2, 1.35, "팔레트\n0.77", fs=5.4)
    rect(ax, cx - 0.95, -0.95, cx - 0.15, -0.15, fc=WATER, lw=0.4, z=5); rect(ax, cx + 0.15, -0.95, cx + 0.95, -0.15, fc=WATER, lw=0.4, z=5); txt(ax, cx, -0.55, "물탱크", fs=5.5, bg="white")
    txt(ax, cx, -1.09, "바닥 밑 1.20: 물탱크 250 L ×3 · 배관 · 케이블", fs=4.8)
    ax.plot([cx - 1.47, cx + 1.47], [Bq["ceil"]] * 2, color="#555555", lw=0.6, ls="--", zorder=5); txt(ax, cx, 2.52, "천장 패널 2.40 (폭 2.94)", fs=5.6)
    rect(ax, cx - 1.5, 1.95, cx - 1.05, 2.35, fc="#b9b9b9", lw=0.4, z=5); rect(ax, cx + 1.05, 1.95, cx + 1.5, 2.35, fc="#b9b9b9", lw=0.4, z=5); txt(ax, cx, 2.15, "덕트 · 케이블 트레이", fs=5.3)
    rect(ax, cx - 0.3, 2.86, cx + 0.3, 2.9, fc="#fff0a0", lw=0.3, z=5); txt(ax, cx, 2.72, "라인 조명", fs=5.2)
    for sgn in (-1, 1):
        rect(ax, cx + sgn * 0.55, 3.15, cx + sgn * 0.65, 5.15, fc="#8c93b8", lw=0.4, z=5)
        ax.add_patch(Circle((cx + sgn * 2.75, 0.65), 0.45, fc="#b5c7b0", ec=K, lw=0.5, zorder=5))
    txt(ax, cx + 1.25, 4.4, "방열기", fs=5.6); txt(ax, cx - 2.75, 0.65, "O₂", fs=5.6); txt(ax, cx + 2.75, 0.65, "N₂", fs=5.6)
    dim(ax, (cx - 2.2, -2.1), (cx + 2.2, -2.1), 0, "외경 4.40 / 내경 4.20", ext=False)
    dim(ax, (cx - fh, -0.0), (cx + fh, -0.0), -1.72, "바닥 폭 3.79", fs=5.8)
    dim(ax, (cx - 1.127, 1.0), (cx + 1.127, 1.0), 0, "통로 2.25", fs=5.8, ext=False)
    dim(ax, (cx - 3.3, 0), (cx - 3.3, ay), 0, "축 0.90", fs=5.4); dim(ax, (cx + 3.3, 0), (cx + 3.3, 3.0), 0, "중앙 3.00", fs=5.4)
    dim(ax, (cx - 0.95, 0), (cx - 0.95, 1.83), 0, "1.83", fs=5.4, ext=False)
    # --- (b) M2 suit room
    cx = 7.2; fh = b_circle(ax, cx); txt(ax, cx, 5.45, "(b) M2 수트실 (장비 락)", fs=9, weight="bold")
    rect(ax, cx - 1.75, 0, cx - 0.85, 2.0, fc=EQ, lw=0.6, z=5); txt(ax, cx - 1.3, 1.0, "수트\n스탠드\n0.90×0.90\n×2.00", fs=5.4)
    rect(ax, cx + fh - 0.60, 0, cx + fh, 1.83, fc=EQ, lw=0.6, z=5); txt(ax, cx + fh - 0.3, 0.95, "PLSS\n정비\n스테\n이션", fs=5.2)
    rect(ax, cx + fh - 0.80, 0, cx + fh - 0.60, 0.9, fc=EQ2, lw=0.4, z=4.9, ls="--"); txt(ax, cx + 0.75, 0.45, "작업대\n(뒤)", fs=5.0)
    ax.plot([cx - 1.25, cx + 1.25], [2.6, 2.6], color="#555555", lw=0.6, ls="--", zorder=5); txt(ax, cx, 2.72, "천장 2.60 (수트 착탈 높이)", fs=5.6)
    dim(ax, (cx - 0.85, 0.35), (cx + fh - 0.80, 0.35), 0, "1.95", fs=5.8, ext=False)
    dim(ax, (cx - 2.5, 0), (cx - 2.5, 2.0), 0, "2.00", fs=5.4)
    # --- (c) M3 crew lock, looking north at the EV hatch
    cx = 14.4; fh = b_circle(ax, cx); txt(ax, cx, 5.45, "(c) M3 크루락 → EV 해치 H-11 정면", fs=9, weight="bold")
    ax.add_patch(Circle((cx, ay), P.RING["d_out"] / 2, fc="#b5bcc5", ec=K, lw=0.7, zorder=5)); ax.add_patch(Circle((cx, ay), P.RING["d_in"] / 2, fc="#d5dae0", ec=K, lw=0.5, zorder=5.1))
    h = P.HATCH
    ax.add_patch(FancyBboxPatch((cx - h["coam_w"] / 2, ay - h["coam_h"] / 2), h["coam_w"], h["coam_h"], boxstyle="round,pad=0,rounding_size=0.32", fc=HATCHC, ec=K, lw=0.6, zorder=5.5))
    ax.add_patch(FancyBboxPatch((cx - h["w"] / 2, h["sill"]), h["w"], h["h"], boxstyle="round,pad=0,rounding_size=%.2f" % h["corner_r"], fc="#f7f7f7", ec=K, lw=0.7, zorder=5.6))
    for sgn in (-1, 1):
        rect(ax, cx + sgn * fh, 0.4, cx + sgn * (fh - 0.2), 1.6, fc=EQ, lw=0.4, z=6)
    txt(ax, cx - 1.45, 1.85, "수트 브러시·\n진공 스테이션", fs=5.2); rect(ax, cx - 1.6, -0.06, cx + 1.6, 0.0, fc="#555555", lw=0.3, hatch="||||", z=6); txt(ax, cx, -0.3, "격자 바닥 + 하향 흡입 플레넘 (먼지 제거)", fs=5.4)
    rect(ax, cx - 0.9, 2.75, cx + 0.9, 2.85, fc="#e07b22", lw=0.3, z=6); txt(ax, cx, 2.99, "에어샤워 노즐 바", fs=5.3)
    dim(ax, (cx - h["w"] / 2, 2.1), (cx + h["w"] / 2, 2.1), 0, "1.02", fs=5.8, ext=False); dim(ax, (cx + 0.78, h["sill"]), (cx + 0.78, h["sill"] + h["h"]), 0, "1.52", fs=5.8, ext=False)
    dim(ax, (cx - 0.9, 0), (cx - 0.9, h["sill"]), 0, "0.14", fs=5.2, ext=False)
    # --- (d) end view of a cone / port ring
    cx = 21.2; txt(ax, cx, 5.45, "(d) 포트 링 정면 (원뿔 끝 · 터널 접합면)", fs=9, weight="bold")
    ax.add_patch(Circle((cx, ay), Bq["r_out"], fc="none", ec="#999999", lw=0.6, ls="--", zorder=2)); txt(ax, cx + 1.75, 2.65, "선체 Ø4.40\n(원뿔 뒤)", fs=5.4, color="#666666")
    ax.add_patch(Circle((cx, ay), P.RING["d_out"] / 2, fc="#9aa3ad", ec=K, lw=0.9, zorder=3)); ax.add_patch(Circle((cx, ay), P.RING["d_in"] / 2, fc="#d5dae0", ec=K, lw=0.6, zorder=3.1))
    ax.add_patch(FancyBboxPatch((cx - h["coam_w"] / 2, ay - h["coam_h"] / 2), h["coam_w"], h["coam_h"], boxstyle="round,pad=0,rounding_size=0.32", fc=HATCHC, ec=K, lw=0.6, zorder=3.5))
    ax.add_patch(FancyBboxPatch((cx - h["w"] / 2, h["sill"]), h["w"], h["h"], boxstyle="round,pad=0,rounding_size=%.2f" % h["corner_r"], fc="#f7f7f7", ec=K, lw=0.7, zorder=3.6))
    fw = P.TUNNEL["floor_w"] / 2; ax.plot([cx - fw, cx + fw], [0, 0], color=K, lw=2.0, zorder=5)
    dim(ax, (cx - 1.2, -0.75), (cx + 1.2, -0.75), 0, "링 외경 2.40 / 내경 2.10", ext=False); dim(ax, (cx - fw, 0), (cx + fw, 0), -0.4, "바닥 1.08", fs=5.6)
    dim(ax, (cx + 1.6, 0), (cx + 1.6, ay), 0, "0.90", fs=5.6); dim(ax, (cx + 2.15, 0), (cx + 2.15, ay + 1.05), 0, "헤드룸 1.95", fs=5.6)
    dim(ax, (cx - h["coam_w"] / 2, 2.05), (cx + h["coam_w"] / 2, 2.05), 0, "코밍 1.30", fs=5.4, ext=False); dim(ax, (cx - 0.8, ay - 0.9), (cx - 0.8, ay + 0.9), 0, "1.80", fs=5.4, ext=False)
    ax.plot([-3.4, 24.6], [0, 0], color=REGO, lw=0.6, zorder=0)
    save(fig, "B-02_engineering_cross_sections.png", "바닥을 축 아래 0.90 에 두면 1.83 m 팔레트가 축 대칭으로 서서 양쪽 벽에 꼭 맞는다 (바닥 가장자리와 팔레트 상단의 선체 반폭이 같다). 해치 중심 = 축 높이.")


# ------------------------------------------------------------------ C plans
def c_base(ax, deck):
    Cq = P.C
    ax.add_patch(Circle((0, 0), Cq["r_out"], fc=INFL, ec=K, lw=1.2, zorder=2)); ax.add_patch(Circle((0, 0), Cq["r_in"], fc=FLOOR, ec=K, lw=0.6, zorder=2.1))


def c_sector_fill(ax, a0, a1, r0, r1, fc, z=2.3):
    ax.add_patch(Wedge((0, 0), r1, a0, a1, width=r1 - r0, fc=fc, ec="none", zorder=z))


def c01():
    Cq = P.C
    fig, ax = new_sheet((12.5, 12.2), (-6.4, 7.3), (-6.3, 6.6), "C 거주 모듈 1층 평면도 (y = 0)  ·  침실 4 + 완충 구획", "C-01")
    # berm
    ax.add_patch(Wedge((0, 0), 5.0, P.BERM["az0"], P.BERM["az1"], width=5.0 - P.BERM["r0"], fc=REGO, ec="none", alpha=0.6, zorder=1)); ax.add_patch(Wedge((0, 0), P.BERM["r_crest"], P.BERM["az0"], P.BERM["az1"], width=P.BERM["crest_w"], fc="#b8ad9a", ec=PIT, lw=0.4, zorder=1.1))
    txt(ax, *ppt((0, 0), 200, 4.78), "성토 (마루 R 3.95~4.55, 끝자락 R 9.05 까지)", fs=5.6, color="#5a5246", rot=-70)
    c_base(ax, 1)
    cols = {"crew_quarters": QUIET, "hygiene": BUF, "uwms": BUF, "corridor": "#f0f0f0"}
    r0, r1 = Cq["room_r0"], Cq["r_in"]
    for nm, typ, a0, a1 in P.C_DECK1:
        c_sector_fill(ax, a0, a1, r0, r1, cols[typ])
        am = (a0 + a1) / 2
        area = P.sector_area(r0, r1, a0, a1)
        rr = 2.05 if typ == "crew_quarters" else (2.55 if typ != "corridor" else 2.35)
        if typ == "crew_quarters":
            txt(ax, *ppt((0, 0), am, 1.98), "%s\n%.2f m²" % (nm, area), fs=6.3, weight="bold", bg="white")
        elif typ == "corridor":
            txt(ax, 2.45, 0.28, "진입부 Entry", fs=6.5, weight="bold"); txt(ax, 2.45, -0.05, "%.2f m²" % area, fs=5.6)
        else:
            txt(ax, *ppt((0, 0), am - 6.0, 2.42), "%s\n%.2f m²" % (nm.replace("Hygiene", "위생").replace("UWMS", "화장실"), area), fs=5.4, weight="bold")
        txt(ax, *ppt((0, 0), am, 3.56), "%.0f°" % (a1 - a0), fs=5.6, color=DIM)
    # partitions (radial) and lobby wall with doors
    bounds = sorted({a0 % 360 for _, _, a0, _ in P.C_DECK1})
    for az in bounds:
        a, b = ppt((0, 0), az, r0 - 0.05), ppt((0, 0), az, r1)
        ax.plot([a[0], b[0]], [a[1], b[1]], color=K, lw=1.6, zorder=5)
        ax.add_patch(Circle(ppt((0, 0), az, Cq["lobby_r"]), 0.05, fc=K, ec=K, zorder=6))
    for nm, typ, a0, a1 in P.C_DECK1:
        am = (a0 + a1) / 2
        w = {"crew_quarters": P.C_DOORS["CQ"], "hygiene": P.C_DOORS["Hygiene"], "uwms": P.C_DOORS["UWMS"], "corridor": 1.06}[typ]
        half = math.degrees(math.asin(w / 2 / r0))
        if typ == "corridor":
            continue
        for s0, s1 in ((a0, am - half), (am + half, a1)):
            ax.add_patch(Arc((0, 0), 2 * r0, 2 * r0, theta1=s0, theta2=s1, color=K, lw=1.6, zorder=5))
        ax.add_patch(Arc((0, 0), 2 * r0, 2 * r0, theta1=am - half, theta2=am + half, color="#2f7d32", lw=1.0, ls=":", zorder=5))
    # equipment
    legend = []
    k = 0
    for name, deck, az, r, tang, rad, hgt, y0 in P.C_EQUIP:
        if deck != 1:
            continue
        pts, c = polar_box((0, 0), az, r, tang, rad)
        canopy = "canopy" in name
        if canopy:
            ax.add_patch(Polygon(pts, closed=True, fc="none", ec=WATER, lw=1.0, ls="--", zorder=8)); continue
        k += 1
        ax.add_patch(Polygon(pts, closed=True, fc=EQ if "bunk" not in name else "#c9b59a", ec=K, lw=0.5, zorder=7))
        txt(ax, c[0], c[1], str(k), fs=5.8, weight="bold")
        legend.append("%2d  %s  (접선 %.2f × 반경 %.2f × 높이 %.2f)" % (k, name, tang, rad, hgt))
    # lobby + ladder
    ax.add_patch(Circle((0, 0), Cq["lobby_r"], fc="#fbfbfb", ec="#999999", lw=0.4, ls="--", zorder=3))
    L = P.C_LADDER
    rect(ax, L["x"] - L["width"] / 2, -L["z_foot"], L["x"] + L["width"] / 2, -L["z_top"], fc="#f5d58a", lw=0.6, z=6)
    for i in range(1, 6):
        yv = -L["z_foot"] + i * (L["z_foot"] - L["z_top"]) / 6
        ax.plot([L["x"] - 0.3, L["x"] + 0.3], [yv, yv], color=K, lw=0.4, zorder=6.1)
    lo = L["opening"]; rect(ax, lo[0], -lo[1], lo[2], -lo[3], ec="#aa7700", ls="--", lw=0.7, z=6.2)
    txt(ax, L["x"], -0.95, "사다리 70°\n폭 0.60 ↑", fs=5.4); txt(ax, 0.55, 0.45, "로비\nØ3.00", fs=7, weight="bold"); txt(ax, 0.55, -0.35, "7.07 m²", fs=5.6)
    ax.add_patch(Circle((L["landing1"][0], -L["landing1"][2]), 0.07, fc="#d33", ec="none", zorder=9)); txt(ax, L["landing1"][0] + 0.42, -L["landing1"][2] - 0.2, "랜딩", fs=5, color="#d33")
    # port throat east
    Lr = P.RING["length"]; rg = P.RING["d_out"] / 2; ri = P.RING["d_in"] / 2
    rect(ax, Cq["r_in"] - 0.03, -ri, Cq["r_out"] + Lr, ri, fc=FLOOR, lw=0.6, z=4); rect(ax, Cq["r_out"], -rg, Cq["r_out"] + Lr, rg, fc="#9aa3ad", lw=0.6, z=4.5)
    hatch_plan(ax, Cq["r_out"] + Lr, 0, 0.0, "H-06", (0.0, 1.5))
    rect(ax, Cq["r_out"] + Lr, -P.TUNNEL["d_out"] / 2, Cq["r_out"] + Lr + 1.5, P.TUNNEL["d_out"] / 2, fc="#dfe3e8", lw=0.8, z=3); txt(ax, Cq["r_out"] + Lr + 0.75, 0, "T-DC\n→ D 허브", fs=6.2, weight="bold")
    leader(ax, (3.6, -0.9), (4.6, -2.3), "강체 포트 프레임\n(소프트굿 관통부, 깊이 0.65)", fs=5.8)
    # dims
    dim(ax, (-Cq["r_out"], -4.75), (Cq["r_out"], -4.75), 0, "외경 7.50", ext=False); dim(ax, (-Cq["r_in"], -4.35), (Cq["r_in"], -4.35), 0, "내경 6.70 (외피 0.40)", ext=False, fs=5.8)
    dim(ax, ppt((0, 0), 13, Cq["room_r0"]), ppt((0, 0), 13, Cq["r_in"]), 0.0, "방 깊이 1.80", fs=5.4, ext=False)
    p_, c_ = polar_box((0, 0), 223, 2.77, 2.0, 0.85)
    dim(ax, p_[3], p_[2], 0.12, "2.00", fs=5.4, ext=False); dim(ax, p_[1], p_[2], -0.12, "0.85", fs=5.4, ext=False)
    for i, s in enumerate(legend):
        txt(ax, -6.3, -5.05 - i * 0.2 + 0.0, s, fs=5.2, ha="left") if i < 6 else txt(ax, 0.4, -5.05 - (i - 6) * 0.2, s, fs=5.2, ha="left")
    txt(ax, -6.3, 6.25, "굵은 선 = 방음 칸막이 0.08 · 초록 점선 = 미닫이문 (침실 0.70, 위생·화장실 0.65, 높이 1.95) · 검은 점 = 로비 기둥 Ø0.10 (R 1.50)\n파란 점선 = 침상 위 물 캐노피 2.00 × 0.85 × 0.10 (y 2.25~2.35, 170 L): 태양 입자 폭풍 때 각자 침실이 대피소", fs=6, ha="left", va="top")
    north(ax, 6.4, 5.0, s=0.8); scalebar(ax, 3.6, -6.0, n=3)
    save(fig, "C-01_habitation_deck1_plan.png", "침실 면적 4.62 m² ≥ NASA 최소(취침 1.82 + 스트레칭 1.40). 침실끼리 벽 비공유(Burke 외 2022 §VII 지적 반영). 침실=폭풍 대피소 + 물 재킷은 TransHab 선례(5.7 cm 물).")


def c02():
    Cq = P.C
    fig, ax = new_sheet((12.5, 12.2), (-6.4, 7.3), (-6.3, 6.6), "C 거주 모듈 2층 평면도 (y = 2.60)  ·  워드룸·갤리 / 라운지 / 온실 / 의무", "C-02")
    c_base(ax, 2)
    cols = {"Medical": QUIET, "Wardroom": "#fbe6c8", "Galley": "#f6d9b8", "Lounge": BUF, "Greenhouse": GREEN}
    kor = {"Medical": "의무실", "Wardroom": "워드룸", "Galley": "갤리", "Lounge": "라운지", "Greenhouse": "온실"}
    r0, r1 = Cq["lobby_r"], Cq["r_in"]
    for nm, typ, a0, a1 in P.C_DECK2:
        c_sector_fill(ax, a0, a1, r0, r1, cols[nm]); am = (a0 + a1) / 2
        rr = {"Medical": 1.95, "Wardroom": 3.05, "Galley": 2.2, "Lounge": 2.35, "Greenhouse": 2.0}[nm]
        aa = {"Medical": am + 14, "Wardroom": am + 35, "Galley": am + 8, "Lounge": am, "Greenhouse": am}[nm]
        txt(ax, *ppt((0, 0), aa, rr), "%s\n%.1f m²" % (kor[nm], P.sector_area(r0, r1, a0, a1)), fs=6.5, weight="bold")
    for az in (-45, 30):
        a, b = ppt((0, 0), az, r0), ppt((0, 0), az, r1)
        ax.plot([a[0], b[0]], [a[1], b[1]], color="#2f7d32", lw=1.0, ls=":", zorder=5)
    ax.add_patch(Arc((0, 0), 2 * r0 + 0.1, 2 * r0 + 0.1, theta1=-45, theta2=30, color="#2f7d32", lw=1.0, ls=":", zorder=5)); txt(ax, *ppt((0, 0), 36, 2.55), "커튼 레일", fs=5.4, color="#2f7d32", rot=30)
    # headroom contours
    for r, s in ((2.76, "헤드룸 2.40"), (3.20, "1.90")):
        ax.add_patch(Circle((0, 0), r, fc="none", ec="#8a8a8a", lw=0.5, ls=(0, (4, 3)), zorder=4)); txt(ax, *ppt((0, 0), 12, r + 0.0), s, fs=5.2, color="#555555", bg="white", rot=-78)
    txt(ax, *ppt((0, 0), 12, 3.36 + 0.14), "벽 1.30", fs=5.0, color="#555555", rot=-78)
    legend = []; k = 0
    for name, deck, az, r, tang, rad, hgt, y0 in P.C_EQUIP:
        if deck != 2:
            continue
        k += 1
        if "table" in name:
            c = ppt((0, 0), az, r); ax.add_patch(Circle(c, tang / 2, fc=EQ, ec=K, lw=0.5, zorder=7))
        else:
            pts, c = polar_box((0, 0), az, r, tang, rad); ax.add_patch(Polygon(pts, closed=True, fc=EQ, ec=K, lw=0.5, zorder=7))
        txt(ax, c[0], c[1], str(k), fs=5.8, weight="bold"); legend.append("%2d  %s  (%.2f × %.2f × %.2f)" % (k, name, tang, rad, hgt))
    for name, deck, a0, a1, ra, rb, hgt, y0 in P.C_ARCS:
        k += 1
        ax.add_patch(Wedge((0, 0), rb, a0, a1, width=rb - ra, fc=EQ2, ec=K, lw=0.5, zorder=7)); txt(ax, *ppt((0, 0), (a0 + a1) / 2, (ra + rb) / 2), str(k), fs=5.8, weight="bold")
        legend.append("%2d  %s  (방위 %.0f°~%.0f°, R %.2f~%.2f)" % (k, name, a0, a1, ra, rb))
    for nm, az, w, y0, y1 in P.C_WINDOWS:
        half = math.degrees(math.asin(w / 2 / Cq["r_out"]))
        ax.add_patch(Wedge((0, 0), Cq["r_out"] + 0.03, az - half, az + half, width=Cq["shell_t"] + 0.06, fc=GLASS, ec=K, lw=0.5, zorder=8))
        txt(ax, *ppt((0, 0), az, 4.35), "창 %s\n1.00 × 0.60, y 3.30~3.90" % nm, fs=5.6)
    ax.add_patch(Circle((0, 0), Cq["lobby_r"], fc="#fbfbfb", ec="#999999", lw=0.4, ls="--", zorder=3))
    L = P.C_LADDER; lo = L["opening"]
    rect(ax, lo[0], -lo[1], lo[2], -lo[3], fc="white", ec=K, lw=0.9, z=6); ax.plot([lo[0], lo[2]], [-lo[1], -lo[3]], color=K, lw=0.4, zorder=6.1); ax.plot([lo[0], lo[2]], [-lo[3], -lo[1]], color=K, lw=0.4, zorder=6.1)
    txt(ax, (lo[0] + lo[2]) / 2, 0.95, "사다리 개구\n1.00 × 1.40", fs=5.4); txt(ax, 0.6, -0.35, "로비\n천장 2.80", fs=6.5, weight="bold")
    ax.add_patch(Circle((L["landing2"][0], -L["landing2"][2]), 0.07, fc="#d33", ec="none", zorder=9)); txt(ax, L["landing2"][0] + 0.4, -L["landing2"][2] + 0.2, "랜딩", fs=5, color="#d33")
    dim(ax, (-Cq["r_out"], -4.75), (Cq["r_out"], -4.75), 0, "외경 7.50", ext=False)
    for i, s in enumerate(legend):
        txt(ax, -6.3, -5.05 - i * 0.2, s, fs=5.2, ha="left") if i < 6 else txt(ax, 0.4, -5.05 - (i - 6) * 0.2, s, fs=5.2, ha="left")
    txt(ax, -6.3, 6.25, "2층은 어깨 곡면 아래 다락형 공간: 벽에서 높이 1.30, R 3.20 에서 1.90, R 2.76 안쪽은 2.40 이상, 로비 2.80.\n키 큰 장비(1.80)는 바깥 모서리가 R 3.05 안쪽에 오게 배치. 벽쪽에는 벤치·조리대·소파(≤ 0.90).\n사다리 개구 위 천장에 들것 호이스트 레일 (환자 이송).", fs=6, ha="left", va="top")
    north(ax, 6.4, 5.0, s=0.8); scalebar(ax, 3.6, -6.0, n=3)
    save(fig, "C-02_habitation_deck2_plan.png", "의무실은 진입부(1층 동쪽) 바로 위: 어느 침실 위도 아니다. 환자 이송은 사다리 개구 + 호이스트 (알려진 타협점, 리뷰 대상). 북쪽 창은 지구 방향.")


def c03():
    Cq = P.C
    fig, ax = new_sheet((14.5, 9.6), (-10.6, 7.6), (-2.5, 7.2), "C 거주 모듈 단면도  ·  동서 단면 (북쪽을 봄, 왼쪽 = 서)", "C-03")
    ax.plot([-10.6, 7.6], [0, 0], color=REGO, lw=1.0, zorder=0)
    outer = c_profile(outer=True); inner = c_profile()
    for sgn in (-1, 1):
        ax.add_patch(Polygon([(sgn * r, y) for r, y in outer], closed=False, fc=INFL, ec=K, lw=1.2, zorder=3)); ax.add_patch(Polygon([(sgn * r, y) for r, y in inner], closed=False, fc=FLOOR, ec=K, lw=0.6, zorder=3.3))
    rect(ax, -Cq["cap_r"], Cq["top"], Cq["cap_r"], Cq["top"] + Cq["shell_t"], fc="#9aa3ad", lw=0.6, z=4); rect(ax, -Cq["cap_r"], Cq["bottom"] - Cq["shell_t"], Cq["cap_r"], Cq["bottom"], fc="#9aa3ad", lw=0.6, z=4)
    txt(ax, 0, Cq["top"] + 0.2, "강체 상부 캡 Ø3.00 (공조 유닛)", fs=5.8); txt(ax, 0, Cq["bottom"] - 0.2, "강체 하부 캡 Ø3.00", fs=5.8)
    rect(ax, -Cq["r_in"], -0.08, Cq["r_in"], 0, fc="#999999", lw=0.5, z=4.5); rect(ax, -Cq["r_in"], Cq["deck2"] - Cq["deck_t"], Cq["r_in"], Cq["deck2"], fc="#bdbdbd", lw=0.6, z=4.5)
    L = P.C_LADDER; lo = L["opening"]; rect(ax, lo[0], Cq["deck2"] - Cq["deck_t"] - 0.01, lo[2], Cq["deck2"] + 0.01, fc=FLOOR, ec="none", z=4.6)
    rect(ax, L["x"] - 0.3, 0, L["x"] + 0.3, Cq["deck2"] + 0.9, fc="#f5d58a", lw=0.5, z=5, alpha=0.9); txt(ax, L["x"], 1.3, "사다리", fs=5.6, rot=90)
    for sgn in (-1, 1):
        ax.plot([sgn * Cq["lobby_r"]] * 2, [0, Cq["clear1"]], color=K, lw=1.0, zorder=5); ax.plot([sgn * Cq["lobby_r"]] * 2, [Cq["deck2"], Cq["top"]], color="#999999", lw=0.4, ls="--", zorder=5)
    txt(ax, 0.55, 1.9, "로비", fs=7, weight="bold"); txt(ax, 0.55, 4.6, "2층 로비\n천장 2.80", fs=6.5)
    # underfloor
    txt(ax, 0, -0.55, "바닥 밑 (깊이 ≤ 1.00): 바닥 보, 물·공기 배관, 저소음 팬", fs=5.6)
    # east: entry + port; deck2 east: medical bed
    Lr = P.RING["length"]; ri = P.RING["d_in"] / 2; rg = P.RING["d_out"] / 2
    rect(ax, Cq["r_in"] - 0.02, P.PORT_H - ri, Cq["r_out"] + Lr, P.PORT_H + ri, fc=FLOOR, lw=0.6, z=5); ax.plot([Cq["r_in"], Cq["r_out"] + Lr], [0, 0], color=K, lw=1.4, zorder=5.2)
    rect(ax, Cq["r_out"], P.PORT_H - rg, Cq["r_out"] + Lr, P.PORT_H + rg, fc="#9aa3ad", lw=0.6, z=5.5); draw_hatch_elev_line(ax, Cq["r_out"] + Lr); txt(ax, Cq["r_out"] + Lr, 2.25, "H-06", fs=5.8, color=HATCHC, weight="bold")
    rect(ax, Cq["r_out"] + Lr, P.PORT_H - 1.15, Cq["r_out"] + Lr + 1.5, P.PORT_H + 1.15, fc="#dfe3e8", lw=0.8, z=3); txt(ax, Cq["r_out"] + Lr + 0.75, 0.9, "T-DC", fs=6.2, weight="bold")
    txt(ax, 2.45, 1.2, "진입부", fs=6.5, weight="bold")
    rect(ax, 2.175, Cq["deck2"], 2.925, Cq["deck2"] + 0.8, fc=EQ, lw=0.5, z=6); txt(ax, 2.55, Cq["deck2"] + 1.1, "의무 침대", fs=5.6); txt(ax, 2.3, 4.6, "의무실", fs=6.5, weight="bold")
    # west: UWMS, deck2 galley counter
    rect(ax, -3.25, 0, -2.65, 0.8, fc=EQ, lw=0.5, z=6); txt(ax, -2.45, 1.3, "화장실", fs=6.5, weight="bold")
    rect(ax, -3.15, Cq["deck2"], -2.55, Cq["deck2"] + 0.9, fc=EQ, lw=0.5, z=6); txt(ax, -2.5, 4.6, "갤리", fs=6.5, weight="bold")
    # projected bunk + canopy (both sides, dashed)
    for sgn in (-1, 1):
        x0, x1 = sorted((sgn * 2.345, sgn * 3.195))
        rect(ax, x0, 0, x1, 0.5, ec="#666666", ls="--", lw=0.5, z=6.5); rect(ax, x0, 2.25, x1, 2.35, fc=WATER, ec="#666666", ls="--", lw=0.4, z=6.5, alpha=0.8)
    leader(ax, (-2.8, 2.3), (-6.6, 2.05), "물 캐노피 0.10 (10 g/cm²)\n침상 바로 위, 천장 아래 (투영)", fs=5.8, ha="right")
    leader(ax, (-2.8, 0.25), (-6.6, 0.75), "침상 상면 0.50 (투영)", fs=5.8, ha="right")
    # window (projected), berm
    rect(ax, -Cq["r_out"] - 0.02, 3.30, -Cq["r_in"] + 0.02, 3.90, fc=GLASS, lw=0.5, z=7); leader(ax, (-3.55, 3.6), (-6.6, 4.25), "창 (투영) y 3.30~3.90\n성토 마루 3.00 위로 시야 확보", fs=5.8, ha="right")
    b = P.BERM
    ax.add_patch(Polygon([(-b["r0"], 0), (-b["r0"], b["height"]), (-b["r_crest"], b["height"]), (-b["r_toe"], 0)], closed=True, fc=REGO, ec=PIT, lw=0.7, zorder=2)); txt(ax, -6.2, 1.0, "레골리스 성토 1:1.5", fs=6.2, color="#5a5246")
    rect(ax, -b["r0"], 0, -Cq["r_out"], b["height"], fc="#a69c8a", lw=0.3, z=2.5); txt(ax, -3.85, 3.25, "옹벽 라이너 0.20", fs=5.0, rot=90)
    ax.plot([-4.4, -4.4, 4.4, 4.4], [0, -P.PITS["C_depth"], -P.PITS["C_depth"], 0], color=PIT, lw=0.6, ls="--"); txt(ax, 3.0, -1.72, "피트 깊이 1.50", fs=5.8, color=PIT)
    # dims
    xs = 5.9
    ys = [Cq["y_bottom_out"], Cq["bottom"], 0.0, Cq["clear1"], Cq["deck2"], Cq["wall_top"], Cq["top"], Cq["y_top_out"]]
    chain(ax, ys, 0.0, axis="v", base=xs, fs=5.6)
    for y, s in zip(ys, ("−1.40", "−1.00", "0.00  1층 바닥", "2.40  1층 천장", "2.60  2층 바닥", "3.90  수직벽 상단", "5.40  내부 정점", "5.80")):
        txt(ax, xs + 0.55, y, s, fs=5.6, color=DIM, ha="left")
    dim(ax, (-Cq["r_out"], 6.55), (Cq["r_out"], 6.55), 0, "외경 7.50", ext=False); dim(ax, (-Cq["r_in"], 6.2), (Cq["r_in"], 6.2), 0, "내경 6.70", ext=False, fs=5.8)
    dim(ax, (-Cq["cap_r"], -2.05), (Cq["cap_r"], -2.05), 0, "캡·로비 Ø3.00", ext=False, fs=5.8)
    dim(ax, (-b["r_toe"], -0.5), (-b["r_crest"], -0.5), 0, "4.50", fs=5.6, ext=False); dim(ax, (-b["r_crest"], -0.5), (-b["r0"], -0.5), 0, "0.60", fs=5.2, ext=False)
    dim(ax, (-9.6, 0), (-9.6, b["height"]), 0, "3.00", fs=5.6)
    dim(ax, (1.0, Cq["deck2"]), (1.0, Cq["top"]), 0, "2.80", fs=5.6, ext=False); dim(ax, (3.2, Cq["deck2"]), (3.2, Cq["deck2"] + P.c_headroom_deck2(3.2)), 0, "1.90", fs=5.4, ext=False)
    txt(ax, -10.4, 6.9, "외피 프로파일(회전체): 수직벽 R 3.35 (y 0~3.90) → 위 어깨 = 타원(가로 1.85, 세로 1.50) → 캡 R 1.50 (y 5.40).  아래 어깨 = 타원(가로 1.85, 세로 1.00) → 캡 R 1.50 (y −1.00).  외피 두께 0.40.", fs=6, ha="left")
    save(fig, "C-03_habitation_section.png", "외피 두께 0.40 m: TransHab 16 in(60겹 이상) 선례. 중앙 강체 캡/코어 + 주변 소프트굿 구성도 TransHab·NASA Surface Habitat 과 같은 방식. 측면 대형 포트는 실증되지 않은 가정(리뷰 대상).")


# ------------------------------------------------------------------ D-01 hub
def d01():
    Dq = P.D
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(16, 8.6), gridspec_kw=dict(width_ratios=[1.05, 1]))
    fig.suptitle("D-01   D 허브 평면도 · 단면도", fontsize=13, weight="bold", x=0.02, ha="left", y=0.985)
    fig.text(0.98, 0.985, "단위 m · tools/design/params.py 에서 생성 · 2026-11", ha="right", va="top", fontsize=7, color="#555555")
    for ax in (a1, a2):
        ax.set_aspect("equal"); ax.axis("off")
    ax = a1; ax.set_xlim(-5.2, 5.2); ax.set_ylim(-5.6, 4.6)
    txt(ax, -5.0, 4.4, "(a) 평면 (북쪽 위)", fs=9, weight="bold", ha="left")
    ax.add_patch(Circle((0, 0), Dq["r_out"], fc=HULL, ec=K, lw=1.2, zorder=2)); ax.add_patch(Circle((0, 0), Dq["r_in"], fc=FLOOR, ec=K, lw=0.6, zorder=2.1))
    Lr = P.RING["length"]; rg = P.RING["d_out"] / 2; ri = P.RING["d_in"] / 2
    names = {"E": "→ T-AD → A 코어", "N": "→ T-DB → B-U", "W": "→ T-DC → C 거주", "S": "→ 로버·물류 포트"}
    hid = {"E": "H-02", "N": "H-04", "W": "H-03", "S": "H-05"}
    for k_, az in Dq["ports"].items():
        a = math.radians(az); ux, uy = math.cos(a), math.sin(a); tx, ty = -uy, ux
        d0 = math.sqrt(Dq["r_in"] ** 2 - ri ** 2) - 0.02
        throat = [(ux * d0 + tx * s * ri, uy * d0 + ty * s * ri) for s in (-1, 1)] + [(ux * (Dq["r_out"] + Lr) + tx * s * ri, uy * (Dq["r_out"] + Lr) + ty * s * ri) for s in (1, -1)]
        ax.add_patch(Polygon(throat, closed=True, fc=FLOOR, ec=K, lw=0.5, zorder=3))
        ring = [(ux * Dq["r_out"] * 0.985 + tx * s * rg, uy * Dq["r_out"] * 0.985 + ty * s * rg) for s in (-1, 1)] + [(ux * (Dq["r_out"] + Lr) + tx * s * rg, uy * (Dq["r_out"] + Lr) + ty * s * rg) for s in (1, -1)]
        ax.add_patch(Polygon(ring, closed=True, fc="none", ec=K, lw=0.7, zorder=3.2))
        hatch_plan(ax, ux * (Dq["r_out"] + Lr), uy * (Dq["r_out"] + Lr), az)
        lx, ly = (ux * 3.55, 0.28) if k_ in ("E", "W") else (0.0, uy * 2.85)
        nx_, ny_ = (ux * 3.75, -0.22) if k_ in ("E", "W") else (0.0, uy * 3.2)
        txt(ax, lx, ly, hid[k_], fs=6.5, color=HATCHC, weight="bold"); txt(ax, nx_, ny_, names[k_], fs=6)
    for az in P.D_LEAF_PARK_AZ:
        ax.add_patch(Arc((0, 0), 2 * (Dq["r_in"] - 0.06), 2 * (Dq["r_in"] - 0.06), theta1=az - 15, theta2=az + 15, color=HATCHC, lw=2.0, ls=(0, (3, 2)), zorder=6))
    txt(ax, *ppt((0, 0), 35, 1.55), "열린 해치 문짝\n(벽에 붙여 보관)", fs=5.2, color=HATCHC)
    for i, (name, az, r, tang, rad, hgt, y0) in enumerate(P.D_EQUIP, start=1):
        pts, c = polar_box((0, 0), az, r, tang, rad); ax.add_patch(Polygon(pts, closed=True, fc=EQ, ec=K, lw=0.5, zorder=7)); txt(ax, c[0], c[1], str(i), fs=6, weight="bold")
        txt(ax, -5.0, -4.55 - (i - 1) * 0.22, "%d  %s  (%.2f × %.2f × %.2f, 바닥 +%.1f)" % (i, name, tang, rad, hgt, y0), fs=5.6, ha="left")
    ax.add_patch(Circle((0, 0), 1.2, fc="none", ec="#888888", lw=0.5, ls="--", zorder=4)); txt(ax, 0, 0.25, "D 허브", fs=10, weight="bold"); txt(ax, 0, -0.2, "바닥 13.9 m² · 회전 여유 Ø2.40", fs=6)
    dim(ax, (-Dq["r_out"], -3.85), (Dq["r_out"], -3.85), 0, "외경 4.40 / 내경 4.20", ext=False)
    dim(ax, (Dq["r_out"], -2.55), (Dq["r_out"] + Lr, -2.55), 0, "0.25", fs=5.4, ext=False)
    txt(ax, -5.0, 3.95, "사분면마다(반시계): 코밍 가장자리 20° → 문짝 보관 20°~50° → 로커 53°~67° → 다음 코밍 70°.", fs=6, ha="left")
    north(ax, 4.6, 2.9, s=0.7)
    # section
    ax = a2; ax.set_xlim(-4.6, 4.9); ax.set_ylim(-2.0, 4.6)
    txt(ax, -4.5, 4.35, "(b) 동서 단면 (북쪽을 봄)", fs=9, weight="bold", ha="left")
    ax.plot([-4.6, 4.9], [0, 0], color=REGO, lw=1.0, zorder=0)
    ro = Dq["r_out"]; rin = Dq["r_in"]
    body = [(-ro, -Dq["floor_t"]), (-ro, Dq["h_clear"] + Dq["ceil_t"])]
    top = [(-ro * math.cos(t), Dq["h_clear"] + Dq["ceil_t"] + Dq["head"] * math.sin(t)) for t in [i * math.pi / 50 for i in range(51)]]
    bot = [(ro * math.cos(t), -Dq["floor_t"] - Dq["head"] * math.sin(t)) for t in [i * math.pi / 50 for i in range(51)]]
    ax.add_patch(Polygon(body + top + [(ro, -Dq["floor_t"])] + bot, closed=True, fc=HULL, ec=K, lw=1.2, zorder=2))
    rect(ax, -rin, 0, rin, Dq["h_clear"], fc=FLOOR, lw=0.6, z=3); rect(ax, -rin, -Dq["floor_t"], rin, 0, fc="#999999", lw=0.5, z=3.5); rect(ax, -rin, Dq["h_clear"], rin, Dq["h_clear"] + Dq["ceil_t"], fc="#cfcfcf", lw=0.5, z=3.5)
    txt(ax, 0, 2.78, "천장 서비스층 + 상부 경판 (공조 디퓨저, 링 조명)", fs=5.6); txt(ax, 0, -0.42, "하부 경판 (배관·케이블 통로)", fs=5.6)
    for sgn in (-1, 1):
        x0 = sgn * (rin - 0.02); x1 = sgn * (ro + Lr)
        rect(ax, x0, P.PORT_H - ri, x1, P.PORT_H + ri, fc=FLOOR, lw=0.5, z=4); rect(ax, sgn * ro, P.PORT_H - rg, sgn * (ro + Lr), P.PORT_H + rg, fc="#9aa3ad", lw=0.6, z=4.5)
        draw_hatch_elev_line(ax, sgn * (ro + Lr)); ax.plot([x0, x1], [0, 0], color=K, lw=1.2, zorder=5)
    # north port seen in elevation
    h = P.HATCH
    ax.add_patch(Circle((0, P.PORT_H), ri, fc="#eef0f3", ec=K, lw=0.6, zorder=3.6))
    ax.add_patch(FancyBboxPatch((-h["coam_w"] / 2, P.PORT_H - h["coam_h"] / 2), h["coam_w"], h["coam_h"], boxstyle="round,pad=0,rounding_size=0.32", fc="#f0b27a", ec=K, lw=0.5, zorder=3.7))
    ax.add_patch(FancyBboxPatch((-h["w"] / 2, h["sill"]), h["w"], h["h"], boxstyle="round,pad=0,rounding_size=%.2f" % h["corner_r"], fc="#fbfbfb", ec=K, lw=0.6, zorder=3.8)); txt(ax, 0, 0.9, "북쪽 포트\nH-04", fs=6.5, color=HATCHC, weight="bold")
    ys = [Dq["y_bottom"], -Dq["floor_t"], 0, Dq["h_clear"], Dq["h_clear"] + Dq["ceil_t"], Dq["y_top"]]
    chain(ax, ys, 0.0, axis="v", base=3.25, fs=5.6)
    for y, s in zip(ys, ("−0.75", "−0.15", "0.00 바닥", "2.40 천장", "2.55", "3.15")):
        txt(ax, 3.8, y, s, fs=5.6, color=DIM, ha="left")
    dim(ax, (-ro, 3.75), (ro, 3.75), 0, "외경 4.40", ext=False); dim(ax, (-3.4, 0), (-3.4, P.PORT_H), 0, "포트 축 0.90", fs=5.6)
    ax.plot([-2.7, -2.7, 2.7, 2.7], [0, -P.PITS["D_depth"], -P.PITS["D_depth"], 0], color=PIT, lw=0.6, ls="--"); txt(ax, 0, -1.1, "피트 0.85", fs=5.8, color=PIT)
    save(fig, "D-01_hub_plan_section.png", "허브는 통로이자 압력 구획 노드: 해치 2개(허브 쪽 + 모듈 쪽)를 닫으면 어느 모듈이든 격리된다. 직경 4.40 은 A 하부·B 와 같은 금속 배럴 공통 규격.")


# ------------------------------------------------------------------ H-01 hatch, ring, tunnel
def h01():
    h = P.HATCH
    fig, (a1, a2, a3) = plt.subplots(1, 3, figsize=(18, 7.6), gridspec_kw=dict(width_ratios=[1, 1.35, 0.95]))
    fig.suptitle("H-01   공통 해치 H-1 · 포트 링 · 터널 상세", fontsize=13, weight="bold", x=0.02, ha="left", y=0.985)
    fig.text(0.98, 0.985, "단위 m · tools/design/params.py 에서 생성 · 2026-11", ha="right", va="top", fontsize=7, color="#555555")
    for ax in (a1, a2, a3):
        ax.set_aspect("equal"); ax.axis("off")
    # (a) elevation
    ax = a1; ax.set_xlim(-2.0, 2.4); ax.set_ylim(-0.9, 2.95)
    txt(ax, -1.95, 2.85, "(a) 해치판 정면 (모듈 안에서 봄)", fs=9, weight="bold", ha="left")
    ax.add_patch(Circle((0, P.PORT_H), P.RING["d_out"] / 2, fc="#9aa3ad", ec=K, lw=1.0, zorder=2)); ax.add_patch(Circle((0, P.PORT_H), P.RING["d_in"] / 2, fc="#d5dae0", ec=K, lw=0.7, zorder=2.1))
    ax.add_patch(FancyBboxPatch((-h["coam_w"] / 2, P.PORT_H - h["coam_h"] / 2), h["coam_w"], h["coam_h"], boxstyle="round,pad=0,rounding_size=0.32", fc="#f0b27a", ec=K, lw=0.8, zorder=3))
    ax.add_patch(FancyBboxPatch((-h["w"] / 2, h["sill"]), h["w"], h["h"], boxstyle="round,pad=0,rounding_size=%.2f" % h["corner_r"], fc="#fbfbfb", ec=K, lw=1.0, zorder=3.1))
    fw = P.TUNNEL["floor_w"] / 2; ax.plot([-1.6, 1.6], [0, 0], color=K, lw=1.8, zorder=4)
    ax.add_patch(Circle((0, 1.25), 0.10, fc=GLASS, ec=K, lw=0.5, zorder=5)); txt(ax, 0, 1.47, "관측창 Ø0.20 (문짝)", fs=5.4)
    ax.add_patch(Circle((0, 0.85), 0.16, fc="none", ec="#666666", lw=0.8, zorder=5)); txt(ax, 0, 0.6, "개폐 휠 Ø0.32", fs=5.4)
    ax.add_patch(Circle((0.38, 0.35), 0.035, fc="#666666", ec=K, lw=0.3, zorder=5)); txt(ax, 0.38, 0.24, "균압 밸브", fs=5.0)
    for yy in (0.45, 0.9, 1.35):
        rect(ax, -h["w"] / 2 - 0.1, yy - 0.06, -h["w"] / 2 - 0.02, yy + 0.06, fc="#555555", lw=0.3, z=5)
    txt(ax, -0.88, 1.62, "경첩 3\n(왼쪽)", fs=5.0)
    dim(ax, (-h["w"] / 2, h["sill"] + h["h"]), (h["w"] / 2, h["sill"] + h["h"]), 0.66, "유효 개구 1.02 (40 in)"); dim(ax, (h["w"] / 2, h["sill"]), (h["w"] / 2, h["sill"] + h["h"]), -1.25, "유효 개구 1.52 (60 in)")
    dim(ax, (-h["coam_w"] / 2, -0.0), (h["coam_w"] / 2, -0.0), -0.3, "코밍 외곽 1.30", fs=5.8); dim(ax, (-1.2, -0.0), (1.2, -0.0), -0.6, "링 외경 2.40 · 해치판 Ø2.10", fs=5.8)
    leader(ax, (0.2, h["sill"] / 2), (0.75, -0.42), "문턱 0.14", fs=5.4); dim(ax, (-1.55, 0), (-1.55, P.PORT_H), 0, "축 0.90", fs=5.6)
    leader(ax, (h["w"] / 2 - 0.06, h["sill"] + h["h"] - 0.06), (-1.9, 2.45), "모서리 R 0.20", fs=5.6); leader(ax, (-0.6, 1.72), (-1.9, 2.2), "코밍 높이 1.80", fs=5.6)
    # (b) longitudinal section through ring - tunnel - ring
    ax = a2; ax.set_xlim(-1.6, 3.6); ax.set_ylim(-0.9, 2.75)
    txt(ax, -1.55, 2.62, "(b) 포트–터널–포트 종단면 (선체 간격 2.00)", fs=9, weight="bold", ha="left")
    Lr = P.RING["length"]; T = P.TUNNEL["length"]; ro = P.TUNNEL["d_out"] / 2; ri = P.TUNNEL["d_in"] / 2; rg = P.RING["d_out"] / 2
    # hull walls (schematic, 0.10 thick) left and right
    for xw, sgn in ((0.0, -1), (2 * Lr + T, 1)):
        rect(ax, xw, P.PORT_H + rg, xw + sgn * 0.10, 2.45, fc=HULL, lw=0.8, z=3); rect(ax, xw, -0.75, xw + sgn * 0.10, P.PORT_H - rg, fc=HULL, lw=0.8, z=3)
        rect(ax, xw + sgn * 0.10, 0, xw + sgn * 1.4, -0.06, fc="#999999", lw=0.4, z=3)
    txt(ax, -0.85, 1.9, "모듈 1 내부", fs=7); txt(ax, 2 * Lr + T + 0.85, 1.9, "모듈 2 내부", fs=7)
    for x0 in (0.0, Lr + T):
        rect(ax, x0, P.PORT_H + ri, x0 + Lr, P.PORT_H + rg, fc="#9aa3ad", lw=0.6, z=4); rect(ax, x0, P.PORT_H - rg, x0 + Lr, P.PORT_H - ri, fc="#9aa3ad", lw=0.6, z=4)
    rect(ax, Lr, P.PORT_H + ri, Lr + T, P.PORT_H + ro, fc="#dfe3e8", lw=0.6, z=4); rect(ax, Lr, P.PORT_H - ro, Lr + T, P.PORT_H - ri, fc="#dfe3e8", lw=0.6, z=4)
    for i in range(6):
        xb = Lr + 0.03 + i * 0.05
        ax.plot([xb, xb], [P.PORT_H + ri, P.PORT_H + ro + 0.05], color=K, lw=0.5, zorder=5); ax.plot([xb, xb], [P.PORT_H - ro - 0.05, P.PORT_H - ri], color=K, lw=0.5, zorder=5)
    leader(ax, (Lr + 0.15, P.PORT_H + ro + 0.05), (0.75, 2.45), "벨로즈 0.30 (정렬·열팽창 흡수)", fs=5.6)
    rect(ax, Lr, -0.05, Lr + T, 0.0, fc="#777777", lw=0.4, z=5); txt(ax, Lr + T / 2, -0.17, "평바닥 인서트 폭 1.08", fs=5.6)
    for xp, sgn in ((Lr, -1), (Lr + T, 1)):          # hatch plates at ring outer faces, leaf open into module
        rect(ax, xp, P.PORT_H - ri, xp + sgn * 0.05, h["sill"], fc=HATCHC, lw=0.4, z=6); rect(ax, xp, h["sill"] + h["h"], xp + sgn * 0.05, P.PORT_H + ri, fc=HATCHC, lw=0.4, z=6)
        rect(ax, xp + sgn * 0.05, h["sill"] - 0.05, xp + sgn * (0.05 + h["depth"]), h["sill"], fc="#f0b27a", lw=0.4, z=6); rect(ax, xp + sgn * 0.05, h["sill"] + h["h"], xp + sgn * (0.05 + h["depth"]), h["sill"] + h["h"] + 0.05, fc="#f0b27a", lw=0.4, z=6)
    rect(ax, -0.95, 0.10, -0.95 - h["leaf_t"], 0.10 + h["leaf_h"], fc="#e9c9a0", lw=0.5, z=6, ls="--"); txt(ax, -1.25, 0.9, "열린 문짝\n1.10 × 1.60 × 0.06\n(모듈 안쪽으로)", fs=5.2)
    txt(ax, Lr + T / 2, 1.25, "터널 (전실)\n평소 양쪽 해치 열림", fs=6.5)
    dim(ax, (0, -0.0), (Lr, -0.0), -0.45, "링 0.25", fs=5.6); dim(ax, (Lr, -0.0), (Lr + T, -0.0), -0.45, "터널 1.50", fs=5.8); dim(ax, (Lr + T, -0.0), (2 * Lr + T, -0.0), -0.45, "링 0.25", fs=5.6)
    dim(ax, (0, -0.0), (2 * Lr + T, -0.0), -0.72, "선체–선체 2.00")
    dim(ax, (3.25, 0), (3.25, P.PORT_H + ri), 0, "헤드룸 1.95", fs=5.6); dim(ax, (2.9, h["sill"]), (2.9, h["sill"] + h["h"]), 0, "1.52", fs=5.6)
    dim(ax, (Lr + 0.05, 2.25), (Lr + 0.05 + h["depth"], 2.25), 0, "틀 깊이 0.15 (6 in)", fs=5.0, ext=False)
    # (c) tunnel cross-section with a 1.80 m person
    ax = a3; ax.set_xlim(-1.9, 2.1); ax.set_ylim(-0.9, 2.75)
    txt(ax, -1.85, 2.62, "(c) 터널 횡단면", fs=9, weight="bold", ha="left")
    ax.add_patch(Circle((0, P.PORT_H), ro, fc="#dfe3e8", ec=K, lw=1.0, zorder=2)); ax.add_patch(Circle((0, P.PORT_H), ri, fc=FLOOR, ec=K, lw=0.6, zorder=2.1))
    th0 = math.degrees(math.asin(P.PORT_H / ri)); ax.add_patch(Wedge((0, P.PORT_H), ri, 180 + th0, 360 - th0, fc="#d0d0d0", ec="none", zorder=2.2))
    ax.add_patch(Polygon([(-fw, 0), (fw, 0), (0, P.PORT_H)], closed=True, fc=FLOOR, ec="none", zorder=2.15)); ax.plot([-fw, fw], [0, 0], color=K, lw=2.0, zorder=4)
    ax.add_patch(FancyBboxPatch((-h["w"] / 2, h["sill"]), h["w"], h["h"], boxstyle="round,pad=0,rounding_size=%.2f" % h["corner_r"], fc="none", ec=HATCHC, lw=1.0, ls="--", zorder=5)); txt(ax, 0.0, 1.78, "해치 개구 (뒤)", fs=5.2, color=HATCHC)
    # person 1.80
    ax.add_patch(Circle((0, 1.68), 0.12, fc="#bbbbbb", ec=K, lw=0.5, zorder=6)); rect(ax, -0.22, 0.85, 0.22, 1.55, fc="#bbbbbb", lw=0.5, z=6); rect(ax, -0.2, 0.0, -0.03, 0.85, fc="#bbbbbb", lw=0.5, z=6); rect(ax, 0.03, 0.0, 0.2, 0.85, fc="#bbbbbb", lw=0.5, z=6)
    txt(ax, 0.62, 1.05, "1.80 m\n(서서 통과,\n해치에서 숙임)", fs=5.2)
    dim(ax, (-ri, -0.0), (ri, -0.0), -0.45, "내경 2.10 / 외경 2.30", fs=5.8); dim(ax, (-fw, 0), (fw, 0), -0.18, "바닥 1.08", fs=5.6)
    dim(ax, (1.45, 0), (1.45, P.PORT_H + ri), 0, "1.95", fs=5.6); dim(ax, (-1.5, 0), (-1.5, P.PORT_H), 0, "0.90", fs=5.6)
    save(fig, "H-01_hatch_ring_tunnel.png", "유효 개구 40 × 60 in, 틀 깊이 6 in: NASA xEMU 해치 목업(ICES-2025-294, EHP-10028 요구) 값. 문턱·문짝·링·터널 치수는 본 설계안. 해치는 자기 모듈 안쪽으로 열려 모듈 압력이 문짝을 눌러 닫는다.")


if __name__ == "__main__":
    only = sys.argv[1:]
    for fn in (g01, g02, b01, b02, c01, c02, c03, d01, h01):
        if not only or fn.__name__ in only:
            fn()
