# -*- coding: utf-8 -*-
"""Writes docs/design/SCHEDULES.md (coordinates, rooms, hatches, equipment) from params.py.
Run:  python -X utf8 tools/design/make_schedules.py"""
import io
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import params as P  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "docs", "design", "SCHEDULES.md")
L = []
w = L.append


def table(head, rows):
    w("| " + " | ".join(head) + " |")
    w("|" + "|".join(["---"] * len(head)) + "|")
    for r in rows:
        w("| " + " | ".join(str(c) for c in r) + " |")
    w("")


def f(v):
    return "%.2f" % v


w("# 기지 설계 일람표 (자동 생성)")
w("")
w("`tools/design/params.py` 에서 `tools/design/make_schedules.py` 로 생성. 손으로 고치지 말고 params 를 고친 뒤 다시 생성한다.")
w("좌표계: 게임 월드 (x 동, y 위, z **남**), 단위 m. 방위각: 0° = 동, 90° = 북, 위에서 볼 때 반시계. 블렌더에서는 X = x, Y = −z, Z = y.")
w("")
w("## 1. 모듈 기준점")
table(["모듈", "중심 x", "중심 z", "바닥 y", "외경", "선체 하단 y", "선체 상단 y"], [
    ["A 코어 타워 (기존)", f(0), f(0), "0 / 2.60 / 5.20", "4.40 (금속) / 6.50", "약 −1.1 (모델)", "약 7.8"],
    ["D 허브", f(P.D["c"][0]), f(P.D["c"][1]), "0", f(2 * P.D["r_out"]), f(P.D["y_bottom"]), f(P.D["y_top"])],
    ["C 거주", f(P.C["c"][0]), f(P.C["c"][1]), "0 / 2.60", f(2 * P.C["r_out"]), f(P.C["y_bottom_out"]), f(P.C["y_top_out"])],
    ["B 엔지니어링 (축)", f(P.B["x"]), "%s ~ %s" % (f(P.ST["B-U cone S start"]), f(P.ST["EV ring face"])), "0", f(2 * P.B["r_out"]), f(P.B["y_bottom"]), f(P.B["y_top"])],
])
w("## 2. B 축 방향 스테이션 (z, 북쪽이 음수)")
keys = list(P.ST.keys())
rows = []
for i, k in enumerate(keys):
    step = "" if i == 0 else f(abs(P.ST[k] - P.ST[keys[i - 1]]))
    rows.append([k, f(P.ST[k]), step])
table(["스테이션", "z", "앞 스테이션에서"], rows)

w("## 3. B 실 일람")
rows = []
for rid, nm, zt, zs, zn in P.B_ROOMS:
    fw = 2 * P.B["floor_half"]
    rows.append([rid, nm, zt, f(P.B["x"] - P.B["floor_half"]), f(P.B["x"] + P.B["floor_half"]), f(zs), f(zn), f(zs - zn), f(fw), "%.1f" % ((zs - zn) * fw)])
table(["실", "이름", "구역 프리셋", "x 서", "x 동", "z 남", "z 북", "길이", "바닥 폭", "면적 m²"], rows)
w("칸막이: " + " · ".join("%s (z %s, 두께 %s, %s)" % (nm, f(zs), f(t), "문 1.00×2.00" if k == "door" else "압력 격벽 + H-1 해치") for nm, zs, t, k in P.B_PARTITIONS))
w("")
w("## 4. C 구획 (중심 %s, %s)" % (f(P.C["c"][0]), f(P.C["c"][1])))
w("1층: 로비 반경 %.2f, 방은 반경 %.2f ~ %.2f. 2층: 로비 반경 %.2f 바깥 전부." % (P.C["lobby_r"], P.C["room_r0"], P.C["r_in"], P.C["lobby_r"]))
w("")
rows = []
for nm, typ, a0, a1 in P.C_DECK1:
    rows.append(["1", nm, typ, "%.0f°" % a0, "%.0f°" % a1, "%.0f°" % (a1 - a0), f(P.sector_area(P.C["room_r0"], P.C["r_in"], a0, a1))])
for nm, typ, a0, a1 in P.C_DECK2:
    rows.append(["2", nm, typ, "%.0f°" % a0, "%.0f°" % a1, "%.0f°" % (a1 - a0), f(P.sector_area(P.C["lobby_r"], P.C["r_in"], a0, a1))])
table(["층", "구획", "구역 프리셋", "방위 시작", "방위 끝", "각도", "면적 m²"], rows)
w("2층 헤드룸: " + " · ".join("R %.2f → %.2f" % (r, P.c_headroom_deck2(r)) for r in (1.5, 2.5, 2.76, 3.0, 3.2, 3.35)))
w("")
w("창: " + " · ".join("%s 방위 %.0f°, 폭 %.2f, y %.2f~%.2f" % (n, az, wd, y0, y1) for n, az, wd, y0, y1 in P.C_WINDOWS))
w("")
Lq = P.C_LADDER
cx, cz = P.C["c"]
w("사다리(70°, 폭 %.2f): x %.2f, 발 z %.2f → 꼭대기 z %.2f. 2층 개구 x %.2f~%.2f, z %.2f~%.2f. 랜딩 1층 (%.2f, 0, %.2f), 2층 (%.2f, 2.60, %.2f)." % (
    Lq["width"], cx + Lq["x"], cz + Lq["z_foot"], cz + Lq["z_top"], cx + Lq["opening"][0], cx + Lq["opening"][2], cz + Lq["opening"][1], cz + Lq["opening"][3],
    cx + Lq["landing1"][0], cz + Lq["landing1"][2], cx + Lq["landing2"][0], cz + Lq["landing2"][2]))
