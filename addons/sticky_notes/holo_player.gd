class_name HoloPlayer
extends Node3D
## Plays a Holonote back as a ghost in world space: a hologram full body (HoloAvatar: always standing,
## 1.6 m tall, head turns, arms reach with IK, hands point, feet step), a headset, a short pointing ray
## from each hand, a ring on the floor and the author's name. If the avatar model is missing it falls back to a simple head, torso and hands. The voice comes from the
## ghost's head (3D audio), and the motion follows the voice clock so lips and gestures stay in sync.
##
## Owned by NoteManager (play_holo / stop_holo_playback). Works the same on desktop and in VR.

signal started(note_id: String)
signal finished(note_id: String)

const FADE_SEC := 0.3
const END_HOLD_SEC := 0.4         # keep the last pose briefly before fading out
const GHOST_ALPHA := 0.55
const RAY_LEN := 0.6
const BODY_SHADER := preload("res://addons/sticky_notes/shaders/holo_body.gdshader")
const BASE_SHADER := preload("res://addons/sticky_notes/shaders/holo_base.gdshader")
const RAY_SHADER := preload("res://addons/sticky_notes/shaders/holo_ray.gdshader")
const BASE_SIZE := 0.95           # metres across the ring on the floor

var playing: bool = false
var note_id: String = ""
var t: float = 0.0
var motion: HoloMotion = null

var _head: Node3D
var _torso: MeshInstance3D
var _hands: Dictionary = {}        # "left" / "right" -> Node3D
var _label: Label3D
var _voice: AudioStreamPlayer3D
var _mats: Array[StandardMaterial3D] = []
var _has_audio: bool = false
var _alpha: float = 0.0
var _ending: float = -1.0          # time since the motion ended, -1 while still playing
var _avatar: HoloAvatar = null     # full body, null if the model could not be set up
var _simple: Array[Node3D] = []    # simple-ghost parts hidden when the avatar works
var _holo_mats: Array[ShaderMaterial] = []   # hologram shader materials (tint, alpha, floor_y)
var _base: MeshInstance3D          # ring on the floor under the body


func _init() -> void:
	name = "HoloPlayer"
	visible = false
	top_level = true

	_head = Node3D.new()
	add_child(_head)
	var skull := _mesh(_sphere(0.11, 0.25), 1.0)
	skull.scale = Vector3(0.85, 1.0, 1.0)
	_head.add_child(skull)
	_simple.append(skull)
	# Headset: a rounded bar over the eyes with a brighter lens strip.
	var visor := MeshInstance3D.new()
	visor.mesh = _capsule(0.043, 0.2)
	visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visor.material_override = _holo_mat(1.5, 0.7)
	visor.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	visor.scale = Vector3(1.0, 1.0, 0.8)
	visor.position = Vector3(0.0, 0.012, -0.088)
	_head.add_child(visor)
	var lens := MeshInstance3D.new()
	lens.mesh = _capsule(0.016, 0.15)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens.material_override = _holo_mat(2.6, 0.95)
	lens.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	lens.scale = Vector3(1.0, 1.0, 0.5)
	lens.position = Vector3(0.0, 0.012, -0.121)
	_head.add_child(lens)

	_torso = _mesh(_capsule(0.17, 0.62), 0.55)
	add_child(_torso)
	_simple.append(_torso)

	for side in ["left", "right"]:
		var hand := Node3D.new()
		var palm := _mesh(_box(Vector3(0.075, 0.03, 0.11)), 1.0)
		hand.add_child(palm)
		_simple.append(palm)
		var ray := MeshInstance3D.new()
		ray.mesh = _cylinder(0.005, RAY_LEN)
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ray_mat := ShaderMaterial.new()
		ray_mat.shader = RAY_SHADER
		ray_mat.render_priority = 2
		_holo_mats.append(ray_mat)
		ray.material_override = ray_mat
		ray.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		ray.position = Vector3(0.0, 0.0, -0.055 - RAY_LEN * 0.5)
		hand.add_child(ray)
		add_child(hand)
		_hands[side] = hand

	_base = MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(BASE_SIZE, BASE_SIZE)
	_base.mesh = quad
	_base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var base_mat := ShaderMaterial.new()
	base_mat.shader = BASE_SHADER
	base_mat.render_priority = 1
	_holo_mats.append(base_mat)
	_base.material_override = base_mat
	_base.visible = false
	add_child(_base)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 36
	_label.pixel_size = 0.0018
	_label.outline_size = 10
	_label.no_depth_test = true
	_label.render_priority = 20
	add_child(_label)

	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 3.0
	_voice.max_db = 3.0
	_head.add_child(_voice)


