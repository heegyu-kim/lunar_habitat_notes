# -*- coding: utf-8 -*-
"""Single source of truth for the base-camp design (modules B, C, D, tunnels, hatches).

World frame = the Godot scene: x east, y up, z SOUTH, metres. Datum y = 0 is the top of every
ground-level floor (tower A level 1). Tower A (NASA reference habitat) stands on the origin.
Azimuth: 0 = east (+x), 90 = north (-z), counter-clockwise seen from above.

Used by tools/draw_design.py (drawings), tools/build_design_blend.py (Blender reference model)
and tools/design/make_schedules.py (tables in docs/design/SCHEDULES.md). Change a number here,
re-run the three tools, and drawings, model and tables stay consistent.
"""
import math

# ----------------------------------------------------------------------------- common parts
PORT_H = 0.90          # height of every port / hatch / tunnel axis above the floor

HATCH = dict(          # H-1 common hatch. Clear opening 40 x 60 in (NASA xEMU hatch mock-up, ICES-2025-294)
    w=1.02, h=1.52, corner_r=0.20,
    sill=PORT_H - 1.52 / 2,      # 0.14 m step-over
    depth=0.15,                  # 6 in frame depth
    coam_w=1.30, coam_h=1.80,    # outer size of the coaming (frame)
    leaf_w=1.10, leaf_h=1.60, leaf_t=0.06,
)
RING = dict(d_in=2.10, d_out=2.40, length=0.25)     # berthing ring that carries the flat hatch plate
TUNNEL = dict(d_in=2.10, d_out=2.30, length=1.50)   # rigid tunnel between two ring faces
TUNNEL["floor_w"] = 2 * math.sqrt((TUNNEL["d_in"] / 2) ** 2 - PORT_H ** 2)   # 1.08 m walking floor
TUNNEL["headroom"] = PORT_H + TUNNEL["d_in"] / 2                              # 1.95 m
HULL_GAP = 2 * RING["length"] + TUNNEL["length"]    # 2.00 m hull to hull

# ----------------------------------------------------------------------------- A  core tower (existing model)
A = dict(c=(0.0, 0.0), r_metal=2.20, h_metal=2.60, r_infl=3.25, h_infl=5.20, r_core=1.65,
         decks=(0.0, 2.6, 5.2), port_az=180.0)

# ----------------------------------------------------------------------------- D  hub
D = dict(r_out=2.20, r_in=2.10, h_clear=2.40, head=0.60, floor_t=0.15, ceil_t=0.15)
D["c"] = (A["c"][0] - A["r_metal"] - HULL_GAP - D["r_out"], 0.0)          # (-6.40, 0)
D["ports"] = {"E": 0.0, "N": 90.0, "W": 180.0, "S": 270.0}
D["y_bottom"] = -D["floor_t"] - D["head"]                                  # -0.75
D["y_top"] = D["h_clear"] + D["ceil_t"] + D["head"]                        # 3.15
ROVER_STUB = 1.00      # short tunnel on the hub's south port, ends in a ring + hatch

# ----------------------------------------------------------------------------- C  habitation (inflatable, 2 decks)
C = dict(r_out=3.75, shell_t=0.40, wall_top=3.90, cap_r=1.50, top=5.40, bottom=-1.00,
         deck2=2.60, deck_t=0.20, clear1=2.40, lobby_r=1.50, room_r0=1.55, part_t=0.08,
         port_az=0.0)
C["r_in"] = C["r_out"] - C["shell_t"]                                      # 3.35
C["c"] = (D["c"][0] - D["r_out"] - HULL_GAP - C["r_out"], 0.0)            # (-14.35, 0)
C["y_bottom_out"] = C["bottom"] - C["shell_t"]                             # -1.40
C["y_top_out"] = C["top"] + C["shell_t"]                                   # 5.80


def c_inner_radius(y):
    """Inner radius of the C shell at height y (None outside the pressure volume)."""
    a = C["r_in"] - C["cap_r"]
    if 0.0 <= y <= C["wall_top"]:
        return C["r_in"]
    if C["wall_top"] < y <= C["top"]:
        b = C["top"] - C["wall_top"]
        return C["cap_r"] + a * math.sqrt(max(0.0, 1 - ((y - C["wall_top"]) / b) ** 2))
    if C["bottom"] <= y < 0.0:
        b = -C["bottom"]
        return C["cap_r"] + a * math.sqrt(max(0.0, 1 - (y / b) ** 2))
    return None


