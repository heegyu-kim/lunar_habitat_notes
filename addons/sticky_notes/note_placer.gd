class_name NotePlacer
extends Node
## 플레이어 카메라에 붙이는 상호작용 도구. Camera3D의 자식 노드로 넣으면 끝.
## HUD, 사이드 패널, 명함 카드를 여기서 만든다.
##
##   N (누르고 있기)  바라보는 표면에 반투명 핀이 따라다님. 떼면 그 자리에 노트 (스크린샷 자동)
##   E               바라보는 노트 열기
##   Tab             목록 열기 / 닫기
##   1 ~ 5           유형 표시 / 숨김
##   ] [             투어 다음 / 이전
##   Esc             투어 종료, 패널 닫기
##
## 데스크톱 입력만 들어 있다. XR로 갈 때는 _raycast()와 이 파일의 입력 부분만 바꾼다.

signal ui_opened
signal ui_closed

@export var camera: Camera3D
@export var max_distance: float = 20.0
## true면 창이 열릴 때 마우스를 풀고, 닫힐 때 다시 잡는다. 플레이어 스크립트가 직접 관리하면 false.
@export var manage_mouse: bool = true
## true면 처음 실행할 때 이름·역할을 묻는 명함 카드를 띄운다.
@export var ask_identity_on_start: bool = true

var ui_open: bool = false
var tour_ids: Array = []
var tour_index: int = -1

var _layer: CanvasLayer
var _hud: NoteHud
var _panel: NotePanel
var _identity: IdentityCard
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_hit: Dictionary = {}
var _holding: bool = false
var _aimed: StickyNote = null
var _busy: bool = false


func _ready() -> void:
	if camera == null and get_parent() is Camera3D:
		camera = get_parent()
	if camera == null:
		push_warning("NotePlacer: Camera3D를 찾지 못했습니다. camera 속성을 지정하거나 Camera3D의 자식으로 넣으세요.")

	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)

	_hud = NoteHud.new()
	_layer.add_child(_hud)

	_panel = NotePanel.new()
	_panel.closed.connect(_close_panel)
	_panel.goto_requested.connect(func(n: NoteData) -> void: NoteManager.request_teleport(n))
	_panel.tour_requested.connect(start_tour)
	_layer.add_child(_panel)

	_identity = IdentityCard.new()
	_identity.done.connect(_on_identity_done)
	_layer.add_child(_identity)

	_make_ghost()

	if ask_identity_on_start and not NoteManager.identity_set:
		call_deferred("_show_identity")


func _show_identity() -> void:
	_identity.open()
	_set_ui_open(true)


func _on_identity_done() -> void:
	_identity.close()
	_set_ui_open(false)


func _make_ghost() -> void:
	_ghost = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = StickyNote.PIN_RADIUS
	sm.height = StickyNote.PIN_RADIUS * 2.0
	_ghost.mesh = sm
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.45)
	# 반투명 외피(inflatable shell) 메시보다 나중에 그린다. 깊이 테스트는 그대로라 벽 뒤에선 가려진다.
	_ghost_mat.render_priority = 8
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	add_child(_ghost)


# ------------------------------------------------------------------
#  매 프레임: 조준, 홀드 배치
# ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if camera == null:
		return
	if ui_open or _busy:
		_set_aimed(null)
		_ghost.visible = false
		_holding = false
		return

	var hit := _raycast()
	var sn: StickyNote = null
	if not hit.is_empty():
		sn = _note_from_collider(hit.collider)
	_set_aimed(sn)

	if sn != null and sn.note != null:
		_hud.set_target("%s · %s   E to open" % [sn.note.type_name(), sn.note.author])
	elif not hit.is_empty():
		_hud.set_target(XRNotePlacer.anchor_name_of(hit.collider))
	else:
		_hud.set_target("")

	var ghost_color := NoteData.type_color(NoteData.default_type_for_role(NoteManager.author_role))
	if Input.is_action_pressed("note_place"):
		_holding = true
		if sn == null and not hit.is_empty():
			_ghost_hit = hit
			_ghost.global_position = hit.position + hit.normal * 0.01
			_ghost_mat.albedo_color = Color(ghost_color, 0.55)
			_ghost.visible = true
			_hud.set_target("release N to place on " + XRNotePlacer.anchor_name_of(hit.collider))
		else:
			_ghost_hit = {}
			_ghost.visible = false
	elif _holding:
		_holding = false
		_ghost.visible = false
		if not _ghost_hit.is_empty():
			_place(_ghost_hit)
			_ghost_hit = {}
		elif sn != null and sn.note != null:
			_open_note(sn.note)


