## Interior lights for the default base camp, placed in code (one per room or bay), plus the
## "zone colour temperature" rule of the space-setup pipeline: a light that stands inside a zone
## takes that zone's colour temperature (crew quarters warm, machinery cool).
##
## Group "habitat_lights": NoteManager calls apply_zone_tints() whenever zones change.
class_name HabitatLights
extends Node3D

const DEFAULT_K := 4000.0

## [position, kelvin, energy, range, shadows]
const LIGHTS := [
	# A core tower (the NASA reference glb): one per level, tower is at the origin
	[Vector3(0.0, 2.3, 0.0), 4000, 1.6, 5.0, false],
	[Vector3(0.0, 4.9, 0.0), 4000, 1.6, 5.0, false],
	[Vector3(0.0, 7.5, 0.0), 4000, 1.6, 5.0, false],
	# D hub + tunnels
	[Vector3(-7.5, 2.5, 0.0), 4000, 1.2, 4.0, false],
	[Vector3(-4.4, 2.0, 0.0), 4000, 0.6, 2.5, false],
	[Vector3(-10.4, 2.0, 0.0), 4000, 0.6, 2.5, false],
	[Vector3(-7.5, 2.0, -5.9), 4000, 0.8, 4.5, false],
	# B engineering: a line of cool lights along the axis
	[Vector3(-0.6, 3.2, -12.0), 4800, 1.4, 4.5, false],
	[Vector3(-2.8, 3.2, -12.0), 4800, 1.4, 4.5, false],
	[Vector3(-5.5, 3.2, -12.0), 4800, 1.6, 5.0, true],
	[Vector3(-8.8, 3.2, -12.0), 4800, 1.6, 5.0, false],
	[Vector3(-11.4, 3.2, -12.0), 4800, 1.4, 4.5, false],
	[Vector3(-13.2, 3.2, -12.0), 4800, 1.4, 4.5, false],
	[Vector3(-14.8, 3.2, -12.0), 4800, 1.2, 4.0, false],
	# C habitation deck 1: four warm lights over the crew quarters, one in the shelter core
	[Vector3(-12.9, 2.3, 2.1), 3000, 1.1, 4.0, false],
	[Vector3(-17.1, 2.3, 2.1), 3000, 1.1, 4.0, false],
	[Vector3(-17.1, 2.3, -2.1), 3000, 1.1, 4.0, false],
	[Vector3(-12.9, 2.3, -2.1), 3000, 1.1, 4.0, false],
	[Vector3(-15.0, 2.2, 0.0), 3400, 0.9, 3.0, false],
	# C habitation deck 2: wardroom (north), medical (east), exercise (west), greenhouse (south)
	[Vector3(-15.0, 5.2, -1.6), 3200, 1.4, 4.5, true],
	[Vector3(-12.6, 5.2, 0.3), 4500, 1.0, 3.5, false],
	[Vector3(-17.5, 5.2, 0.0), 4500, 1.0, 3.5, false],
	[Vector3(-15.0, 5.2, 2.6), 5500, 1.0, 3.5, false],
]

var _lights: Array[OmniLight3D] = []


func _ready() -> void:
	add_to_group("habitat_lights")
	for spec in LIGHTS:
		var l := OmniLight3D.new()
		l.position = spec[0]
		l.light_color = kelvin_to_color(float(spec[1]))
		l.light_energy = float(spec[2])
		l.omni_range = float(spec[3])
		l.omni_attenuation = 1.4
		l.shadow_enabled = bool(spec[4])
		l.set_meta("base_k", float(spec[1]))
		add_child(l)
		_lights.append(l)


## Lights inside a zone take the zone's colour temperature; others keep their own.
func apply_zone_tints(manager: Node) -> void:
	for l in _lights:
		var z: Dictionary = manager.zone_at(l.global_position - Vector3(0.0, 1.0, 0.0))
		var k := float(l.get_meta("base_k", DEFAULT_K))
		if not z.is_empty() and int(z.get("color_temp_k", 0)) > 0:
			k = float(z["color_temp_k"])
		l.light_color = kelvin_to_color(k)


## Approximate black-body colour (Tanner Helland's fit), normalised so 6500 K is white.
static func kelvin_to_color(k: float) -> Color:
	var t := clampf(k, 1000.0, 12000.0) / 100.0
	var r: float
	var g: float
	var b: float
	if t <= 66.0:
		r = 255.0
		g = 99.4708025861 * log(t) - 161.1195681661
		b = 0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307
	else:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
		b = 255.0
	return Color(clampf(r / 255.0, 0.0, 1.0), clampf(g / 255.0, 0.0, 1.0), clampf(b / 255.0, 0.0, 1.0))
