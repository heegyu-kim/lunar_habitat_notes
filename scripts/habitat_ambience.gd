extends Node3D
## Fixed 3D emitters with smooth floor-to-floor level changes. Note audio is independent.

const DECK_HEIGHT := 2.6
# Gains in dB for decks 1, 2 and 3. Distance falloff is applied by the players.
const MIX_BY_SOURCE := {
	"VentCeiling": Vector3(-16, -11, -4),
	"PipeDeck2": Vector3(-23, -10, -18),
	"PipeDeck3": Vector3(-25, -17, -7),
	"MachineRoomDeck2": Vector3(-32, -3, -26),
	"DryMachineDeck2": Vector3(-31, -9, -26),
}

const LOCAL_FILES := {
	"VentCeiling": "vent_ceiling_loop.wav",
	"PipeDeck2": "pipe_flow_loop.wav",
	"PipeDeck3": "pipe_flow_loop.wav",
	"MachineRoomDeck2": "machine_room_loop.wav",
	"DryMachineDeck2": "machine_dry_3s_10s_pause.wav",
}

@onready var _xr_origin := get_parent().get_node("XROrigin3D") as XROrigin3D
var _emitters: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	for source_name in MIX_BY_SOURCE:
		var player := get_node(source_name) as AudioStreamPlayer3D
		var path := "res://assets/audio/" + String(LOCAL_FILES[source_name])
		if not ResourceLoader.exists(path):
			continue
		var sample := load(path) as AudioStreamWAV
		if not sample or sample.get_length() <= 0.0:
			continue
		player.stream = sample
		sample.loop_begin = 0
		sample.loop_end = roundi(sample.get_length() * sample.mix_rate)
		sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_emitters.append(player)
	_apply_mix(0.0, INF)
	for player in _emitters:
		# Keep the two pipe emitters from playing the same water pulse in sync.
		player.play(11.0 if player.name == &"PipeDeck3" else 0.0)


func _process(delta: float) -> void:
	var feet := _xr_origin if get_viewport().use_xr else get_parent().get_node_or_null("DesktopPlayer") as Node3D
	if feet:
		_apply_mix(feet.global_position.y, delta * 28.0)


func _apply_mix(elevation: float, max_db_step: float) -> void:
	var deck := clampf(elevation / DECK_HEIGHT, 0.0, 2.0)
	for player in _emitters:
		var gains: Vector3 = MIX_BY_SOURCE[String(player.name)]
		var target := lerpf(gains.x, gains.y, deck) if deck < 1.0 else lerpf(gains.y, gains.z, deck - 1.0)
		player.volume_db = move_toward(player.volume_db, target, max_db_step)
