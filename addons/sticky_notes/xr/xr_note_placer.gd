class_name XRNotePlacer
extends Node
## VR 상호작용. 오른손 트리거 하나로 다 한다.
##
##   벽을 겨누고 트리거      파란 반투명 노트가 그 자리에 보인다
##     → 놓으면            진짜 노트가 바로 붙는다 (유형은 내 역할 기본값, 보드에서 바꿀 수 있음)
##   노트를 겨누고 트리거 탭  보드에 그 노트가 열린다
##   노트를 겨누고 3초 홀드   "Hold 3 s to record"  → 3초가 차면 화면+음성 녹화 시작
##   녹화 중 트리거 탭        녹화 정지
##   보드를 겨누고 트리거     버튼 클릭
##   오른쪽 스틱 위아래       보드 스크롤
##
## A / B / X / Y / 그립은 쓰지 않는다. 보드는 왼손에 항상 떠 있다.

const RAY_LENGTH := 6.0
const HOLD_TO_RECORD := 3.0

var camera: XRCamera3D
var left: XRController3D
var right: XRController3D
var board: WristBoard
var theater: ClipTheater

var tour_ids: Array = []
var tour_index: int = -1

var _ray: MeshInstance3D
var _ray_mat: StandardMaterial3D
var _tip: MeshInstance3D
var _tip_label: Label3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_hit: Dictionary = {}
var _aimed: StickyNote = null
var _busy: bool = false

var _trigger_prev: bool = false
var _hold_note: StickyNote = null      # 트리거를 누르기 시작했을 때 겨누던 노트
var _hold_t: float = 0.0
var _hold_fired: bool = false          # 이번 홀드로 녹화를 시작했는가
var _scroll_accum: float = 0.0


func _ready() -> void:
	_make_visuals()
	board.panel.goto_requested.connect(func(n: NoteData) -> void: NoteManager.request_teleport(n))
	board.panel.tour_requested.connect(start_tour)
	board.panel.tour_step.connect(_on_tour_step)
	board.panel.play_requested.connect(_on_play_requested)
	board.panel.closed.connect(_on_panel_closed)
	board.identity.done.connect(_on_identity_done)
	board.visible = true
	if NoteManager.identity_set:
		board.panel.open_tab(VRPanel.Tab.NOTE)
	else:
		call_deferred("_show_identity")


func _show_identity() -> void:
	board.panel.visible = false
	board.identity.open()


func _on_identity_done() -> void:
	board.identity.close()
	board.panel.open_tab(VRPanel.Tab.NOTE)


func _on_panel_closed() -> void:
	stop_tour()
	board.panel.open_tab(VRPanel.Tab.NOTE)


func _make_visuals() -> void:
	_ray = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.004, 0.004, 1.0)
	_ray.mesh = bm
	_ray_mat = StandardMaterial3D.new()
	_ray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ray_mat.albedo_color = Color(1, 1, 1, 0.35)
	# 반투명 외피(inflatable shell) 메시보다 나중에 그린다. 깊이 테스트는 그대로라 벽 뒤에선 가려진다.
	_ray_mat.render_priority = 8
	_ray.material_override = _ray_mat
	right.add_child(_ray)

	_tip = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.008
	sm.height = 0.016
	_tip.mesh = sm
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1, 1, 1, 0.9)
	tm.render_priority = 8
	_tip.material_override = tm
	_tip.top_level = true
	add_child(_tip)

	_tip_label = Label3D.new()
	_tip_label.pixel_size = 0.001
	_tip_label.font_size = 34
	_tip_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tip_label.no_depth_test = true
	_tip_label.modulate = Color(1, 1, 1, 0.95)
	_tip_label.outline_size = 8
	_tip_label.top_level = true
	add_child(_tip_label)

	_ghost = MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = StickyNote.PIN_RADIUS * 1.2
	gm.height = StickyNote.PIN_RADIUS * 2.4
	_ghost.mesh = gm
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.3, 0.65, 1.0, 0.5)
	_ghost_mat.render_priority = 8
	_ghost.material_override = _ghost_mat
	_ghost.top_level = true
	_ghost.visible = false
	add_child(_ghost)


# =====================================================================
#  매 프레임
# =====================================================================