w("")
w("## 5. 해치 일람 (모두 H-1: 유효 개구 1.02 × 1.52, 중심 높이 y = 0.90)")
rows = [[hid, desc, f(x), f(z), "%.0f°" % az, "EV (외부)" if kind == "EV" else "IV"] for hid, desc, x, z, az, kind in P.ports()]
table(["번호", "위치", "x", "z", "바깥 법선 방위", "종류"], rows)
w("문짝은 법선 반대쪽(자기 모듈 안쪽)으로 열린다. 좌표는 해치판 바깥면(링 끝면) 중심.")
w("")
w("## 6. 터널")
rows = [[nm, f(x0), f(z0), f(x1), f(z1), f(math.hypot(x1 - x0, z1 - z0))] for nm, x0, z0, x1, z1 in P.tunnels()]
table(["터널", "x0", "z0", "x1", "z1", "길이"], rows)
w("단면: 내경 %.2f, 외경 %.2f, 축 높이 %.2f, 평바닥 폭 %.2f, 헤드룸 %.2f." % (P.TUNNEL["d_in"], P.TUNNEL["d_out"], P.PORT_H, P.TUNNEL["floor_w"], P.TUNNEL["headroom"]))
w("")
w("## 7. B 장비 (월드 좌표 상자)")
rows = []
for i, (name, room, x0, x1, y0, y1, zs, zn) in enumerate(P.b_equip_boxes(), start=1):
    rows.append([i, name, f(x0), f(x1), f(zs), f(zn), f(y0), f(y1), "%s × %s × %s" % (f(zs - zn), f(x1 - x0), f(y1 - y0))])
table(["#", "장비", "x0", "x1", "z 남", "z 북", "y0", "y1", "길이 × 깊이 × 높이"], rows)
rows = [[nm, f(x0), f(x1), f(z0), f(z1), f(y0), f(y1)] for nm, x0, z0, x1, z1, y0, y1 in P.B_EXTERNAL]
table(["외부 장비", "x0", "x1", "z0", "z1", "y0", "y1"], rows)
w("## 8. C 장비 (C 중심 기준 극좌표: 방위, 중심 반경, 접선 길이 × 반경 깊이 × 높이)")
rows = []
for name, deck, az, r, tang, rad, hgt, y0 in P.C_EQUIP:
    x, z = P.pol(P.C["c"], az, r)
    base = 0.0 if deck == 1 else P.C["deck2"]
    rows.append([deck, name, "%.1f°" % az, f(r), f(x), f(z), "%s × %s × %s" % (f(tang), f(rad), f(hgt)), f(base + y0)])
table(["층", "장비", "방위", "반경", "x", "z", "크기", "바닥 y"], rows)
rows = [[deck, name, "%.0f°~%.0f°" % (a0, a1), "%s~%s" % (f(ra), f(rb)), f(hgt)] for name, deck, a0, a1, ra, rb, hgt, y0 in P.C_ARCS]
table(["층", "곡면 가구", "방위", "반경", "높이"], rows)
w("## 9. D 장비 (D 중심 기준 극좌표)")
rows = []
for name, az, r, tang, rad, hgt, y0 in P.D_EQUIP:
    x, z = P.pol(P.D["c"], az, r)
    rows.append([name, "%.0f°" % az, f(r), f(x), f(z), "%s × %s × %s" % (f(tang), f(rad), f(hgt)), f(y0)])
table(["장비", "방위", "반경", "x", "z", "크기", "바닥 y"], rows)
w("## 10. 파이프라인 구역 초안 (tools/build_default_session.gd 의 ZONES 표 형식)")
w("B·D·터널은 사각형이라 그대로 넣을 수 있다. C 는 부채꼴이라 사각형 구역으로는 근사만 된다 (구역 도구에 부채꼴/다각형 지원이 필요).")
w("")
w("```gdscript")
for rid, nm, zt, zs, zn in P.B_ROOMS:
    w('\t["B-%s %s", 0.0, "%s", %s, %s, %s, %s],' % (rid, nm.split(" (")[0], zt, f(P.B["x"] - P.B["floor_half"]), f(zn), f(P.B["x"] + P.B["floor_half"]), f(zs)))
dx, dz = P.D["c"]
w('\t["D hub", 0.0, "corridor", %s, %s, %s, %s],' % (f(dx - 2.1), f(dz - 2.1), f(dx + 2.1), f(dz + 2.1)))
for nm, x0, z0, x1, z1 in P.tunnels():
    hw = P.TUNNEL["floor_w"] / 2
    if abs(z1 - z0) < 1e-6:
        w('\t["%s", 0.0, "corridor", %s, %s, %s, %s],' % (nm, f(min(x0, x1)), f(z0 - hw), f(max(x0, x1)), f(z0 + hw)))
    else:
        w('\t["%s", 0.0, "corridor", %s, %s, %s, %s],' % (nm, f(x0 - hw), f(min(z0, z1)), f(x0 + hw), f(max(z0, z1))))
w("```")
io.open(OUT, "w", encoding="utf8").write("\n".join(L) + "\n")
print("wrote", OUT, len(L), "lines")