def c_headroom_deck2(r):
    """Clear height above the deck-2 floor at radius r."""
    if r <= C["cap_r"]:
        return C["top"] - C["deck2"]
    a = C["r_in"] - C["cap_r"]
    b = C["top"] - C["wall_top"]
    t = (r - C["cap_r"]) / a
    return C["wall_top"] + b * math.sqrt(max(0.0, 1 - t * t)) - C["deck2"]


# Deck 1 sectors (azimuth from, to). No two crew quarters share a wall.
C_DECK1 = [
    ("Entry",      "corridor",      -20.0,  20.0),
    ("CQ-A",       "crew_quarters",  20.0,  80.0),
    ("Hygiene A",  "hygiene",        80.0, 107.0),
    ("CQ-B",       "crew_quarters", 107.0, 167.0),
    ("UWMS",       "uwms",          167.0, 193.0),
    ("CQ-C",       "crew_quarters", 193.0, 253.0),
    ("Hygiene B",  "hygiene",       253.0, 280.0),
    ("CQ-D",       "crew_quarters", 280.0, 340.0),
]
# Deck 2 areas (open plan; only Medical has a curtain line).
C_DECK2 = [
    ("Medical",            "medical",    -45.0,  30.0),
    ("Wardroom",           "galley",      30.0, 150.0),
    ("Galley",             "galley",     150.0, 195.0),
    ("Lounge",             "other",      195.0, 255.0),
    ("Greenhouse",         "greenhouse", 255.0, 315.0),
]
C_WINDOWS = [   # (name, azimuth, width, y0, y1) on deck 2, in the vertical part of the wall
    ("W-N (Earth)", 90.0, 1.00, 3.30, 3.90),
    ("W-SW",       225.0, 1.00, 3.30, 3.90),
]
# Ship's ladder in the lobby, C-local coordinates (x east, z south of the C centre).
C_LADDER = dict(x=-0.75, z_foot=0.50, z_top=-0.45, width=0.60, angle_deg=70.0,
                opening=(-1.25, -0.70, -0.25, 0.70),          # x0, z0, x1, z1 in deck 2
                landing1=(0.30, 0.0, 0.50), landing2=(0.30, 2.60, -0.60))
# Regolith berm around C.
BERM = dict(r0=3.95, crest_w=0.60, height=3.00, slope_run=1.5, az0=55.0, az1=305.0)
BERM["r_crest"] = BERM["r0"] + BERM["crest_w"]                             # 4.55
BERM["r_toe"] = BERM["r_crest"] + BERM["height"] * BERM["slope_run"]       # 9.05

# C equipment, polar: (name, deck, azimuth, r_centre, tangential_len, radial_depth, height, y0_above_deck)
C_EQUIP = []
C_CQ_AZ = {"A": 50.0, "B": 137.0, "C": 223.0, "D": 310.0}
for tag, az in C_CQ_AZ.items():
    C_EQUIP += [
        (f"CQ-{tag} | bunk 2.00x0.85 (top 0.50)",  1, az,        2.77, 2.00, 0.85, 0.50, 0.00),
        (f"CQ-{tag} | water canopy 0.10 (170 L)",  1, az,        2.77, 2.00, 0.85, 0.10, 2.25),
        (f"CQ-{tag} | folding desk 0.50x0.60",     1, az + 20.0, 2.00, 0.50, 0.60, 0.75, 0.00),
        (f"CQ-{tag} | wardrobe 0.50x0.50",         1, az - 21.0, 2.00, 0.50, 0.50, 1.90, 0.00),
    ]