func _process(delta: float) -> void:
	if camera == null or right == null or left == null:
		return
	var hit := _raycast()
	var kind := _classify(hit)      # "board" / "note" / "surface" / ""
	var sn: StickyNote = _note_from_collider(hit.collider) if kind == "note" else null
	_set_aimed(sn)
	_update_ray(hit, kind)

	var trigger := right.is_button_pressed("trigger_click")
	var pressed_now := trigger and not _trigger_prev
	var released_now := (not trigger) and _trigger_prev
	_trigger_prev = trigger
	var identity_open := board.identity.visible

	# ---- 몰입 재생 중: 트리거 탭이면 나온다 ----
	if theater != null and theater.active:
		_ghost.visible = false
		_tip_label.visible = false
		_ray.visible = false
		_tip.visible = false
		board.visible = false
		if pressed_now:
			theater.exit()
		return
	_ray.visible = true
	board.visible = true

	# ---- 보드: 포인터 → 마우스 ----
	if kind == "board":
		var px := board.pixel_from_hit(hit.position)
		board.pointer_move(px)
		if pressed_now:
			board.pointer_button(px, true)
		elif released_now:
			board.pointer_button(px, false)
	else:
		board.pointer_leave()

	# ---- 오른쪽 스틱 위아래 = 스크롤 ----
	var sy := right.get_vector2("primary").y
	if absf(sy) > 0.25:
		board.panel.scroll_by(-sy * 900.0 * delta)

	if identity_open or _busy:
		_ghost.visible = false
		return

	# ---- 녹화 중: 트리거 탭이면 정지 ----
	if NoteManager.is_clip_recording:
		_ghost.visible = false
		if pressed_now and kind != "board":
			board.panel.stop_record_from_trigger()
			_haptic(right, 0.5)
			_hold_note = null
			_hold_fired = true     # 이 홀드가 끝날 때 아무것도 하지 않게
		return

	# ---- 트리거 누르기 시작 ----
	if pressed_now and kind != "board":
		_hold_t = 0.0
		_hold_fired = false
		_hold_note = sn
		if kind != "note":
			_hold_note = null

	# ---- 누르고 있는 동안 ----
	if trigger and kind != "board":
		if _hold_note != null and is_instance_valid(_hold_note):
			# 노트 위에서 홀드: 3초 게이지
			_ghost.visible = false
			_hold_t += delta
			if not _hold_fired:
				if _hold_t >= HOLD_TO_RECORD:
					_hold_fired = true
					board.panel.record_for_note(_hold_note.note)
					_haptic(right, 0.6)
				else:
					var left_s := ceili(HOLD_TO_RECORD - _hold_t)
					_tip_label.text = "Hold %d s to record screen and voice" % left_s
					if int(_hold_t * 4.0) != int((_hold_t - delta) * 4.0):
						_haptic(right, 0.08)
		elif kind == "surface":
			# 벽 위에서 홀드: 파란 반투명 미리보기
			_ghost_hit = hit
			_ghost.global_position = hit.position + hit.normal * 0.012
			_ghost.visible = true
			_tip_label.text = "Release to place a note on " + anchor_name_of(hit.collider)
		else:
			_ghost_hit = {}
			_ghost.visible = false

	# ---- 놓았을 때 ----
	if released_now:
		_ghost.visible = false
		if _hold_note != null and is_instance_valid(_hold_note) and not _hold_fired:
			_open_note(_hold_note.note)            # 짧게 탭 → 열기
		elif _hold_note == null and not _hold_fired and not _ghost_hit.is_empty():
			_place(_ghost_hit)                      # 벽 → 바로 노트
		_hold_note = null
		_hold_fired = false
		_ghost_hit = {}


## 투어 중에는 이동을 막지 않는다. (스틱은 그대로 이동)
func blocks_locomotion() -> bool:
	return false


# =====================================================================
#  레이
# =====================================================================

func _raycast() -> Dictionary:
	var from := right.global_position
	var to := from - right.global_transform.basis.z * RAY_LENGTH
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := right.get_world_3d().direct_space_state.intersect_ray(q)
	# 안쪽에서 본 셸 메시(압력 용기 등)는 뒷면이 맞아 법선이 벽 속을 향한다. 노트가 항상 보는 쪽으로 서게 한다.
	if not hit.is_empty() and hit.normal.dot(to - from) > 0.0:
		hit.normal = -hit.normal
	return hit


func _classify(hit: Dictionary) -> String:
	if hit.is_empty():
		return ""
	if board.visible and hit.collider == board.area:
		return "board"
	if _note_from_collider(hit.collider) != null:
		return "note"
	return "surface"


func _note_from_collider(collider: Object) -> StickyNote:
	var n: Node = collider as Node
	while n != null:
		if n is StickyNote:
			return n
		n = n.get_parent()
	return null


