class_name StickyNote
extends Node3D
## 월드에 붙어 있는 노트 한 장. 코드로만 만들어져서 .tscn이 필요 없다.
##
## 멀리서  유형 색 구슬(핀) + 역할 머리글자. 답글 수는 아래 작은 숫자.
## 가까이  (3m 안, 조준 중, 또는 패널에서 보는 중) 핀 위로 카드가 펼쳐진다.
## 충돌    같은 부재에 Constraint와 Proposal이 함께 있으면 핀이 느리게 숨쉰다.

const PIN_RADIUS := 0.045
const CARD_DISTANCE := 3.0
const CARD_W := 0.32
const CARD_H := 0.17

var note: NoteData
var aimed: bool = false            # NotePlacer가 매 프레임 넣어준다

var _pin: MeshInstance3D
var _pin_mat: StandardMaterial3D
var _initial: Label3D
var _badge: Label3D
var _card: Node3D
var _card_mat: StandardMaterial3D
var _card_type: Label3D
var _card_text: Label3D
var _card_meta: Label3D
var _conflict: bool = false
var _focused: bool = false
var _card_scale: float = 0.0
var _t: float = 0.0


func _init() -> void:
	# ---- 핀 ----
	_pin = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = PIN_RADIUS
	sm.height = PIN_RADIUS * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	_pin.mesh = sm
	_pin_mat = StandardMaterial3D.new()
	_pin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 반투명 외피(inflatable shell) 메시보다 나중에 그린다. 깊이 테스트는 그대로라 벽 뒤에선 가려진다.
	_pin_mat.render_priority = 8
	_pin.material_override = _pin_mat
	add_child(_pin)

	_initial = _make_label(0.0011, 56, Color(0.08, 0.08, 0.08))
	_initial.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_initial.no_depth_test = true
	_initial.render_priority = 10
	add_child(_initial)

	_badge = _make_label(0.0008, 30, Color(0.95, 0.95, 0.95))
	_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_badge.no_depth_test = true
	_badge.render_priority = 10
	_badge.position = Vector3(0.0, -0.085, 0.0)
	add_child(_badge)

	# ---- 카드 (핀 위쪽, 표면과 평행) ----
	_card = Node3D.new()
	_card.position = Vector3(0.0, PIN_RADIUS + CARD_H * 0.5 + 0.03, 0.012)
	add_child(_card)

	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(CARD_W, CARD_H)
	quad.mesh = qm
	_card_mat = StandardMaterial3D.new()
	_card_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_card_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_card_mat.render_priority = 8
	quad.material_override = _card_mat
	_card.add_child(quad)

	var band := MeshInstance3D.new()
	var bm := QuadMesh.new()
	bm.size = Vector2(0.012, CARD_H)
	band.mesh = bm
	band.position = Vector3(-CARD_W * 0.5 + 0.006, 0.0, 0.001)
	var band_mat := StandardMaterial3D.new()
	band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_mat.albedo_color = Color(0.08, 0.08, 0.08)
	band_mat.render_priority = 8
	band.material_override = band_mat
	_card.add_child(band)

	_card_type = _make_label(0.0007, 30, Color(0.12, 0.12, 0.12))
	_card_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_card_type.position = Vector3(-CARD_W * 0.5 + 0.03, CARD_H * 0.5 - 0.022, 0.002)
	_card.add_child(_card_type)

	_card_text = _make_label(0.0007, 30, Color(0.06, 0.06, 0.06))
	_card_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_card_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_text.width = (CARD_W - 0.05) / 0.0007
	_card_text.position = Vector3(-CARD_W * 0.5 + 0.03, CARD_H * 0.5 - 0.045, 0.002)
	_card.add_child(_card_text)

	_card_meta = _make_label(0.0006, 26, Color(0.25, 0.25, 0.25))
	_card_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_card_meta.position = Vector3(-CARD_W * 0.5 + 0.03, -CARD_H * 0.5 + 0.018, 0.002)
	_card.add_child(_card_meta)

	_card.visible = false
	_card.scale = Vector3.ONE * 0.001

	# ---- 클릭 영역 ----
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = PIN_RADIUS * 1.6
	cs.shape = shape
	area.add_child(cs)
	add_child(area)


func _make_label(pixel: float, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.pixel_size = pixel
	l.font_size = size
	l.modulate = color
	l.outline_size = 0
	l.render_priority = 9
	return l


## NoteManager가 add_child 한 다음에 호출한다.
func setup(n: NoteData) -> void:
	note = n
	_place()
	refresh()


## 표면 법선(normal) 쪽을 바라보도록 세운다. 노트의 +Z가 법선 방향.
func _place() -> void:
	var n := note.normal.normalized()
	if n.length() < 0.5:
		n = Vector3.UP
	global_position = note.position + n * 0.01
	var up := Vector3.UP
	if absf(n.dot(Vector3.UP)) > 0.95:
		up = Vector3.FORWARD
	global_transform.basis = Basis.looking_at(-n, up)


func refresh() -> void:
	if note == null:
		return
	visible = NoteManager.type_visible[clampi(note.type, 0, 4)]
	_conflict = (not note.resolved) and NoteManager.is_conflict(note.anchor_name)
	_focused = NoteManager.focused_id == note.id

	var c := note.color()
	if note.resolved:
		_pin_mat.albedo_color = Color(0.55, 0.55, 0.55, 0.55)
		_card_mat.albedo_color = Color(0.82, 0.82, 0.82)
	else:
		_pin_mat.albedo_color = c
		_card_mat.albedo_color = c.lerp(Color.WHITE, 0.55)

	_initial.text = note.role_initial()
	var replies := NoteManager.replies_of(note.id).size()
	var badge := ""
	if replies > 0:
		badge = "+%d" % replies
	if note.resolved:
		badge = ("✓ " + badge).strip_edges()
	_badge.text = badge

	_card_type.text = note.type_name().to_upper() + ("   RESOLVED" if note.resolved else "")
	_card_text.text = note.short_text(90) if note.text != "" else "(voice note)"
	_card_meta.text = "%s · %s · %s" % [note.role_name(), note.author, note.short_time()]


func _process(delta: float) -> void:
	if note == null:
		return
	_t += delta
	var near := false
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		near = cam.global_position.distance_to(global_position) < CARD_DISTANCE
	var want_card := near or aimed or _focused
	_card_scale = move_toward(_card_scale, 1.0 if want_card else 0.0, delta * 7.0)
	_card.visible = _card_scale > 0.01
	_card.scale = Vector3.ONE * maxf(_card_scale, 0.001)

	var s := 1.0
	if _conflict:
		s += 0.3 * (0.5 + 0.5 * sin(_t * 3.5))
	if _focused:
		s *= 1.35
	elif aimed:
		s *= 1.15
	_pin.scale = Vector3.ONE * s
