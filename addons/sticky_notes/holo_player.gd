class_name HoloPlayer
extends Node3D
## Plays a Holonote back as a ghost in world space: a translucent head with a visor, a hint of a
## torso, both hands with a short pointing ray, and the author's name. The voice comes from the
## ghost's head (3D audio), and the motion follows the voice clock so lips and gestures stay in sync.
##
## Owned by NoteManager (play_holo / stop_holo_playback). Works the same on desktop and in VR.

signal started(note_id: String)
signal finished(note_id: String)

const FADE_SEC := 0.3
const END_HOLD_SEC := 0.4         # keep the last pose briefly before fading out
const GHOST_ALPHA := 0.55
const RAY_LEN := 0.6

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


func _init() -> void:
	name = "HoloPlayer"
	visible = false
	top_level = true

	_head = Node3D.new()
	add_child(_head)
	var skull := _mesh(_sphere(0.11, 0.25), 1.0)
	skull.scale = Vector3(0.85, 1.0, 1.0)
	_head.add_child(skull)
	var visor := _mesh(_box(Vector3(0.17, 0.06, 0.05)), 1.6)
	visor.position = Vector3(0.0, 0.015, -0.085)
	_head.add_child(visor)

	_torso = _mesh(_capsule(0.17, 0.62), 0.55)
	add_child(_torso)

	for side in ["left", "right"]:
		var hand := Node3D.new()
		var palm := _mesh(_box(Vector3(0.075, 0.03, 0.11)), 1.0)
		hand.add_child(palm)
		var ray := _mesh(_cylinder(0.004, RAY_LEN), 0.6)
		ray.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		ray.position = Vector3(0.0, 0.0, -0.055 - RAY_LEN * 0.5)
		hand.add_child(ray)
		add_child(hand)
		_hands[side] = hand

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
	_apply_pose()
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


## Where to stand to watch a holonote: behind and to the right of the author's starting point,
## looking the same way, pulled in if a wall is in the way. Returns [camera_position, camera_rotation].
func viewer_spot(m: HoloMotion, back: float = 1.3, side: float = 0.5) -> Array:
	var head := m.pose_at("head", 0.0)
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var yaw := atan2(-fwd.x, -fwd.z)
	var want := head.origin - fwd * back + right * side
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(head.origin, want)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var p: Vector3 = hit["position"]
			want = head.origin + (p - head.origin) * maxf(0.0, 1.0 - 0.3 / maxf(head.origin.distance_to(p), 0.01))
	return [want, Vector3(0.0, yaw, 0.0)]


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
	_apply_pose()
	if _ending > END_HOLD_SEC and _alpha <= 0.0:
		stop()


func _apply_pose() -> void:
	var tt := minf(t, motion.duration)
	var head := motion.pose_at("head", tt)
	_head.global_transform = head
	# Torso: under the head, upright, turned with the head's yaw only.
	var fwd := -head.basis.z
	fwd.y = 0.0
	var yaw := atan2(-fwd.x, -fwd.z) if fwd.length() > 0.01 else 0.0
	_torso.global_transform = Transform3D(Basis(Vector3.UP, yaw), head.origin + Vector3(0.0, -0.5, 0.0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.05))
	_label.global_position = head.origin + Vector3(0.0, 0.26, 0.0)
	for side in _hands:
		var hand: Node3D = _hands[side]
		if not motion.has_track(side):
			continue
		hand.global_transform = motion.pose_at(side, tt)
		hand.visible = motion.valid_at(side, tt)
	for mat in _mats:
		mat.albedo_color.a = GHOST_ALPHA * _alpha * float(mat.get_meta("a", 1.0))
	_label.modulate.a = _alpha
	_label.outline_modulate.a = _alpha


# ---------------- mesh helpers ----------------

func _mesh(m: Mesh, brightness: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.set_meta("k", brightness)
	mat.set_meta("a", 0.5 if brightness < 0.7 else 1.0)   # torso and rays are fainter
	mi.material_override = mat
	_mats.append(mat)
	return mi


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
