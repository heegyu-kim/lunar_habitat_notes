class_name WristBoard
extends Node3D
## 왼손에 붙는 보드. 기존 2D UI(NotePanel, IdentityCard)를 SubViewport에 그려서
## 쿼드에 입힌다. 오른손 광선이 닿는 지점을 마우스 이벤트로 바꿔 넘기므로
## 버튼·탭·드롭다운이 데스크톱과 똑같이 동작한다.
##
##   맨 위 한 줄   나 (이름 · 역할) + 유형 칩 다섯 개 (누르면 표시/숨김)
##   그 아래      NotePanel (Note / List / Session)
##   맨 아래      컨트롤러 안내

const VIEW_W := 560
const VIEW_H := 760
const BOARD_W := 0.36   # m
const BOARD_H := BOARD_W * VIEW_H / VIEW_W

var viewport: SubViewport
var panel: VRPanel
var identity: IdentityCard
var area: Area3D

var _quad: MeshInstance3D
var _identity_label: Label
var _chips: Array[Button] = []
var _hint: Label
var _last_px: Vector2 = Vector2(-1, -1)
var _pointer_down: bool = false


func _init() -> void:
	# ---- 2D 쪽 ----
	viewport = SubViewport.new()
	viewport.size = Vector2i(VIEW_W, VIEW_H)
	viewport.transparent_bg = true
	viewport.gui_embed_subwindows = true       # OptionButton 팝업, 확인창이 보드 안에 뜨게
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.075, 0.09, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)

	# 머리줄
	var head := NoteUiKit.panel(NoteUiKit.BG_SOFT, 10)
	col.add_child(head)
	var hv := NoteUiKit.vbox(8)
	head.add_child(hv)
	_identity_label = NoteUiKit.label("", 20)
	hv.add_child(_identity_label)
	var chips := NoteUiKit.hbox(6)
	hv.add_child(chips)
	for i in NoteData.TYPE_NAMES.size():
		var b := NoteUiKit.color_button("%s 0" % NoteData.TYPE_INITIALS[i], NoteData.TYPE_COLORS[i], Callable(), true)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 18)
		b.set_pressed_no_signal(true)
		b.toggled.connect(func(on: bool) -> void: NoteManager.set_type_visible(i, on))
		chips.add_child(b)
		_chips.append(b)

	# 패널 자리
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(holder)
	panel = VRPanel.new()
	holder.add_child(panel)
	identity = IdentityCard.new()
	identity.compact = true
	holder.add_child(identity)

	# 안내줄
	var foot := NoteUiKit.panel(NoteUiKit.BG_SOFTER, 6)
	col.add_child(foot)
	_hint = NoteUiKit.label("", 15, NoteUiKit.MUTED, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(_hint)
	set_hint_default()

	# ---- 3D 쪽 ----
	_quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(BOARD_W, BOARD_H)
	_quad.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = viewport.get_texture()
	# 반투명 외피(inflatable shell) 메시보다 나중에 그린다. 깊이 테스트는 그대로라 벽 뒤에선 가려진다.
	mat.render_priority = 20
	_quad.material_override = mat
	add_child(_quad)

	area = Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BOARD_W, BOARD_H, 0.01)
	cs.shape = box
	area.add_child(cs)
	add_child(area)


func _ready() -> void:
	NoteManager.note_added.connect(func(_n: NoteData) -> void: _update_counts())
	NoteManager.note_updated.connect(func(_n: NoteData) -> void: _update_counts())
	NoteManager.note_removed.connect(func(_id: String) -> void: _update_counts())
	NoteManager.notes_reloaded.connect(_update_counts)
	NoteManager.identity_changed.connect(_update_identity)
	NoteManager.visibility_changed.connect(_sync_chips)
	_update_identity()
	_update_counts()


# ---------------- 표시 ----------------

func set_hint(text: String) -> void:
	_hint.text = text


func set_hint_default() -> void:
	_hint.text = "Trigger on a wall  place note      Trigger on a note  tap open / hold 3 s record      Right stick  scroll"


func _update_identity() -> void:
	_identity_label.text = "%s  ·  %s" % [NoteManager.author_name, NoteData.ROLE_NAMES[NoteManager.author_role]]


func _update_counts() -> void:
	var counts := NoteManager.counts_by_type()
	for i in _chips.size():
		_chips[i].text = "%s %d" % [NoteData.TYPE_INITIALS[i], counts[i]]


func _sync_chips() -> void:
	for i in _chips.size():
		_chips[i].set_pressed_no_signal(NoteManager.type_visible[i])


# ---------------- 포인터 ----------------

## 월드 좌표의 충돌 지점을 뷰포트 픽셀로 바꾼다.
func pixel_from_hit(world_pos: Vector3) -> Vector2:
	var local := _quad.to_local(world_pos)
	var u := local.x / BOARD_W + 0.5
	var v := 0.5 - local.y / BOARD_H
	return Vector2(clampf(u, 0.0, 1.0) * VIEW_W, clampf(v, 0.0, 1.0) * VIEW_H)


func pointer_move(px: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = px
	ev.global_position = px
	ev.relative = px - _last_px if _last_px.x >= 0.0 else Vector2.ZERO
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _pointer_down else 0
	_last_px = px
	viewport.push_input(ev)


func pointer_button(px: Vector2, pressed: bool) -> void:
	_pointer_down = pressed
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = px
	ev.global_position = px
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_last_px = px
	viewport.push_input(ev)


func pointer_leave() -> void:
	if _pointer_down:
		pointer_button(_last_px, false)
	_last_px = Vector2(-1, -1)
