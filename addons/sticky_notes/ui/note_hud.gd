class_name NoteHud
extends Control
## 항상 떠 있는 얇은 층.
##   왼쪽 위   나 (이름 · 역할)
##   오른쪽 위  유형별 개수 칩 다섯 개. 클릭(패널 열린 상태) 또는 1~5 키로 표시/숨김
##   가운데    조준점과 바라보는 대상 이름
##   아래      투어 상태, 키 안내

var _identity: Label
var _chips: Array[Button] = []
var _target: Label
var _tour: Label
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	# ---- 왼쪽 위: 나 ----
	var id_panel := NoteUiKit.panel(NoteUiKit.BG, 6)
	id_panel.set_anchors_and_offsets_preset(PRESET_TOP_LEFT, PRESET_MODE_MINSIZE, 12)
	id_panel.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(id_panel)
	var id_row := NoteUiKit.hbox(8)
	id_panel.add_child(id_row)
	var dot := ColorRect.new()
	dot.color = NoteUiKit.FG
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = SIZE_SHRINK_CENTER
	id_row.add_child(dot)
	_identity = NoteUiKit.label("", 13)
	id_row.add_child(_identity)

	# ---- 오른쪽 위: 유형 칩 ----
	var chip_row := NoteUiKit.hbox(4)
	chip_row.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_MINSIZE, 12)
	chip_row.grow_horizontal = GROW_DIRECTION_BEGIN
	add_child(chip_row)
	for i in NoteData.TYPE_NAMES.size():
		var c := NoteData.TYPE_COLORS[i]
		var b := NoteUiKit.color_button("%s 0" % NoteData.TYPE_INITIALS[i], c, Callable(), true)
		b.tooltip_text = "%s   (key %d)" % [NoteData.TYPE_NAMES[i], i + 1]
		b.set_pressed_no_signal(true)
		b.toggled.connect(func(on: bool) -> void: NoteManager.set_type_visible(i, on))
		chip_row.add_child(b)
		_chips.append(b)

	# ---- 가운데 ----
	var center_dot := ColorRect.new()
	center_dot.color = Color(1, 1, 1, 0.85)
	center_dot.custom_minimum_size = Vector2(4, 4)
	center_dot.set_anchors_and_offsets_preset(PRESET_CENTER, PRESET_MODE_MINSIZE)
	center_dot.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center_dot)

	_target = NoteUiKit.label("", 13, Color(1, 1, 1, 0.8))
	_target.set_anchors_and_offsets_preset(PRESET_CENTER, PRESET_MODE_KEEP_SIZE)
	_target.grow_horizontal = GROW_DIRECTION_BOTH
	_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target.position.y += 22
	add_child(_target)

	# ---- 아래 ----
	_tour = NoteUiKit.label("", 13, Color(1, 1, 1, 0.9))
	_tour.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, PRESET_MODE_KEEP_SIZE, 46)
	_tour.grow_horizontal = GROW_DIRECTION_BOTH
	_tour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_tour)

	_hint = NoteUiKit.label("", 12, Color(1, 1, 1, 0.5))
	_hint.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, PRESET_MODE_KEEP_SIZE, 20)
	_hint.grow_horizontal = GROW_DIRECTION_BOTH
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	set_hint_default()

	NoteManager.note_added.connect(func(_n: NoteData) -> void: _update_counts())
	NoteManager.note_updated.connect(func(_n: NoteData) -> void: _update_counts())
	NoteManager.note_removed.connect(func(_id: String) -> void: _update_counts())
	NoteManager.notes_reloaded.connect(_update_counts)
	NoteManager.identity_changed.connect(_update_identity)
	NoteManager.visibility_changed.connect(_sync_chips)
	_update_identity()
	_update_counts()


func set_target(text: String) -> void:
	_target.text = text


func set_tour(text: String) -> void:
	_tour.text = text


func set_hint(text: String) -> void:
	_hint.text = text


func set_hint_default() -> void:
	_hint.text = "Hold N  place note      E  open      Tab  list      1 to 5  show / hide types      Right drag  look around while panel is open"


func _update_identity() -> void:
	_identity.text = "%s  ·  %s" % [NoteManager.author_name, NoteData.ROLE_NAMES[NoteManager.author_role]]


func _update_counts() -> void:
	var counts := NoteManager.counts_by_type()
	for i in _chips.size():
		_chips[i].text = "%s %d" % [NoteData.TYPE_INITIALS[i], counts[i]]


func _sync_chips() -> void:
	for i in _chips.size():
		_chips[i].set_pressed_no_signal(NoteManager.type_visible[i])