func _set_aimed(sn: StickyNote) -> void:
	if _aimed == sn:
		return
	if is_instance_valid(_aimed):
		_aimed.aimed = false
	_aimed = sn
	if is_instance_valid(_aimed):
		_aimed.aimed = true


# ------------------------------------------------------------------
#  키 입력
# ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _busy or _identity.visible:
		return
	for i in 5:
		if event.is_action_pressed("note_type_%d" % (i + 1)):
			NoteManager.toggle_type_visible(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("note_list"):
		if _panel.is_on_tab(NotePanel.Tab.LIST):
			_close_panel()
		else:
			_panel.open_tab(NotePanel.Tab.LIST)
			_set_ui_open(true)
		get_viewport().set_input_as_handled()
		return
	if is_touring():
		if event.is_action_pressed("note_tour_next"):
			_tour_go(tour_index + 1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("note_tour_prev"):
			_tour_go(tour_index - 1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if is_touring():
			stop_tour()
			get_viewport().set_input_as_handled()
			return
		if ui_open:
			_close_panel()
			get_viewport().set_input_as_handled()
			return
	if ui_open:
		return
	if event.is_action_pressed("note_interact"):
		if is_instance_valid(_aimed) and _aimed.note != null:
			_open_note(_aimed.note)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------
#  배치 / 열기
# ------------------------------------------------------------------

func _raycast() -> Dictionary:
	if camera == null:
		return {}
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * max_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	# 안쪽에서 본 셸 메시(압력 용기 등)는 뒷면이 맞아 법선이 벽 속을 향한다. 노트가 항상 보는 쪽으로 서게 한다.
	if not hit.is_empty() and hit.normal.dot(to - from) > 0.0:
		hit.normal = -hit.normal
	return hit


func _note_from_collider(collider: Object) -> StickyNote:
	var n: Node = collider as Node
	while n != null:
		if n is StickyNote:
			return n
		n = n.get_parent()
	return null


func _place(hit: Dictionary) -> void:
	_busy = true
	var note := NoteData.make_new()
	note.position = hit.position
	note.normal = hit.normal
	note.anchor_name = XRNotePlacer.anchor_name_of(hit.collider)
	note.camera_position = camera.global_position
	note.camera_rotation = camera.global_rotation
	note.author = NoteManager.author_name
	note.role = NoteManager.author_role
	note.type = NoteData.default_type_for_role(NoteManager.author_role)

	_hud.visible = false
	note.screenshot_file = await NoteManager.capture_screenshot(note.id)
	_hud.visible = true
	_busy = false

	stop_tour()
	_panel.show_editor(note)
	_set_ui_open(true)


func _open_note(note: NoteData) -> void:
	_panel.show_note(note)
	_set_ui_open(true)


func _close_panel() -> void:
	stop_tour()
	_panel.close()
	_set_ui_open(false)


# ------------------------------------------------------------------
#  투어
# ------------------------------------------------------------------

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
	_hud.set_tour("")


func _tour_go(i: int) -> void:
	# 지워진 노트는 건너뛴다
	var guard := tour_ids.size()
	while guard > 0 and not tour_ids.is_empty():
		tour_index = posmod(i, tour_ids.size())
		var n := NoteManager.get_note(tour_ids[tour_index])
		if n != null:
			NoteManager.request_teleport(n)
			_panel.show_note(n)
			_set_ui_open(true)
			_hud.set_tour("Tour  %d / %d      [  previous      ]  next      Esc  end tour" % [tour_index + 1, tour_ids.size()])
			return
		tour_ids.remove_at(tour_index)
		guard -= 1
	stop_tour()


# ------------------------------------------------------------------

func _set_ui_open(open: bool) -> void:
	if ui_open == open:
		return
	ui_open = open
	if manage_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		ui_opened.emit()
	else:
		ui_closed.emit()