C_EQUIP += [
    ("Hygiene A | wash station",        1,  93.5, 3.05, 0.60, 0.45, 0.90, 0.00),
    ("Hygiene A | towel/dryer locker",  1, 101.0, 2.40, 0.30, 0.50, 1.80, 0.00),
    ("Hygiene B | wash station",        1, 266.5, 3.05, 0.60, 0.45, 0.90, 0.00),
    ("Hygiene B | towel/dryer locker",  1, 274.0, 2.40, 0.30, 0.50, 1.80, 0.00),
    ("UWMS | toilet unit",              1, 180.0, 2.95, 0.50, 0.60, 0.80, 0.00),
    ("UWMS | hand wash",                1, 187.0, 2.20, 0.40, 0.30, 0.90, 0.00),
    # deck 2
    ("Wardroom | table d1.20",          2,  90.0, 2.20, 1.20, 1.20, 0.75, 0.00),
    ("Galley | counter 2.00x0.60",      2, 172.0, 2.85, 2.00, 0.60, 0.90, 0.00),
    ("Galley | fridge-freezer",         2, 160.0, 2.15, 0.60, 0.60, 1.80, 0.00),
    ("Lounge | screen stand",           2, 225.0, 1.75, 1.20, 0.10, 1.60, 0.40),
    ("Greenhouse | growth rack 1",      2, 272.0, 2.65, 1.05, 0.60, 1.80, 0.00),
    ("Greenhouse | growth rack 2",      2, 298.0, 2.65, 1.05, 0.60, 1.80, 0.00),
    ("Medical | treatment bed 2.00x0.75", 2, 0.0, 2.55, 2.00, 0.75, 0.80, 0.00),
    ("Medical | medical rack",          2, 326.5, 2.55, 0.60, 1.05, 1.80, 0.00),
]
# Items that follow the curved wall: (name, deck, az0, az1, r0, r1, height, y0)
C_ARCS = [
    ("Wardroom | wall bench (seat 0.45)", 2,  62.0, 118.0, 2.90, 3.35, 0.45, 0.00),
    ("Lounge | wall sofa (seat 0.45)",    2, 203.0, 247.0, 2.80, 3.35, 0.45, 0.00),
]
C_POSTS_AZ = [20.0, 80.0, 107.0, 167.0, 193.0, 253.0, 280.0, 340.0]     # lobby posts d0.10 at r = 1.50
C_DOORS = {"CQ": 0.70, "Hygiene": 0.65, "UWMS": 0.65}                   # sliding doors on the lobby wall, h 1.95

# ----------------------------------------------------------------------------- B  engineering (two metal segments, axis north-south)
B = dict(r_out=2.20, r_in=2.10, axis_y=PORT_H, cone=0.60, cone_r_out=RING["d_out"] / 2,
         rack_face=1.05, part_t=0.05, bulkhead_t=0.10, equip_h=1.83, ceil=2.40)
B["x"] = D["c"][0]                                                         # axis at x = -6.40
B["floor_half"] = math.sqrt(B["r_in"] ** 2 - B["axis_y"] ** 2)             # 1.897
B["y_bottom"] = B["axis_y"] - B["r_out"]                                   # -1.30
B["y_top"] = B["axis_y"] + B["r_out"]                                      # 3.10


def _stations():
    """Walk north from the hub and return named z stations (world z, negative = north)."""
    z = D["c"][1] - D["r_out"]                     # hub north hull
    st = {"D hull N": z}
    z -= RING["length"];        st["D ring N face"] = z
    z -= TUNNEL["length"];      st["B-U ring S face"] = z
    z -= RING["length"];        st["B-U cone S start"] = z          # hatch plate here
    z -= B["cone"];             st["B-U cyl S"] = z
    st["U1 S"] = z;  z -= 2.10; st["U1 N"] = z
    z -= B["part_t"];           st["U2 S"] = z
    z -= 2.10;                  st["U2 N"] = z
    z -= B["part_t"];           st["U3 S"] = z
    z -= 3.40;                  st["U3 N"] = z;  st["B-U cyl N"] = z
    z -= B["cone"];             st["B-U cone N end"] = z            # hatch plate here
    z -= RING["length"];        st["B-U ring N face"] = z           # ring to ring mating plane
    z -= RING["length"];        st["B-M cone S start"] = z          # hatch plate here
    z -= B["cone"];             st["B-M cyl S"] = z
    st["M1 S"] = z;  z -= 2.40; st["M1 N"] = z
    z -= B["part_t"];           st["M2 S"] = z
    z -= 2.40;                  st["M2 N"] = z
    z -= B["bulkhead_t"];       st["M3 S"] = z                      # pressure bulkhead with IV hatch
    z -= 2.00;                  st["M3 N"] = z;  st["B-M cyl N"] = z
    z -= B["cone"];             st["B-M cone N end"] = z            # EV hatch plate here
    z -= RING["length"];        st["EV ring face"] = z
    return st


