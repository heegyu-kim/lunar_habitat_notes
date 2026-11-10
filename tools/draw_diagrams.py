# -*- coding: utf-8 -*-
"""Draws the base-camp planning diagrams into docs/diagrams/ (site plan, floor plans, sections, zoning).
Run:  python tools/draw_diagrams.py
Dimensions follow docs/MODELING_GUIDE.md (NASA Surface Habitat reference, HIDH minimums)."""
import math, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Rectangle, Polygon, Wedge, FancyArrowPatch, Arc

matplotlib.rcParams["font.family"] = ["Malgun Gothic", "NanumGothic", "Arial"]
matplotlib.rcParams["axes.unicode_minus"] = False

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "diagrams_v1_superseded")  # superseded by tools/draw_design.py
os.makedirs(OUT, exist_ok=True)

C_METAL = "#8e949c"; C_INFL = "#d9cfb8"; C_FLOOR = "#e9e9e9"; C_WALL = "#404040"
C_QUIET = "#9bb3e6"; C_BUFFER = "#cfd8dc"; C_NOISY = "#f0b27a"; C_EQUIP = "#5d6d9e"; C_WATER = "#6aa3d6"
C_REGO = "#b9b0a2"; C_DIM = "#c0392b"; C_GLASS = "#9ad0f5"


def dim(ax, p1, p2, text, offset=0.0, side="h", fs=7, color=C_DIM):
    """Dimension line between p1 and p2 with ticks; offset moves it perpendicular."""
    x1, y1 = p1; x2, y2 = p2
    if side == "h":
        y = y1 + offset
        ax.annotate("", (x1, y), (x2, y), arrowprops=dict(arrowstyle="<->", color=color, lw=0.8, shrinkA=0, shrinkB=0))
        ax.plot([x1, x1], [y1, y], color=color, lw=0.5, ls=":")
        ax.plot([x2, x2], [y2, y], color=color, lw=0.5, ls=":")
        ax.text((x1 + x2) / 2, y, text, ha="center", va="bottom", fontsize=fs, color=color)
    else:
        x = x1 + offset
        ax.annotate("", (x, y1), (x, y2), arrowprops=dict(arrowstyle="<->", color=color, lw=0.8, shrinkA=0, shrinkB=0))
        ax.plot([x1, x], [y1, y1], color=color, lw=0.5, ls=":")
        ax.plot([x2, x], [y2, y2], color=color, lw=0.5, ls=":")
        ax.text(x, (y1 + y2) / 2, text, ha="left", va="center", fontsize=fs, color=color, rotation=90)


def label(ax, x, y, text, fs=7, color="black", ha="center", va="center", weight="normal", bg=None, rotation=0):
    kw = dict(ha=ha, va=va, fontsize=fs, color=color, weight=weight, rotation=rotation)
    if bg:
        kw["bbox"] = dict(boxstyle="round,pad=0.2", fc=bg, ec="none", alpha=0.9)
    ax.text(x, y, text, **kw)


def ring(ax, cx, cy, r_out, r_in, fc, ec=C_WALL, lw=1.0, z=1):
    ax.add_patch(Circle((cx, cy), r_out, fc=fc, ec=ec, lw=lw, zorder=z))
    ax.add_patch(Circle((cx, cy), r_in, fc=C_FLOOR, ec=ec, lw=lw, zorder=z + 0.1))


def box(ax, x, y, w, h, fc, ec=C_WALL, lw=0.8, z=2, angle=0.0, text=None, fs=5.5, tc="white"):
    p = Rectangle((x, y), w, h, fc=fc, ec=ec, lw=lw, zorder=z, angle=angle, rotation_point="center")
    ax.add_patch(p)
    if text:
        label(ax, x + w / 2, y + h / 2, text, fs=fs, color=tc)
    return p


def north(ax, x, y, s=2.0):
    ax.annotate("", (x, y + s), (x, y), arrowprops=dict(arrowstyle="-|>", color="black", lw=1.2))
    label(ax, x, y + s + 0.4, "N", fs=9, weight="bold")


def scalebar(ax, x, y, length, text):
    ax.plot([x, x + length], [y, y], color="black", lw=2)
    ax.plot([x, x], [y - 0.2, y + 0.2], color="black", lw=1)
    ax.plot([x + length, x + length], [y - 0.2, y + 0.2], color="black", lw=1)
    label(ax, x + length / 2, y - 0.9, text, fs=7)