func _ready() -> void:
	# The avatar needs to be in the tree to wire its IK targets.
	var avatar := HoloAvatar.new()
	avatar.name = "Avatar"
	add_child(avatar)
	if avatar.setup(_holo_mat(1.0, 0.34)):
		_avatar = avatar
		_base.visible = true
		for n in _simple:
			n.visible = false
	else:
		avatar.queue_free()


## Starts playback. False if the motion is empty.
func play(note: NoteData, m: HoloMotion) -> bool:
	stop()
	if m == null or m.frame_count < 2:
		return false
	motion = m
	note_id = note.id
	var c := NoteData.type_color(note.type).lightened(0.25)
	for mat in _mats:
		var k: float = mat.get_meta("k", 1.0)
		mat.albedo_color = Color(c.r * k, c.g * k, c.b * k, 0.0)
	# The hologram keeps more of the note type's own colour than the simple ghost (its rim adds the light).
	var hc := NoteData.type_color(note.type).lightened(0.08)
	for hm in _holo_mats:
		hm.set_shader_parameter("tint", Vector3(hc.r, hc.g, hc.b))
		hm.set_shader_parameter("alpha", 0.0)
	_label.text = "%s · %s" % [note.author if note.author != "" else "Guest", note.role_name()]
	_label.modulate = Color(1, 1, 1, 0)
	_label.outline_modulate = Color(0, 0, 0, 0)
	for side in _hands:
		(_hands[side] as Node3D).visible = motion.has_track(side)
	_has_audio = false
	if motion.audio_file != "":
		_voice.stream = NoteManager.load_audio(motion.audio_file)
		_has_audio = _voice.stream != null
	t = 0.0
	_alpha = 0.0
	_ending = -1.0
	_apply_pose(0.0, true)
	visible = true
	playing = true
	if _has_audio:
		_voice.play()
	started.emit(note_id)
	return true


func stop() -> void:
	if not playing:
		return
	playing = false
	_voice.stop()
	visible = false
	var id := note_id
	note_id = ""
	finished.emit(id)


## Where to stand to watch a holonote. Tries spots around the author's starting point (behind first,
## so you see what they point at, then the sides, then in front) and takes the first one with
## MIN_CLEAR metres of free line of sight to the ghost's head. In a cramped room with no clear spot it
## takes the one with the most room. You always look toward the area in front of the author.
## Returns [camera_position, camera_rotation].
const VIEW_SPOTS: Array[Vector2] = [
	Vector2(1.3, 0.5), Vector2(1.3, -0.5), Vector2(1.1, 0.0),       # behind (back, side)
	Vector2(0.2, 1.2), Vector2(0.2, -1.2),                          # beside
	Vector2(-1.0, 0.9), Vector2(-1.0, -0.9),                        # in front, three-quarter view
]
const MIN_CLEAR := 1.0
const WALL_MARGIN := 0.3


func viewer_spot(m: HoloMotion) -> Array:
	var head := m.pose_at("head", 0.0)
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var look_at_pt := head.origin + fwd * 1.0
	var best := Vector3.ZERO
	var best_clear := -1.0
	for o in VIEW_SPOTS:
		var want := head.origin - fwd * o.x + right * o.y
		var dist := head.origin.distance_to(want)
		var clear := dist
		if is_inside_tree():
			var dir := (want - head.origin).normalized()
			var q := PhysicsRayQueryParameters3D.create(head.origin, want + dir * WALL_MARGIN)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				clear = head.origin.distance_to(hit["position"]) - WALL_MARGIN
		var spot := head.origin + (want - head.origin).normalized() * clampf(clear, 0.0, dist)
		if clear >= minf(MIN_CLEAR, dist):
			best = spot
			break
		if clear > best_clear:
			best_clear = clear
			best = spot
	var to := look_at_pt - best
	var yaw := atan2(-to.x, -to.z)
	return [best, Vector3(0.0, yaw, 0.0)]