ST = _stations()
B_ROOMS = [   # (id, name, zone preset, z south, z north)
    ("U1", "Logistics & stowage",           "logistics", ST["U1 S"], ST["U1 N"]),
    ("U2", "Power & thermal",               "power",     ST["U2 S"], ST["U2 N"]),
    ("U3", "ECLSS bay",                     "eclss",     ST["U3 S"], ST["U3 N"]),
    ("M1", "Workshop",                      "workshop",  ST["M1 S"], ST["M1 N"]),
    ("M2", "Suit room (equipment lock)",    "workshop",  ST["M2 S"], ST["M2 N"]),
    ("M3", "Crew lock (airlock)",           "airlock",   ST["M3 S"], ST["M3 N"]),
]
B_PARTITIONS = [  # (name, z south face, thickness, kind)  kind: "door" = 1.00 x 2.00 opening, "hatch" = pressure bulkhead with H-1
    ("P1 U1/U2", ST["U1 N"], B["part_t"], "door"),
    ("P2 U2/U3", ST["U2 N"], B["part_t"], "door"),
    ("P3 M1/M2", ST["M1 N"], B["part_t"], "door"),
    ("PB M2/M3 pressure bulkhead", ST["M2 N"], B["bulkhead_t"], "hatch"),
]
B_DOOR = dict(w=1.00, h=2.00)
PORCH = dict(length=2.40, width=2.40)      # EVA porch at grade, north of the EV hatch

# B equipment: (room, side, offset from the room's south wall, length along z, depth, height, y0, name, back)
# side "W" / "E": back against that wall. `back` = distance of the item's back face from the axis (default: floor edge).
_FH = None
B_EQUIP = [
    ("U1", "W", 0.00, 1.05, 0.84, 1.83, 0.0, "CTB stowage rack 1", _FH),
    ("U1", "W", 1.05, 1.05, 0.84, 1.83, 0.0, "CTB stowage rack 2", _FH),
    ("U1", "E", 0.00, 1.05, 0.84, 1.83, 0.0, "Cold stowage (freezer)", _FH),
    ("U1", "E", 1.05, 1.05, 0.84, 0.90, 0.0, "Inventory station + trash compactor", _FH),
    ("U2", "W", 0.00, 1.05, 0.60, 1.83, 0.0, "Power distribution cabinet", _FH),
    ("U2", "W", 1.05, 1.05, 0.84, 1.83, 0.0, "Battery rack", _FH),
    ("U2", "E", 0.00, 1.05, 0.84, 1.83, 0.0, "Thermal pump module", _FH),
    ("U2", "E", 1.05, 1.05, 0.60, 1.83, 0.0, "Avionics rack", _FH),
]
for i, nm in enumerate(("ARS-1", "ARS-2", "CO2 reduction", "OGA")):
    B_EQUIP.append(("U3", "W", 0.10 + i * 0.80, 0.77, 0.77, 1.83, 0.0, f"Pallet W{i+1} {nm}", _FH))
for i, nm in enumerate(("WPA-1", "WPA-2", "UPA", "BPA")):
    B_EQUIP.append(("U3", "E", 0.10 + i * 0.80, 0.77, 0.77, 1.83, 0.0, f"Pallet E{i+1} {nm}", _FH))
