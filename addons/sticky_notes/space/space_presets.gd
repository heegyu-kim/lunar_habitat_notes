## Zone type presets and noise source presets for the space-setup pipeline.
##
## Zone defaults come from the NASA Surface Habitat function list (see docs/HABITAT_DESIGN.md §2.3).
## quiet / clean / private are 0..1 (1 = quiet, clean, private). noise_limit_db is what the zone tolerates,
## including its own equipment (a workshop puts up with its tools; a crew quarters puts up with very little).
class_name SpacePresets
extends RefCounted

const ZONE_TYPES := {
	"crew_quarters": {"name": "Crew quarters", "quiet": 0.9, "clean": 0.9, "private": 0.9, "noise_limit_db": 35, "color_temp_k": 3000, "color": Color(0.30, 0.40, 0.90), "min_area": "sleep 1.82 + stretch 1.40 m²"},
	"hygiene":       {"name": "Hygiene", "quiet": 0.6, "clean": 0.9, "private": 0.9, "noise_limit_db": 45, "color_temp_k": 3500, "color": Color(0.25, 0.75, 0.80), "min_area": "1.06 m²"},
	"uwms":          {"name": "Toilet (UWMS)", "quiet": 0.6, "clean": 0.9, "private": 0.9, "noise_limit_db": 45, "color_temp_k": 3500, "color": Color(0.20, 0.65, 0.70), "min_area": "0.91 m²"},
	"galley":        {"name": "Galley / wardroom", "quiet": 0.5, "clean": 0.9, "private": 0.1, "noise_limit_db": 65, "color_temp_k": 3000, "color": Color(0.95, 0.60, 0.20), "min_area": "table 1.62 + prep 1.12 m²"},
	"medical":       {"name": "Medical", "quiet": 0.8, "clean": 0.9, "private": 0.6, "noise_limit_db": 45, "color_temp_k": 4500, "color": Color(0.90, 0.25, 0.25), "min_area": "1.87 m²"},
	"exercise":      {"name": "Exercise", "quiet": 0.1, "clean": 0.8, "private": 0.2, "noise_limit_db": 75, "color_temp_k": 4500, "color": Color(0.95, 0.85, 0.20), "min_area": "1.50 m²"},
	"lab":           {"name": "Lab / workstation", "quiet": 0.5, "clean": 0.8, "private": 0.2, "noise_limit_db": 60, "color_temp_k": 4500, "color": Color(0.35, 0.75, 0.35), "min_area": "1.37 m²"},
	"eclss":         {"name": "ECLSS / machinery", "quiet": 0.1, "clean": 0.5, "private": 0.1, "noise_limit_db": 80, "color_temp_k": 5000, "color": Color(0.55, 0.55, 0.60), "min_area": "1.0 m aisle in front of pallets"},
	"power":         {"name": "Power & thermal", "quiet": 0.1, "clean": 0.5, "private": 0.1, "noise_limit_db": 80, "color_temp_k": 5000, "color": Color(0.45, 0.45, 0.55), "min_area": ""},
	"workshop":      {"name": "Workshop / maintenance", "quiet": 0.2, "clean": 0.2, "private": 0.1, "noise_limit_db": 85, "color_temp_k": 4500, "color": Color(0.60, 0.40, 0.25), "min_area": "1.37 m²"},
	"logistics":     {"name": "Logistics / stowage", "quiet": 0.5, "clean": 0.5, "private": 0.1, "noise_limit_db": 55, "color_temp_k": 4000, "color": Color(0.80, 0.70, 0.50), "min_area": ""},
	"airlock":       {"name": "Airlock / dust vestibule", "quiet": 0.1, "clean": 0.1, "private": 0.1, "noise_limit_db": 80, "color_temp_k": 5000, "color": Color(0.65, 0.30, 0.20), "min_area": "5.0 m², 2.6 m headroom"},
	"corridor":      {"name": "Corridor / hub", "quiet": 0.5, "clean": 0.5, "private": 0.1, "noise_limit_db": 65, "color_temp_k": 4000, "color": Color(0.85, 0.85, 0.85), "min_area": "1.0 m wide"},
	"greenhouse":    {"name": "Greenhouse", "quiet": 0.8, "clean": 0.8, "private": 0.2, "noise_limit_db": 45, "color_temp_k": 5500, "color": Color(0.55, 0.85, 0.30), "min_area": ""},
	"shelter":       {"name": "Storm shelter", "quiet": 0.8, "clean": 0.8, "private": 0.3, "noise_limit_db": 45, "color_temp_k": 3500, "color": Color(0.60, 0.35, 0.80), "min_area": "4 days for the whole crew"},
	"other":         {"name": "Other", "quiet": 0.5, "clean": 0.5, "private": 0.3, "noise_limit_db": 55, "color_temp_k": 4000, "color": Color(0.70, 0.70, 0.70), "min_area": ""},
}

## Order shown in menus.
const ZONE_ORDER := ["crew_quarters", "hygiene", "uwms", "galley", "medical", "exercise", "lab", "eclss", "power", "workshop", "logistics", "airlock", "corridor", "greenhouse", "shelter", "other"]

## Noise emitters: sound level 1 m from the source.
const NOISE_TYPES := {
	"fan":        {"name": "Fan (ARS / cabin air)", "db": 65},
	"pump":       {"name": "Pump (water / thermal)", "db": 65},
	"compressor": {"name": "Compressor", "db": 75},
	"exercise":   {"name": "Exercise device", "db": 70},
	"talk":       {"name": "Conversation", "db": 60},
	"tools":      {"name": "Workshop tools", "db": 80},
	"other":      {"name": "Other", "db": 60},
}
const NOISE_ORDER := ["fan", "pump", "compressor", "exercise", "talk", "tools", "other"]


static func zone_type(key: String) -> Dictionary:
	return ZONE_TYPES.get(key, ZONE_TYPES["other"])


static func zone_type_name(key: String) -> String:
	return str(zone_type(key)["name"])


static func zone_color(key: String) -> Color:
	return zone_type(key)["color"]


static func noise_type(key: String) -> Dictionary:
	return NOISE_TYPES.get(key, NOISE_TYPES["other"])