func _process(delta: float) -> void:
	if not playing:
		return
	# Follow the voice clock, smoothed: playback_position only moves once per audio mix.
	t += delta
	if _has_audio and _voice.playing:
		var a := _voice.get_playback_position()
		if absf(a - t) > 0.08:
			t = a
	var done := t >= motion.duration and not (_has_audio and _voice.playing)
	if done:
		_ending = maxf(_ending, 0.0) + delta
	# Fade in at the start, out at the end.
	var target := 0.0 if _ending > END_HOLD_SEC else 1.0
	_alpha = move_toward(_alpha, target, delta / FADE_SEC)
	_apply_pose(delta)
	if _ending > END_HOLD_SEC and _alpha <= 0.0:
		stop()


func _apply_pose(delta: float, snap: bool = false) -> void:
	var tt := minf(t, motion.duration)
	var head := motion.pose_at("head", tt)
	# The full body always stands at its own height, so everything recorded moves up or down with it.
	var lift := Vector3.ZERO
	if _avatar != null:
		var hands := {}
		for side in ["left", "right"]:
			hands[side] = motion.pose_at(side, tt) if motion.valid_at(side, tt) else null
		_avatar.drive(head, hands, delta, snap)
		lift = Vector3.UP * _avatar.lift()
	_head.global_transform = Transform3D(head.basis, head.origin + lift)
	# Torso: under the head, upright, turned with the head's yaw only.
	var fwd := -head.basis.z
	fwd.y = 0.0
	var yaw := atan2(-fwd.x, -fwd.z) if fwd.length() > 0.01 else 0.0
	_torso.global_transform = Transform3D(Basis(Vector3.UP, yaw), head.origin + Vector3(0.0, -0.5, 0.0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.05))
	_label.global_position = head.origin + lift + Vector3(0.0, 0.26, 0.0)
	for side in _hands:
		var hand: Node3D = _hands[side]
		if not motion.has_track(side):
			continue
		var hp := motion.pose_at(side, tt)
		hand.global_transform = Transform3D(hp.basis, hp.origin + lift)
		hand.visible = motion.valid_at(side, tt)
	for mat in _mats:
		mat.albedo_color.a = GHOST_ALPHA * _alpha * float(mat.get_meta("a", 1.0))
	var floor_y := -1000.0
	if _avatar != null:
		floor_y = _avatar.floor_height()
		var gp := _avatar.ground_point()
		_base.global_transform = Transform3D(Basis.IDENTITY, gp + Vector3(0.0, 0.012, 0.0))
	for hm in _holo_mats:
		hm.set_shader_parameter("alpha", _alpha)
		hm.set_shader_parameter("floor_y", floor_y)
	_label.modulate.a = _alpha
	_label.outline_modulate.a = _alpha


# ---------------- mesh helpers ----------------

## Hologram material: the colour pass only.
## NOT the depth-only pre-pass (holo_depth.gdshader as the first pass with this as next_pass): on the
## Quest 3, that pass on the skinned body with foveated rendering (VRS) faults the GPU and crashes
## the app ("Vulkan device was lost") within seconds of playback. Found with an on-device probe,
## 2026-11-18. Cost: where an arm crosses the chest, the chest shows faintly through it.
func _holo_mat(brightness: float, core_alpha: float) -> ShaderMaterial:
	var color := ShaderMaterial.new()
	color.shader = BODY_SHADER
	color.render_priority = 1
	color.set_shader_parameter("brightness", brightness)
	color.set_shader_parameter("core_alpha", core_alpha)
	_holo_mats.append(color)
	return color

func _mesh(m: Mesh, brightness: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _ghost_mat(brightness, 0.5 if brightness < 0.7 else 1.0)   # torso and rays are fainter
	return mi


## Translucent ghost material, tinted by note type in play(). Depth pre-pass so a body does not show
## its own inside through itself.
func _ghost_mat(brightness: float, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.set_meta("k", brightness)
	mat.set_meta("a", alpha)
	_mats.append(mat)
	return mat


static func _sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 24
	m.rings = 12
	return m


static func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


static func _cylinder(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 6
	return m