B_EQUIP += [
    ("M1", "W", 0.00, 1.80, 0.80, 0.90, 0.0, "General workbench", _FH),
    ("M1", "W", 1.80, 0.60, 0.80, 1.83, 0.0, "Tool cabinet", _FH),
    ("M1", "E", 0.00, 0.90, 0.84, 1.83, 0.0, "Additive manufacturing cabinet", _FH),
    ("M1", "E", 1.00, 1.30, 0.80, 0.90, 0.0, "Electronics bench (ESD)", _FH),
    ("M2", "W", 0.05, 0.90, 0.90, 2.00, 0.0, "Suit don/doff stand 1", 1.75),
    ("M2", "W", 0.95, 0.90, 0.90, 2.00, 0.0, "Suit don/doff stand 2", 1.75),
    ("M2", "W", 1.85, 0.55, 0.84, 1.83, 0.0, "Spare suit locker (2 suits)", _FH),
    ("M2", "E", 0.05, 1.20, 0.60, 1.83, 0.0, "PLSS service + recharge station", _FH),
    ("M2", "E", 1.25, 1.10, 0.80, 0.90, 0.0, "Suit maintenance bench", _FH),
    ("M3", "W", 0.30, 0.60, 0.60, 0.60, 0.6, "Sample pass-through locker", _FH),
    ("M3", "W", 1.10, 0.30, 0.20, 1.20, 0.4, "Suit brush / vacuum station 1", _FH),
    ("M3", "E", 0.30, 0.80, 0.20, 0.60, 0.9, "Umbilical interface panel", _FH),
    ("M3", "E", 1.30, 0.30, 0.20, 1.20, 0.4, "Suit brush / vacuum station 2", _FH),
]
# External items on B: (name, x0, z0, x1, z1, y0, y1)
B_EXTERNAL = [
    ("Radiator panel W", B["x"] - 0.65, ST["U1 S"] - 0.4, B["x"] - 0.55, ST["U3 N"] + 0.4, 3.15, 5.15),
    ("Radiator panel E", B["x"] + 0.55, ST["U1 S"] - 0.4, B["x"] + 0.65, ST["U3 N"] + 0.4, 3.15, 5.15),
    ("HP O2 tank 1 (d0.90)", B["x"] - 3.20, ST["U3 S"] - 0.2, B["x"] - 2.30, ST["U3 S"] - 1.6, 0.20, 1.10),
    ("HP O2 tank 2 (d0.90)", B["x"] - 3.20, ST["U3 S"] - 1.8, B["x"] - 2.30, ST["U3 S"] - 3.2, 0.20, 1.10),
    ("HP N2 tank 1 (d0.90)", B["x"] + 2.30, ST["U3 S"] - 0.2, B["x"] + 3.20, ST["U3 S"] - 1.6, 0.20, 1.10),
    ("HP N2 tank 2 (d0.90)", B["x"] + 2.30, ST["U3 S"] - 1.8, B["x"] + 3.20, ST["U3 S"] - 3.2, 0.20, 1.10),
]

# D equipment, polar about the hub centre: (name, azimuth, r_centre, tangential_len, radial_depth, height, y0)
# Each quadrant, counter-clockwise from a port: coaming edge (20 deg), parked hatch leaf (to 50 deg), locker (53..67 deg).
D_EQUIP = [
    ("Emergency locker (masks, extinguishers)",   60.0, 1.87, 0.50, 0.40, 1.80, 0.0),
    ("Caution & warning / hatch control panel",  150.0, 2.00, 0.50, 0.15, 1.20, 1.0),
    ("First response: AED, trauma kit, litter",   240.0, 1.87, 0.50, 0.40, 1.80, 0.0),
    ("Safe-haven consumables (CTB) + O2",         330.0, 1.87, 0.50, 0.40, 1.20, 0.0),
]
D_LEAF_PARK_AZ = [35.0, 125.0, 215.0, 305.0]     # centre of the wall arc where each open hatch leaf rests

# ----------------------------------------------------------------------------- site (approximate; not part of the pressurised design)
SITE = dict(
    fsp=(-60.0, -800.0),            # fission surface power, behind its own berm
    solar=[(-30.0, -45.0), (20.0, -45.0)],
    antenna=(12.0, -14.0),
    lander_pad=(150.0, 10.0),
    ltv=(-1.5, -24.5),
)
PITS = dict(B_trench_w=5.4, B_depth=1.40, D_depth=0.85, C_depth=1.50, tunnel_depth=0.35)


# ----------------------------------------------------------------------------- helpers
def pol(c, az_deg, r):
    """World (x, z) of a point at azimuth/radius from centre c."""
    a = math.radians(az_deg)
    return (c[0] + r * math.cos(a), c[1] - r * math.sin(a))


