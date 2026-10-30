class_name ClipTheater
extends Node3D
## 몰입 재생. 노트를 남긴 사람의 자리·시선으로 들어가서, 그 사람이 녹화한 화면을
## 눈앞에 머리 고정으로 펼친다. 들어갈 때와 나올 때 검게 페이드.
##
##   enter(note)  페이드 → 텔레포트 → 화면 + 소리
##   exit()       페이드 → 원래 자리로 → 밝아짐
## 재생 중에는 XRNotePlacer 가 트리거 탭을 exit() 로 넘긴다.

signal started
signal finished

const FADE_SEC := 0.45
const SCREEN_DIST := 2.4
const SCREEN_W := 3.6     # 16:9

var active: bool = false
var camera: XRCamera3D
var origin: XROrigin3D

var _fade: MeshInstance3D
var _fade_mat: StandardMaterial3D
var _screen: Node3D
var _screen_mesh: MeshInstance3D
var _screen_mat: StandardMaterial3D
var _badge: Label3D
var _frames := ClipFrames.new()
var _audio: AudioStreamPlayer
var _has_audio: bool = false
var _t: float = 0.0
var _playing: bool = false
var _return_pos: Vector3 = Vector3.ZERO
var _return_basis: Basis = Basis.IDENTITY
var _fade_target: float = 0.0
var _fade_value: float = 0.0


func _init() -> void:
	# 페이드: 머리 바로 앞 검은 판 (카메라 자식으로 붙인다)
	_fade = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(4.0, 4.0)
	_fade.mesh = qm
	_fade_mat = StandardMaterial3D.new()
	_fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_mat.no_depth_test = true
	_fade_mat.render_priority = 120
	_fade_mat.albedo_color = Color(0, 0, 0, 0)
	_fade.material_override = _fade_mat
	_fade.position = Vector3(0, 0, -0.25)
	_fade.visible = false

	# 화면
	_screen = Node3D.new()
	_screen.visible = false
	_screen_mesh = MeshInstance3D.new()
	var sm := QuadMesh.new()
	sm.size = Vector2(SCREEN_W, SCREEN_W * 9.0 / 16.0)
	_screen_mesh.mesh = sm
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.no_depth_test = true
	_screen_mat.render_priority = 100
	_screen_mesh.material_override = _screen_mat
	_screen_mesh.position = Vector3(0, 0, -SCREEN_DIST)
	_screen.add_child(_screen_mesh)

	_badge = Label3D.new()
	_badge.text = "●  PLAYBACK"
	_badge.font_size = 40
	_badge.pixel_size = 0.0012
	_badge.modulate = Color(1, 0.35, 0.3)
	_badge.outline_size = 8
	_badge.no_depth_test = true
	_badge.render_priority = 110
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge.position = Vector3(SCREEN_W * 0.5 - 0.05, SCREEN_W * 9.0 / 32.0 + 0.12, -SCREEN_DIST)
	_screen.add_child(_badge)

	_audio = AudioStreamPlayer.new()
	add_child(_audio)


func attach(cam: XRCamera3D, org: XROrigin3D) -> void:
	camera = cam
	origin = org
	camera.add_child(_fade)
	camera.add_child(_screen)


func enter(note: NoteData) -> void:
	if active or camera == null:
		return
	if not _frames.load(note) or not _frames.ready:
		return
	active = true
	started.emit()
	_return_pos = origin.global_position
	_return_basis = origin.global_transform.basis
	_has_audio = false
	if _frames.audio_file != "":
		_audio.stream = NoteManager.load_audio(_frames.audio_file)
		_has_audio = _audio.stream != null
	await _fade_to(1.0)
	_teleport(note.camera_position, note.camera_rotation)
	_screen_mat.albedo_texture = _frames.texture_index(1)
	_screen.visible = true
	_t = 0.0
	_playing = true
	if _has_audio:
		_audio.play()
	await _fade_to(0.0)


func exit() -> void:
	if not active or not _playing:
		return
	_playing = false
	_audio.stop()
	await _fade_to(1.0)
	_screen.visible = false
	origin.global_position = _return_pos
	origin.global_transform.basis = _return_basis
	await _fade_to(0.0)
	active = false
	finished.emit()


func _process(delta: float) -> void:
	# 페이드
	if _fade_value != _fade_target:
		_fade_value = move_toward(_fade_value, _fade_target, delta / FADE_SEC)
		_fade_mat.albedo_color = Color(0, 0, 0, _fade_value)
		_fade.visible = _fade_value > 0.001
	if not _playing:
		return
	_t = _audio.get_playback_position() if _has_audio and _audio.playing else _t + delta
	_screen_mat.albedo_texture = _frames.texture_at(_t)
	var done := (_has_audio and not _audio.playing) or (not _has_audio and _t >= _frames.duration)
	if done:
		exit()


func _fade_to(v: float) -> void:
	_fade_target = v
	while absf(_fade_value - _fade_target) > 0.001:
		await get_tree().process_frame


## 머리를 그 사람의 눈 위치·시선 yaw 로 맞춘다
func _teleport(cam_pos: Vector3, cam_rot: Vector3) -> void:
	var current_yaw := camera.global_transform.basis.get_euler().y
	var pivot := camera.global_position
	origin.global_rotate(Vector3.UP, cam_rot.y - current_yaw)
	var shift := pivot - camera.global_position
	shift.y = 0.0
	origin.global_position += shift
	# 높이도 옮긴다. 다른 데크에서 녹화한 클립이면 그 데크로 간다 (lunar habitat 통합).
	origin.global_position += cam_pos - camera.global_position