def finish(fig, name, title, note=""):
    fig.suptitle(title, fontsize=13, weight="bold", y=0.985)
    if note:
        fig.text(0.5, 0.01, note, ha="center", fontsize=7, color="#555555")
    path = os.path.join(OUT, name)
    fig.savefig(path, dpi=170, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("wrote", path)


# ---------------------------------------------------------------- 1. site plan
def site_plan():
    fig, ax = plt.subplots(figsize=(12, 9))
    ax.set_aspect("equal"); ax.axis("off")
    # Berm around C
    ax.add_patch(Circle((-15, 0), 10.0, fc=C_REGO, ec="none", alpha=0.6, zorder=0))
    ax.add_patch(Circle((-15, 0), 4.2, fc="white", ec="none", zorder=0.5))
    label(ax, -15, -8.3, "레골리스 성토 Regolith berm\nH 3.5 m, 두께 2~3 m", fs=6.5, color="#5c554a")
    # Modules
    ring(ax, 0, 0, 3.25, 3.0, C_INFL); label(ax, 0, 0.6, "A 코어 타워\nCore tower", fs=8, weight="bold"); label(ax, 0, -4.3, "Ø6.5 m (하부 금속 Ø4.4)\n3층 0 / 2.6 / 5.2", fs=6)
    ring(ax, -7.5, 0, 2.0, 1.85, C_METAL); label(ax, -7.5, 0.4, "D 허브\nHub", fs=8, weight="bold"); label(ax, -7.5, -1.3, "Ø4.0 m", fs=6)
    ring(ax, -15, 0, 3.75, 3.6, C_INFL); label(ax, -15, 0.6, "C 거주 모듈\nHabitation", fs=8, weight="bold"); label(ax, -15, -4.8, "Ø7.5 m, 2층 0 / 2.6 + 돔", fs=6)
    box(ax, -15.5, 9.8, 16, 4.4, C_METAL, text=None)
    label(ax, -7.5, 12.6, "B 엔지니어링 모듈  Engineering", fs=8, weight="bold", color="white")
    label(ax, -7.5, 11.3, "Ø4.4 × 16 m (수평 실린더), 바닥 폭 3.3~3.8 m", fs=6, color="white")
    # Tunnels (inner 1.4 x 2.0)
    box(ax, -5.5, -0.8, 2.2, 1.6, C_FLOOR); box(ax, -11.3, -0.8, 1.8, 1.6, C_FLOOR); box(ax, -8.3, 2.0, 1.6, 7.8, C_FLOOR)
    box(ax, -8.3, -3.3, 1.6, 1.3, C_FLOOR); label(ax, -7.5, -4.3, "가압 로버 도킹\nPressurised rover port", fs=6)
    label(ax, -4.4, 2.0, "터널 2.2 m", fs=6); label(ax, -10.4, 2.0, "터널 1.8 m", fs=6); label(ax, -9.6, 6.0, "터널 7.8 m\n내부 1.4 × 2.0", fs=6, ha="right")
    # Hatches
    for (x, y) in [(-3.3, 0), (-5.5, 0), (-9.5, 0), (-11.3, 0), (-7.5, 2.0), (-7.5, 9.8), (0.5, 12.0)]:
        ax.add_patch(Circle((x, y), 0.35, fc="#e67e22", ec="none", zorder=5))
    label(ax, 1.6, 12.9, "EVA 해치 → 외부", fs=6, ha="left")
    # Exterior props
    box(ax, 3.4, 11.0, 3.2, 2.0, "#3b3f5c", text="LTV", tc="white")
    for x in (-25, 10):
        box(ax, x - 3, 49.5, 6, 0.6, "#1f2a5a"); label(ax, x, 51.5, "수직 태양전지 타워\nSolar tower H 12 m", fs=6)
    ax.add_patch(Circle((12, 20), 1.3, fc=C_METAL, ec=C_WALL)); label(ax, 12, 22.3, "안테나", fs=6)
    ax.annotate("착륙선 Lander  150 m →", (22, 2), (10, 2), fontsize=7, arrowprops=dict(arrowstyle="->"))
    ax.annotate("원자로 FSP  600~1000 m ↑ (성토 뒤, 케이블)", (-7.5, 57), (-7.5, 53.5), fontsize=7, ha="center", arrowprops=dict(arrowstyle="->"))
    ax.plot([-11.0, -11.0], [14.2, 49], color="#333333", lw=0.8, ls="--"); label(ax, -12.4, 30, "고전압 케이블", fs=6, rotation=90)
    # Dimensions
    dim(ax, (-15, 0), (-7.5, 0), "7.5 m", offset=-6.2); dim(ax, (-7.5, 0), (0, 0), "7.5 m", offset=-6.2)
    dim(ax, (-15.5, 9.8), (0.5, 9.8), "16.0 m", offset=-1.0)
    dim(ax, (-7.5, 2.0), (-7.5, 9.8), "7.8 m", offset=1.6, side="v")
    dim(ax, (-18.75, 0), (-11.25, 0), "7.5", offset=4.3); dim(ax, (-3.25, 0), (3.25, 0), "6.5", offset=4.0)
    north(ax, 18, 40); scalebar(ax, 10, -8, 10, "10 m")
    ax.set_xlim(-30, 24); ax.set_ylim(-10, 58)
    finish(fig, "01_site_plan.png", "전체 배치도  Site plan  (x 동, 위가 북)",
           "A: NASA Artemis Surface Habitat 참조 설계 (Burke/Howard/Kessler 2022). 모듈 간격·터널은 우리 가안. 원자로 이격은 NASA 40 kWe FSP 전개형 연구(약 1 km).")


# ---------------------------------------------------------------- 2. B engineering plan
def plan_B():
    fig, ax = plt.subplots(figsize=(13, 5.2))
    ax.set_aspect("equal"); ax.axis("off")
    zc = 12.0  # plot y of module centre (world z -12)
    splits = [0.5, -1.7, -3.9, -10.5, -12.3, -14.1, -15.5]
    names = ["B1 먼지 전실·에어락\nAirlock 2.2 m", "B2 수트 정비\nSuit maint. 2.2", "B3 ECLSS 베이  6.6 m\n팔레트 8, 앞 통로 1.0 m", "B4 전력·열\nPower 1.8", "B5 공방\nWorkshop 1.8", "B6 물류\nLogistics 1.4"]
    kinds = [C_NOISY, C_NOISY, C_NOISY, C_NOISY, C_NOISY, C_BUFFER]
    box(ax, -15.5, zc - 2.2, 16, 4.4, C_METAL, lw=1.5)
    for i in range(6):
        x0, x1 = splits[i + 1], splits[i]
        box(ax, x0, zc - 1.9, x1 - x0, 3.8, kinds[i], ec="none", z=1.5)
        label(ax, (x0 + x1) / 2, zc + 2.75, names[i], fs=6.5)
        if i < 5:
            ax.plot([x0, x0], [zc - 1.9, zc + 1.9], color=C_WALL, lw=1.5)
            box(ax, x0 - 0.06, zc + 0.35, 0.12, 0.9, "white", ec="none", z=3)  # door opening
    # Equipment
    for k in range(4): box(ax, -1.2 + k * 0.42, zc + 1.3, 0.35, 0.45, C_EQUIP)
    label(ax, -0.5, zc + 1.0, "수트 거치 4", fs=5.5)
    box(ax, -0.9, zc - 1.75, 1.8, 0.3, "#e67e22"); label(ax, -0.9 + 0.9, zc - 1.95 - 0.25, "에어샤워 노즐", fs=5.5)
    box(ax, -3.7, zc + 1.05, 1.8, 0.7, C_EQUIP, text="수트 작업대", fs=5); box(ax, -3.1, zc - 1.75, 0.8, 0.5, C_EQUIP, text="충전랙", fs=5)
    x0 = -3.9 - 0.55
    for k in range(8):
        box(ax, x0 - k * 0.8 - 0.37, zc + 1.08, 0.74, 0.74, C_EQUIP, text=f"P{k+1}", fs=5)
    label(ax, -7.2, zc + 1.9 + 0.35, "Collins 범용 팔레트 1.83 × 0.77 × 0.77 m (서 있음)", fs=6)
    box(ax, -8.8, zc - 1.8, 3.0, 0.6, "#4d5560", text="O₂ / N₂ 탱크", fs=5)
    dim(ax, (-7.2, zc + 1.08), (-7.2, zc + 0.08), "1.0 m", offset=0, side="v", fs=6)
    box(ax, -11.9, zc + 1.15, 1.0, 0.6, C_EQUIP, text="전력 캐비닛", fs=5); box(ax, -12.1, zc - 1.75, 1.4, 0.6, "#4d5560", text="배터리", fs=5)
    box(ax, -11.1, zc - 0.5, 0.6, 0.8, "#4d5560", text="펌프", fs=5)
    box(ax, -13.9, zc + 0.9, 1.6, 0.8, "#4d5560", text="작업대 + 3D 프린터", fs=5); box(ax, -13.8, zc - 1.75, 1.4, 0.5, "#4d5560", text="서랍", fs=5)
    box(ax, -15.3, zc + 0.7, 1.0, 0.7, "#4d5560", text="CTB 랙", fs=5); box(ax, -15.3, zc - 1.5, 1.0, 0.7, C_EQUIP, text="냉동고", fs=5)
    # Hatches
    box(ax, -8.05, zc - 2.3, 1.1, 0.25, "#e67e22"); label(ax, -7.5, zc - 2.9, "허브 터널 해치 0.9 × 1.9", fs=6)
    box(ax, 0.45, zc - 0.55, 0.25, 1.1, "#e67e22"); label(ax, 1.5, zc - 1.2, "EVA 해치\n→ 외부", fs=6)
    ax.plot([-10.5, -10.5], [zc - 2.2, zc + 2.2], color="#c0392b", lw=2.5); label(ax, -10.5, zc - 2.75, "격벽 + 해치 (방화·소음)", fs=6, color="#c0392b")
    dim(ax, (-15.5, zc - 2.2), (0.5, zc - 2.2), "16.0 m", offset=-1.3, fs=8)
    dim(ax, (0.5, zc - 2.2), (0.5, zc + 2.2), "Ø4.4", offset=1.5, side="v", fs=7)
    dim(ax, (0.5, zc - 1.9), (0.5, zc + 1.9), "바닥 3.8", offset=2.4, side="v", fs=6)
    for i in range(6):
        dim(ax, (splits[i + 1], zc + 2.2), (splits[i], zc + 2.2), f"{splits[i]-splits[i+1]:.1f}", offset=0.25, fs=6)
    label(ax, -7.5, zc + 4.1, "천장 케이블 트레이 / 라인 조명 4,800 K   ·   지붕 방열기 3장   ·   케이블 인입 B4", fs=6.5, color="#333333")
    ax.set_xlim(-17, 4); ax.set_ylim(zc - 4.2, zc + 4.6)
    finish(fig, "02_plan_B_engineering.png", "B 엔지니어링 모듈 평면  Engineering module plan  (동 → 서 : 더러움 → 깨끗함)",
           "팔레트 치수 NASA/Collins 범용 팔레트(72\" × 30.19\"). 통로 폭 1.0 m, 에어락 높이 2.6 m는 NASA Foundation Surface Habitat NHV 권고.")


# ---------------------------------------------------------------- 3. C habitation plans
def plan_C():
    fig, axes = plt.subplots(1, 2, figsize=(13, 6.8))
    R = 3.75
    for ax in axes:
        ax.set_aspect("equal"); ax.axis("off"); ax.set_xlim(-5.6, 5.6); ax.set_ylim(-5.4, 5.6)
        ring(ax, 0, 0, R, R - 0.15, C_INFL, lw=1.5)
    # Deck 1
    ax = axes[0]
    for a0, a1, fc in [(20, 70, C_QUIET), (110, 160, C_QUIET), (200, 250, C_QUIET), (290, 340, C_QUIET),
                       (-20, 20, C_BUFFER), (70, 110, C_BUFFER), (160, 200, C_BUFFER), (250, 290, C_BUFFER)]:
        ax.add_patch(Wedge((0, 0), R - 0.15, a0, a1, width=R - 0.15 - 1.85, fc=fc, ec="none", zorder=1.2))
    for a in [20, 70, 110, 160, 200, 250, 290, 340]:
        r = math.radians(a); ax.plot([1.85 * math.cos(r), (R - 0.15) * math.cos(r)], [1.85 * math.sin(r), (R - 0.15) * math.sin(r)], color=C_WALL, lw=1.4)
    ax.add_patch(Wedge((0, 0), 1.75, 10, 170, width=0.3, fc=C_WATER, ec=C_WALL, zorder=2)); ax.add_patch(Wedge((0, 0), 1.75, 190, 350, width=0.3, fc=C_WATER, ec=C_WALL, zorder=2))
    label(ax, 0, 0.35, "태양폭풍 대피소\nStorm shelter", fs=7, weight="bold"); label(ax, 0, -0.5, "물탱크 벽 1,000 L\nH 1.5 m, 두께 0.3", fs=5.5)
    for i, a in enumerate([45, 135, 225, 315]):
        r = math.radians(a); x, y = 2.9 * math.cos(r), 2.9 * math.sin(r)
        box(ax, x - 1.0, y - 0.42, 2.0, 0.85, "#8d6e4f", angle=a - 90, text="침상 2.0×0.85", fs=4.5)
        label(ax, 2.2 * math.cos(r), 2.2 * math.sin(r), f"침실 {'ABCD'[i]}\n4.5 m²", fs=6.5, weight="bold")
    for a, t in [(0, "위생 A\n1.1 m²"), (90, "수납"), (180, "위생 B\n1.1 m²"), (270, "화장실\nUWMS 0.9")]:
        r = math.radians(a); label(ax, 2.75 * math.cos(r), 2.75 * math.sin(r), t, fs=5.5)
    box(ax, R - 0.3, -0.45, 0.25, 0.9, "#e67e22"); label(ax, R + 0.9, 0, "→ 허브 터널\n해치", fs=6)
    box(ax, 2.2, 1.7, 1.2, 1.0, "#f5d58a", text="사다리\n개구", fs=5, tc="black")
    dim(ax, (-R, -4.4), (R, -4.4), "Ø7.5 m (내부 Ø7.2)", offset=-0.1, fs=7)
    dim(ax, (-1.75, 4.2), (1.75, 4.2), "대피소 Ø3.5", offset=0.1, fs=6)
    ax.set_title("C 1층  Deck 1 (y = 0)   침실 4 + 완충 구획 4 + 대피소", fontsize=9)
    label(ax, 0, -5.1, "침실끼리 벽을 공유하지 않는다: 침실 사이에 위생·수납·화장실", fs=6.5, color="#c0392b")
    # Deck 2
    ax = axes[1]
    ax.add_patch(Wedge((0, 0), R - 0.15, 180, 360, fc=C_BUFFER, ec="none", zorder=1.2))   # wardroom (north = -y here? use plot north up: wardroom north)
    ax.add_patch(Wedge((0, 0), R - 0.15, 0, 180, fc=C_FLOOR, ec="none", zorder=1.2))
    # plot: north is +y. Wardroom & galley north (y>0), medical east, exercise west, greenhouse south.
    ax.add_patch(Wedge((0, 0), R - 0.15, 20, 160, fc=C_BUFFER, ec="none", zorder=1.3))
    ax.add_patch(Wedge((0, 0), R - 0.15, -40, 20, fc=C_QUIET, ec="none", zorder=1.3))
    ax.add_patch(Wedge((0, 0), R - 0.15, 160, 220, fc=C_NOISY, ec="none", zorder=1.3))
    ax.add_patch(Wedge((0, 0), R - 0.15, 220, 320, fc="#cfe8c0", ec="none", zorder=1.3))
    ax.add_patch(Circle((0, 1.6), 0.7, fc="white", ec=C_WALL, zorder=3)); label(ax, 0, 1.6, "테이블\nØ1.4", fs=5.5)
    box(ax, 0.3, 2.6, 2.2, 0.6, C_EQUIP, angle=-25, text="조리대 1.1×0.6 + 냉장", fs=4.5)
    label(ax, 0, 3.05, "워드룸·갤리  창(지구 방향)", fs=6.5, weight="bold")
    box(ax, 2.4, -0.7, 0.8, 2.0, "#8d6e4f", text="들것\n2.0×0.8", fs=4.5); label(ax, 2.2, 1.0, "의무실 1.9 m²\n커튼", fs=6)
    box(ax, -3.0, -0.3, 0.7, 1.4, "#4d5560", text="운동기구", fs=4.5); box(ax, -2.7, -1.9, 0.5, 1.2, C_EQUIP, text="자전거", fs=4.5); label(ax, -2.3, 1.2, "운동 1.5 m²\n창(서)", fs=6)
    box(ax, -1.8, -3.15, 1.6, 0.5, "#4d8a3a", text="온실 랙", fs=4.5); box(ax, 0.2, -3.15, 1.6, 0.5, "#4d8a3a", text="온실 랙", fs=4.5); label(ax, -0.4, -2.3, "온실 4 m²  LED 5,500 K", fs=6)
    box(ax, 2.2, -2.2, 1.2, 1.0, "#f5d58a", text="사다리\n개구", fs=5, tc="black")
    box(ax, -0.45, R - 0.2, 0.9, 0.12, C_GLASS); box(ax, -R + 0.08, 0.15, 0.12, 0.9, C_GLASS)
    label(ax, 0, R + 0.5, "창 0.9 × 0.7 (북, 지구)", fs=6); label(ax, -R - 0.9, 0.6, "창\n(서)", fs=6)
    dim(ax, (-R, -4.4), (R, -4.4), "Ø7.5 m", offset=-0.1, fs=7)
    ax.set_title("C 2층  Deck 2 (y = 2.6)   워드룸·갤리 / 의무 / 운동 / 온실", fontsize=9)
    label(ax, 0, -5.1, "시끄러운 운동은 침실 위가 아닌 서쪽 끝, 조용한 의무실은 동쪽", fs=6.5, color="#c0392b")
    finish(fig, "03_plan_C_habitation.png", "C 거주 모듈 평면  Habitation module plans  (위가 북)",
           "면적: NASA Foundation Surface Habitat NHV 권고 (취침 1.82 + 스트레칭 1.40, 위생 1.06, UWMS 0.91, 테이블 1.62, 의료 1.87, 운동 1.50 m²). 침실 벽 비공유: Burke et al. 2022 §VII.")


# ---------------------------------------------------------------- 4. A core plans
def plan_A():
    fig, axes = plt.subplots(1, 3, figsize=(14, 5.4))
    specs = [
        ("L1  y = 0  금속 Ø4.4", 2.2, [
            ("수트포트 에어락\n5.0 m², H 2.6\n수트포트 2 + 해치 2", 180, 360, C_NOISY),
            ("작업대 1.37\n정비·물류·쓰레기", 0, 60, C_NOISY), ("지질 실험대", 60, 110, C_BUFFER), ("EVA 컴퓨터", 110, 150, C_BUFFER), ("OGA 팔레트 2\n화물 수트포트", 150, 180, C_NOISY)]),
        ("L2  y = 2.6  인플레이터블 Ø6.5", 3.25, [
            ("위생 1.06", 0, 45, C_BUFFER), ("UWMS 0.91", 45, 80, C_BUFFER), ("운동 1.5\nE4D", 80, 135, C_NOISY), ("생물 실험대", 135, 180, C_BUFFER),
            ("WPA 팔레트 3", 180, 240, C_NOISY), ("UP / BP 팔레트 2", 240, 290, C_NOISY), ("물탱크", 290, 360, C_BUFFER)]),
        ("L3  y = 5.2  인플레이터블 Ø6.5", 3.25, [
            ("침실 1\n(벽 공유 !)", 150, 200, C_QUIET), ("침실 2", 200, 250, C_QUIET), ("의무 1.87\n들것", 250, 300, C_QUIET),
            ("컴퓨터\n스테이션", 300, 340, C_BUFFER), ("조리 + 워드룸 테이블\n창", 340, 420, C_BUFFER), ("물리 실험", 60, 105, C_BUFFER), ("인간연구 실험", 105, 150, C_BUFFER)]),
    ]
    for ax, (title, R, rooms) in zip(axes, specs):
        ax.set_aspect("equal"); ax.axis("off"); ax.set_xlim(-4.6, 4.6); ax.set_ylim(-4.6, 4.6)
        ring(ax, 0, 0, R, R - (0.12 if R < 3 else 0.25), C_METAL if R < 3 else C_INFL, lw=1.5)
        for name, a0, a1, fc in rooms:
            ax.add_patch(Wedge((0, 0), R - 0.25, a0, a1, width=R - 0.25 - 1.65, fc=fc, ec=C_WALL, lw=0.6, zorder=1.5))
            m = math.radians((a0 + a1) / 2); label(ax, 2.5 * math.cos(m), 2.5 * math.sin(m), name, fs=5.2)
        ax.add_patch(Circle((0, 0), 1.65, fc="#f3f3f3", ec=C_WALL, lw=1.2, ls="--", zorder=2))
        label(ax, 0, 0.55, "코어 Ø3.3", fs=6)
        box(ax, -0.3, -0.9, 0.6, 1.0, "#f5d58a", text="사다리", fs=5, tc="black")
        if R > 3:
            label(ax, 0, -1.3, "ARS 팔레트 3 (L3)\n시스템·수납" if "L3" in title else "ARS / 열제어 접근", fs=5)
        ax.set_title(title, fontsize=9)
        dim(ax, (-R, -4.0), (R, -4.0), f"Ø{2*R:.1f} m", offset=-0.1, fs=7)
    label(axes[2], 0, -4.45, "NASA 논문이 지적한 결함: 침실 2개 벽 공유, 침실 1은 의무실 통과, ARS 옆", fs=6.5, color="#c0392b")
    finish(fig, "04_plan_A_core.png", "A 코어 타워 층별 구성  Core tower levels  (NASA Surface Habitat 참조 설계 요약)",
           "출처: Burke, Howard, Kessler, Internal Layout of a Lunar Surface Habitat, ASCEND 2022 (Fig. 5~7 요약, 각도 배치는 근사).")


# ---------------------------------------------------------------- 5. sections
def sections():
    fig, axes = plt.subplots(1, 3, figsize=(15, 6.2), gridspec_kw=dict(width_ratios=[1.1, 1.3, 0.9]))
    # A tower section
    ax = axes[0]; ax.set_aspect("equal"); ax.axis("off"); ax.set_xlim(-5.5, 5.5); ax.set_ylim(-1.5, 10.5)
    box(ax, -2.2, 0, 4.4, 2.6, C_METAL, lw=1.5); box(ax, -3.25, 2.6, 6.5, 5.2, C_INFL, lw=1.5)
    ax.add_patch(Arc((0, 7.8), 6.5, 1.4, theta1=0, theta2=180, color=C_WALL, lw=1.5)); ax.add_patch(Polygon([(-3.25, 7.8), (3.25, 7.8), (3.25, 7.8)], fc=C_INFL))
    for y, t in [(0, "L1  0.0"), (2.6, "L2  2.6"), (5.2, "L3  5.2")]:
        ax.plot([-3.1 if y > 0 else -2.05, 3.1 if y > 0 else 2.05], [y, y], color=C_WALL, lw=3); label(ax, 3.9, y + 0.15, t, fs=6.5, ha="left")
    box(ax, -1.65, 0, 3.3, 7.8, "none", ec=C_WALL, lw=0.8); label(ax, 0, 8.2, "코어 Ø3.3 (시스템·사다리)", fs=6)
    box(ax, -0.25, 0, 0.5, 7.8, "#f5d58a", ec="none"); label(ax, 0, 4.0, "사다리", fs=6, rotation=90)
    dim(ax, (-2.2, -0.3), (2.2, -0.3), "4.4", offset=-0.5, fs=7); dim(ax, (-3.25, 9.3), (3.25, 9.3), "6.5", offset=0.1, fs=7)
    dim(ax, (4.9, 0), (4.9, 2.6), "2.6 금속", offset=0, side="v", fs=6); dim(ax, (4.9, 2.6), (4.9, 7.8), "5.2 인플레이터블", offset=0, side="v", fs=6)
    ax.plot([-5.3, 5.3], [0, 0], color=C_REGO, lw=3); label(ax, 0, -1.0, "레골리스 지면 (하부 금속부 매립 가능)", fs=6)
    ax.set_title("A 코어 타워 단면 (NASA 참조: 금속 2.6 m + 인플레이터블 5.2 m)", fontsize=8.5)
    # C section
    ax = axes[1]; ax.set_aspect("equal"); ax.axis("off"); ax.set_xlim(-11, 11); ax.set_ylim(-1.5, 9)
    for sgn in (-1, 1):
        ax.add_patch(Polygon([(sgn * 3.9, 0), (sgn * 10.0, 0), (sgn * 8.0, 2.0), (sgn * 5.2, 3.5), (sgn * 3.9, 3.5)], fc=C_REGO, ec=C_WALL, lw=0.8))
    box(ax, -3.75, 0, 7.5, 5.8, C_INFL, lw=1.5)
    ax.add_patch(Arc((0, 5.8), 7.5, 2.4, theta1=0, theta2=180, color=C_WALL, lw=1.5, zorder=3)); ax.add_patch(Polygon([(-3.75, 5.8), (-3.75, 5.8 + 1.2), (0, 7.0), (3.75, 7.0), (3.75, 5.8)], fc=C_INFL, ec="none"))
    ax.plot([-3.6, 3.6], [0, 0], color=C_WALL, lw=3); ax.plot([-3.6, 1.6], [2.6, 2.6], color=C_WALL, lw=3); ax.plot([2.8, 3.6], [2.6, 2.6], color=C_WALL, lw=3)
    label(ax, 2.2, 2.75, "사다리 개구", fs=5.5)
    for x in (-1.75, 1.45): box(ax, x, 0, 0.3, 1.5, C_WATER)
    label(ax, 0, 0.75, "대피소\n물탱크 벽 1.5 m", fs=6); label(ax, -2.7, 1.2, "침실\n침상 0.5", fs=6); box(ax, -3.4, 0, 2.0, 0.5, "#8d6e4f")
    label(ax, 0, 3.9, "2층: 워드룸 · 의무 · 운동 · 온실", fs=6.5); box(ax, 3.55, 4.0, 0.2, 0.7, C_GLASS); label(ax, 6.3, 4.6, "창 0.9×0.7\n(2층 바닥 +1.4)", fs=5.5)
    dim(ax, (4.3, 0), (4.3, 2.6), "2.6", offset=0, side="v", fs=6.5); dim(ax, (4.3, 2.6), (4.3, 5.8), "3.2", offset=0, side="v", fs=6.5)
    dim(ax, (-3.75, 8.3), (3.75, 8.3), "Ø7.5", offset=0.1, fs=7); dim(ax, (-10, -0.6), (10, -0.6), "성토 포함 20 m", offset=-0.5, fs=6.5)
    dim(ax, (8.8, 0), (8.8, 3.5), "성토 3.5", offset=0, side="v", fs=6.5)
    ax.set_title("C 거주 모듈 단면 (인플레이터블 2층 + 돔 + 레골리스 성토)", fontsize=8.5)
    # B cross-section
    ax = axes[2]; ax.set_aspect("equal"); ax.axis("off"); ax.set_xlim(-4.2, 4.2); ax.set_ylim(-1.2, 6.2)
    ax.add_patch(Circle((0, 1.45), 2.2, fc=C_METAL, ec=C_WALL, lw=1.5)); ax.add_patch(Circle((0, 1.45), 2.05, fc=C_FLOOR, ec=C_WALL, lw=0.8))
    half = math.sqrt(2.05 ** 2 - 1.45 ** 2)
    ax.add_patch(Polygon([(-half, 0), (half, 0), (half, -0.6), (-half, -0.6)], fc=C_METAL, ec="none"))
    ax.add_patch(Wedge((0, 1.45), 2.05, 180 + math.degrees(math.asin(1.45 / 2.05)), 360 - math.degrees(math.asin(1.45 / 2.05)), fc=C_METAL, ec="none"))
    ax.plot([-half, half], [0, 0], color=C_WALL, lw=3)
    box(ax, -1.65 + 0.2, 0, 0.74, 1.83, C_EQUIP, text="팔레트\n1.83", fs=5); label(ax, 0.9, 0.9, "통로 1.0 m", fs=6)
    box(ax, 0.6, 1.45 + 1.6, 1.4, 0.15, "#4d5560"); label(ax, 1.3, 2.75, "케이블 트레이", fs=5.5)
    box(ax, -0.3, 1.45 + 1.9, 0.6, 0.06, "#fff3b0"); label(ax, -1.2, 3.05, "라인 조명 4,800 K", fs=5.5)
    for k in range(3): box(ax, -1.5 + k * 1.0, 3.7, 0.06, 1.6, C_METAL)
    label(ax, 0, 5.6, "방열기 패널 (수직)", fs=6)
    dim(ax, (-2.2, -0.9), (2.2, -0.9), "Ø4.4", offset=0, fs=7); dim(ax, (-half, 0.2), (half, 0.2), f"바닥 폭 {2*half:.1f}", offset=0, fs=6)
    dim(ax, (2.6, 0), (2.6, 1.45 + 2.05), f"천장 {1.45+2.05:.1f}", offset=0, side="v", fs=6.5)
    ax.set_title("B 엔지니어링 횡단면", fontsize=8.5)
    finish(fig, "05_sections.png", "단면도  Sections",
           "표준 높이 2.4 m(수트 착탈 2.6 m), 팔레트 1.83 m: NASA Foundation Surface Habitat NHV 권고. 성토 높이는 가안(거주 모듈 2/3).")


# ---------------------------------------------------------------- 6. zoning
def zoning():
    fig, ax = plt.subplots(figsize=(11, 7))
    ax.set_aspect("equal"); ax.axis("off")
    ax.add_patch(Circle((0, 0), 3.25, fc=C_BUFFER, ec=C_WALL)); label(ax, 0, 0, "A 코어\n(혼합: L1 시끄러움\nL3 침실·워드룸)", fs=7)
    ax.add_patch(Circle((-7.5, 0), 2.0, fc=C_BUFFER, ec=C_WALL)); label(ax, -7.5, 0, "D 허브\n완충", fs=7)
    ax.add_patch(Circle((-15, 0), 3.75, fc=C_QUIET, ec=C_WALL)); label(ax, -15, 0.4, "C 거주\n조용 · 깨끗 · 사적", fs=8, weight="bold"); label(ax, -15, -1.2, "침실 4 · 대피소\n2층 공용", fs=6)
    box(ax, -15.5, 9.8, 16, 4.4, C_NOISY); label(ax, -7.5, 12.0, "B 엔지니어링   시끄러움 · 더러움 허용", fs=8, weight="bold")
    label(ax, -1.0, 10.6, "B1 에어락\n더러움 ●●●", fs=6); label(ax, -7.2, 10.6, "B3 ECLSS 팔레트 70~80 dB", fs=6); label(ax, -13.5, 10.6, "B5 공방 80 dB", fs=6)
    box(ax, -5.5, -0.8, 2.2, 1.6, C_BUFFER); box(ax, -11.3, -0.8, 1.8, 1.6, C_BUFFER); box(ax, -8.3, 2.0, 1.6, 7.8, C_BUFFER)
    # dust path
    pts = [(3.0, 12.0), (-1.0, 12.0), (-3.0, 12.0), (-7.5, 10.5), (-7.5, 3.0), (-9.8, 0), (-13.0, 0)]
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        ax.annotate("", (x1, y1), (x0, y0), arrowprops=dict(arrowstyle="-|>", color="#8e5a2b", lw=2.2))
    label(ax, 3.4, 13.0, "먼지 동선: 외부 → 에어락(털기) → 수트실 → 터널 → 허브 → 거주", fs=7, color="#8e5a2b", ha="left")
    # noise barriers
    ax.plot([-10.5, -10.5], [9.8, 14.2], color="#c0392b", lw=3); label(ax, -10.5, 15.0, "격벽 −15 dB", fs=6, color="#c0392b")
    for (x, y) in [(-5.5, 0), (-9.5, 0), (-7.5, 9.8), (-7.5, 2.0), (-3.3, 0), (-11.3, 0)]:
        ax.add_patch(Circle((x, y), 0.3, fc="#c0392b", ec="none", zorder=5))
    label(ax, -7.5, -2.4, "● 해치 = 소음 경계(−15 dB) · 층 사이 −25 dB", fs=6.5, color="#c0392b")
    ax.add_patch(Circle((-15, 0), 1.75, fc=C_WATER, ec=C_WALL, zorder=3)); label(ax, -15, 0, "대피소", fs=6, color="white", weight="bold")
    # legend
    for i, (c, t) in enumerate([(C_QUIET, "조용 (35~45 dB) 침실·대피소·의무·온실"), (C_BUFFER, "완충 (45~65 dB) 위생·수납·통로·워드룸"), (C_NOISY, "시끄러움 (65~85 dB) ECLSS·전력·운동·공방·에어락")]):
        box(ax, -22, 5.5 - i * 1.3, 1.2, 0.9, c); label(ax, -20.5, 6.0 - i * 1.3, t, fs=7, ha="left")
    label(ax, -22, 8.0, "구역 성격 (ISS 거주모듈 1988 설계의 3구역 원칙)", fs=7.5, weight="bold", ha="left")
    label(ax, -22, -3.5, "허용 소음 = 그 방의 장비까지 포함해 견디는 수준 (침실 35, 의무 45, 워드룸 65, 운동 75, 공방 85 dB)", fs=6.5, ha="left")
    ax.set_xlim(-24, 8); ax.set_ylim(-5, 16)
    finish(fig, "06_zoning_dust_noise.png", "구역·먼지·소음 다이어그램  Zoning, dust path and noise barriers",
           "3구역 원칙: SAE 881119 (Space Station Habitat baseline). 먼지 1차 방어선 = 에어락: NMSU WERC 2025 Task 4. 소음 규칙 −15/−25 dB는 도구의 어림값.")


if __name__ == "__main__":
    site_plan(); plan_B(); plan_C(); plan_A(); sections(); zoning()
