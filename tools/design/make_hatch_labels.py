# -*- coding: utf-8 -*-
"""Placard textures for the hatch door (blender/textures/hatch_*.png). Run with the system Python:
    python -X utf8 tools/design/make_hatch_labels.py"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, Rectangle

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "blender", "textures")
os.makedirs(OUT, exist_ok=True)


def placard(name, title, lines, w=4.0, h=3.4):
    fig = plt.figure(figsize=(w, h), dpi=128)
    ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, 1); ax.set_ylim(0, 1); ax.axis("off")
    ax.add_patch(Rectangle((0, 0), 1, 1, fc="#f4f4f1", ec="none"))
    ax.add_patch(Rectangle((0.025, 0.03), 0.95, 0.94, fc="none", ec="#222222", lw=1.6))
    ax.text(0.5, 0.88, title, ha="center", va="center", fontsize=15, weight="bold", color="#111111", family="Arial")
    y = 0.76
    for i, s in enumerate(lines, start=1):
        ax.text(0.07, y, "%d.  %s" % (i, s), ha="left", va="center", fontsize=7.6, color="#222222", family="Arial")
        y -= 0.70 / max(len(lines), 1)
    fig.savefig(os.path.join(OUT, name), dpi=128); plt.close(fig)


placard("hatch_placard_opening.png", "OPENING HATCH", [
    "PRESSURE EQUALIZATION VALVE - OPEN", "CHECK DELTA-P INDICATOR - ZERO", "CRANK HANDLE - UNSTOW",
    "RATCHET - UNLATCH POSITION", "CRANK HANDLE - TURN TO UNLATCH, FULL TRAVEL", "INDICATOR - UNLATCHED",
    "CRANK HANDLE - STOW", "PULL HATCH CLEAR OF SEAL", "SWING OPEN TO STOP", "HOLD-OPEN LATCH - ENGAGE"])
placard("hatch_placard_closing.png", "CLOSING HATCH", [
    "HOLD-OPEN LATCH - RELEASE", "SEAL SURFACE - INSPECT, WIPE", "SWING HATCH CLOSED",
    "RATCHET - LATCH POSITION", "CRANK HANDLE - TURN TO LATCH, FULL TRAVEL", "INDICATOR - LATCHED",
    "CRANK HANDLE - STOW", "PRESSURE EQUALIZATION VALVE - CLOSED"], h=3.0)

# yellow warning label
fig = plt.figure(figsize=(4.0, 1.6), dpi=128)
ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, 1); ax.set_ylim(0, 1); ax.axis("off")
ax.add_patch(Rectangle((0, 0), 1, 1, fc="#f2c300", ec="none")); ax.add_patch(Rectangle((0.02, 0.05), 0.96, 0.9, fc="none", ec="#111111", lw=1.6))
ax.add_patch(Rectangle((0.02, 0.66), 0.96, 0.29, fc="#111111", ec="none"))
ax.text(0.5, 0.80, "WARNING", ha="center", va="center", fontsize=14, weight="bold", color="#f2c300", family="Arial")
ax.text(0.5, 0.36, "EQUALIZE PRESSURE BEFORE UNLATCHING.\nKEEP HANDS CLEAR OF LATCH LINKAGE.", ha="center", va="center", fontsize=8, weight="bold", color="#111111", family="Arial")
fig.savefig(os.path.join(OUT, "hatch_label_warning.png"), dpi=128); plt.close(fig)

# red / white striped handle label
fig = plt.figure(figsize=(4.0, 1.0), dpi=128)
ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, 4); ax.set_ylim(0, 1); ax.axis("off")
ax.add_patch(Rectangle((0, 0), 4, 1, fc="#f6f6f6", ec="none"))
for i in range(-2, 12):
    ax.add_patch(Polygon([(i * 0.5, 0), (i * 0.5 + 0.25, 0), (i * 0.5 + 0.75, 1), (i * 0.5 + 0.5, 1)], closed=True, fc="#c62020", ec="none"))
ax.add_patch(Rectangle((1.1, 0.14), 1.8, 0.72, fc="#f6f6f6", ec="#c62020", lw=1.5))
ax.text(2.0, 0.5, "EXIT", ha="center", va="center", fontsize=20, weight="bold", color="#c62020", family="Arial")
fig.savefig(os.path.join(OUT, "hatch_label_exit.png"), dpi=128); plt.close(fig)

# latch state indicator ring strip (green LATCHED / red UNLATCHED / amber EQUALIZE)
fig = plt.figure(figsize=(4.0, 0.5), dpi=128)
ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, 3); ax.set_ylim(0, 1); ax.axis("off")
for i, (c, t) in enumerate((("#1f8f3a", "LATCHED"), ("#d9a400", "EQUALIZE"), ("#c62020", "UNLATCHED"))):
    ax.add_patch(Rectangle((i, 0), 1, 1, fc=c, ec="none")); ax.text(i + 0.5, 0.5, t, ha="center", va="center", fontsize=9, weight="bold", color="white", family="Arial")
fig.savefig(os.path.join(OUT, "hatch_label_indicator.png"), dpi=128); plt.close(fig)
print("wrote labels to", OUT)