def b_room(room_id):
    for r in B_ROOMS:
        if r[0] == room_id:
            return r
    raise KeyError(room_id)


def b_equip_boxes():
    """World boxes of B equipment: (name, room, x0, x1, y0, y1, z_south, z_north)."""
    out = []
    for room, side, off, length, depth, height, y0, name, back in B_EQUIP:
        _, _, _, zs, _ = b_room(room)
        z_s = zs - off
        z_n = z_s - length
        bk = B["floor_half"] if back is None else back
        if side == "W":
            x0, x1 = B["x"] - bk, B["x"] - bk + depth
        else:
            x0, x1 = B["x"] + bk - depth, B["x"] + bk
        out.append((f"B-{room} | {name}", room, x0, x1, y0, y0 + height, z_s, z_n))
    return out


def ports():
    """Every hatch plate in the base: (id, description, x, z, azimuth of the outward normal, kind)."""
    dx, dz = D["c"]
    cx, cz = C["c"]
    L = RING["length"]
    return [
        ("H-01", "A west port (new, replaces the maintenance bench)", A["c"][0] - A["r_metal"] - L, 0.0, 180.0, "IV"),
        ("H-02", "D east port",  dx + D["r_out"] + L, dz, 0.0, "IV"),
        ("H-03", "D west port",  dx - D["r_out"] - L, dz, 180.0, "IV"),
        ("H-04", "D north port", dx, dz - D["r_out"] - L, 90.0, "IV"),
        ("H-05", "D south port", dx, dz + D["r_out"] + L, 270.0, "IV"),
        ("H-06", "C east port (rigid frame through the soft goods)", cx + C["r_out"] + L, cz, 0.0, "IV"),
        ("H-07", "B-U south end port", B["x"], ST["B-U cone S start"], 270.0, "IV"),
        ("H-08", "B-U north end port", B["x"], ST["B-U cone N end"], 90.0, "IV"),
        ("H-09", "B-M south end port", B["x"], ST["B-M cone S start"], 270.0, "IV"),
        ("H-10", "Crew lock inner hatch (pressure bulkhead)", B["x"], ST["M2 N"], 90.0, "IV"),
        ("H-11", "EV hatch (crew lock outer)", B["x"], ST["B-M cone N end"], 90.0, "EV"),
        ("H-12", "Rover / logistics port (end of the south stub)", dx, dz + D["r_out"] + L + ROVER_STUB + L, 270.0, "IV"),
    ]


def tunnels():
    """(name, x0, z0, x1, z1) centre-line end points on the ring faces."""
    dx, dz = D["c"]
    L = RING["length"]
    return [
        ("T-AD", A["c"][0] - A["r_metal"] - L, 0.0, dx + D["r_out"] + L, 0.0),
        ("T-DC", dx - D["r_out"] - L, 0.0, C["c"][0] + C["r_out"] + L, 0.0),
        ("T-DB", dx, dz - D["r_out"] - L, dx, ST["B-U ring S face"]),
        ("T-DS (rover stub)", dx, dz + D["r_out"] + L, dx, dz + D["r_out"] + L + ROVER_STUB),
    ]


def sector_area(r0, r1, az0, az1):
    return math.pi * (r1 * r1 - r0 * r0) * (az1 - az0) / 360.0


if __name__ == "__main__":
    print("D centre", D["c"], " C centre", C["c"], " B axis x", B["x"])
    print("B floor half-width %.3f  tunnel floor %.2f headroom %.2f" % (B["floor_half"], TUNNEL["floor_w"], TUNNEL["headroom"]))
    for k, v in ST.items():
        print("  %-20s z = %7.2f" % (k, v))
    for n, t, a0, a1 in C_DECK1:
        print("  %-10s %5.1f deg  %.2f m2" % (n, a1 - a0, sector_area(C["room_r0"], C["r_in"], a0, a1)))
    for r in (1.5, 2.5, 2.8, 3.0, 3.2, 3.35):
        print("  deck-2 headroom at r=%.2f : %.2f" % (r, c_headroom_deck2(r)))
    print("berm r_crest %.2f r_toe %.2f" % (BERM["r_crest"], BERM["r_toe"]))