func _update_ray(hit: Dictionary, kind: String) -> void:
	var dist := RAY_LENGTH
	if not hit.is_empty():
		dist = right.global_position.distance_to(hit.position)
	_ray.position = Vector3(0, 0, -dist * 0.5)
	_ray.scale = Vector3(1, 1, dist)
	_tip.visible = not hit.is_empty()
	_tip_label.visible = not hit.is_empty() and kind != "board"
	if hit.is_empty():
		return
	_tip.global_position = hit.position
	_tip_label.global_position = hit.position + Vector3(0, 0.07, 0)
	if NoteManager.is_clip_recording:
		_tip_label.text = "●  REC  %.0fs    pull trigger to stop" % NoteManager.clip_elapsed
		_tip_label.modulate = NoteData.TYPE_COLORS[0]
		return
	_tip_label.modulate = Color(1, 1, 1, 0.95)
	var sn := _note_from_collider(hit.collider)
	if sn != null and sn.note != null:
		_tip_label.text = "%s · %s      tap: open   hold 3 s: record" % [sn.note.type_name(), sn.note.author]
	elif kind == "surface":
		_tip_label.text = anchor_name_of(hit.collider)
	else:
		_tip_label.text = ""


## 가져온 모델(FBX/glb)은 콜리전 노드 이름이 "Hatch_col" 또는 "StaticBody3D" 처럼 된다.
## 사람이 읽을 이름(메시 이름)을 찾아서 돌려준다.
static func anchor_name_of(collider: Object) -> String:
	var n: Node = collider as Node
	if n == null:
		return ""
	var name_ := str(n.name)
	for suffix in ["_col", "-col", "_colonly", "-colonly", "_convcol", "-convcol"]:
		if name_.ends_with(suffix):
			name_ = name_.substr(0, name_.length() - suffix.length())
	if name_.begins_with("StaticBody3D") or name_.begins_with("CollisionShape") or name_ == "":
		var p := n.get_parent()
		if p != null:
			return str(p.name)
	return name_


func _set_aimed(sn: StickyNote) -> void:
	if _aimed == sn:
		return
	if is_instance_valid(_aimed):
		_aimed.aimed = false
	_aimed = sn
	if is_instance_valid(_aimed):
		_aimed.aimed = true


# =====================================================================
#  배치 / 열기
# =====================================================================

func _place(hit: Dictionary) -> void:
	_busy = true
	var note := NoteData.make_new()
	note.position = hit.position
	note.normal = hit.normal
	note.anchor_name = anchor_name_of(hit.collider)
	note.camera_position = camera.global_position
	note.camera_rotation = camera.global_rotation
	note.author = NoteManager.author_name
	note.role = NoteManager.author_role
	note.type = NoteData.default_type_for_role(NoteManager.author_role)
	note.screenshot_file = await NoteManager.capture_screenshot(note.id)
	_busy = false
	stop_tour()
	NoteManager.add_note(note)
	board.panel.show_note(note)
	_haptic(right, 0.4)


func _on_play_requested(note: NoteData) -> void:
	if theater == null or NoteManager.is_clip_recording:
		return
	stop_tour()
	theater.enter(note)


func _open_note(note: NoteData) -> void:
	board.panel.show_note(note)
	_haptic(right, 0.2)


# =====================================================================
#  투어
# =====================================================================

func is_touring() -> bool:
	return not tour_ids.is_empty()


func start_tour(ids: Array) -> void:
	if ids.is_empty():
		return
	tour_ids = ids.duplicate()
	_tour_go(0)


func stop_tour() -> void:
	if tour_ids.is_empty():
		return
	tour_ids.clear()
	tour_index = -1
	board.panel.tour_label = ""
	board.set_hint_default()


func _on_tour_step(direction: int) -> void:
	if direction == 0:
		stop_tour()
		if board.panel.note != null:
			board.panel.show_note(board.panel.note)
	elif direction > 0:
		tour_next()
	else:
		tour_prev()


func tour_next() -> void:
	if is_touring():
		_tour_go(tour_index + 1)


func tour_prev() -> void:
	if is_touring():
		_tour_go(tour_index - 1)


func _tour_go(i: int) -> void:
	var guard := tour_ids.size()
	while guard > 0 and not tour_ids.is_empty():
		tour_index = posmod(i, tour_ids.size())
		var n := NoteManager.get_note(tour_ids[tour_index])
		if n != null:
			NoteManager.request_teleport(n)
			board.panel.tour_label = "Tour  %d / %d" % [tour_index + 1, tour_ids.size()]
			board.panel.show_note(n)
			return
		tour_ids.remove_at(tour_index)
		guard -= 1
	stop_tour()


func _haptic(c: XRController3D, strength: float) -> void:
	c.trigger_haptic_pulse("haptic", 0.0, strength, 0.08, 0.0)
