class_name NotePanel
extends Control
## 오른쪽 사이드 패널 하나가 모든 UI를 담당한다. 3D 뷰는 가리지 않는다.
##   Note     지금 쓰는 노트 / 보고 있는 노트 (답글은 대화처럼 아래로 쌓인다)
##   List     목록, 필터, 투어 시작
##   Session  나, 저장 / 불러오기, 리포트 내보내기

signal closed
signal goto_requested(note: NoteData)
signal tour_requested(ids: Array)

enum Tab { NOTE, LIST, SESSION }
enum Mode { EMPTY, EDIT, VIEW }

const WIDTH := 380.0

var mode: int = Mode.EMPTY
var note: NoteData = null

var _tabs: TabContainer
var _note_box: VBoxContainer
var _player: AudioStreamPlayer

# 작성
var _type_row: NoteUiKit.ChoiceRow
var _text: TextEdit
var _rec_btn: Button
var _rec_time: Label
var _rec_started: int = 0

# 답글 작성
var _reply_type: OptionButton
var _reply_edit: LineEdit
var _reply_rec: Button
var _pending_reply: NoteData = null

# 목록
var _count: Label
var _type_filter: OptionButton
var _role_filter: OptionButton
var _show_resolved: CheckButton
var _items: ItemList
var _shown_ids: Array = []

# 세션
var _name_edit: LineEdit
var _role_row: NoteUiKit.ChoiceRow
var _session_name: LineEdit
var _session_opt: OptionButton
var _status: Label
var _mic_opt: OptionButton
var _mic_level: ProgressBar
var _mic_text: Label
var _pending_load: String = ""

var _confirm_delete: ConfirmationDialog
var _confirm_clear: ConfirmationDialog
var _confirm_load: ConfirmationDialog


# =====================================================================
#  구성
# =====================================================================

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	var panel := NoteUiKit.panel(NoteUiKit.BG, 12)
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.set_anchors_and_offsets_preset(PRESET_RIGHT_WIDE, PRESET_MODE_MINSIZE, 12)
	panel.grow_horizontal = GROW_DIRECTION_BEGIN
	add_child(panel)

	var v := NoteUiKit.vbox(8)
	panel.add_child(v)

	var head := NoteUiKit.hbox()
	head.add_child(NoteUiKit.label("Sticky Notes", 15))
	head.add_child(NoteUiKit.spacer())
	head.add_child(NoteUiKit.button("Close  Esc", _on_close_pressed, true))
	v.add_child(head)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 13)
	v.add_child(_tabs)

	_build_note_tab()
	_build_list_tab()
	_build_session_tab()

	_player = AudioStreamPlayer.new()
	add_child(_player)

	_confirm_delete = ConfirmationDialog.new()
	_confirm_delete.dialog_text = "Delete this note and all its replies?"
	_confirm_delete.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm_delete)

	_confirm_clear = ConfirmationDialog.new()
	_confirm_clear.dialog_text = "Remove all notes from the scene? Saved sessions are kept."
	_confirm_clear.confirmed.connect(NoteManager.clear_all)
	add_child(_confirm_clear)

	_confirm_load = ConfirmationDialog.new()
	_confirm_load.dialog_text = "Replace the current notes with this session?"
	_confirm_load.confirmed.connect(_on_load_confirmed)
	add_child(_confirm_load)

	NoteManager.note_added.connect(_on_note_changed)
	NoteManager.note_updated.connect(_on_note_changed)
	NoteManager.note_removed.connect(_on_note_removed)
	NoteManager.notes_reloaded.connect(_on_reloaded)
	NoteManager.identity_changed.connect(_sync_identity)
	hide()


func _build_note_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Note"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_note_box = NoteUiKit.vbox(10)
	_note_box.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_note_box)
	_rebuild_note()


func _build_list_tab() -> void:
	var v := NoteUiKit.vbox(8)
	v.name = "List"
	_tabs.add_child(v)

	_count = NoteUiKit.label("Notes", 14)
	v.add_child(_count)

	var frow := NoteUiKit.hbox(6)
	_type_filter = NoteUiKit.type_option(true)
	_type_filter.size_flags_horizontal = SIZE_EXPAND_FILL
	_type_filter.item_selected.connect(func(_i: int) -> void: refresh_list())
	frow.add_child(_type_filter)
	_role_filter = NoteUiKit.role_option(true)
	_role_filter.size_flags_horizontal = SIZE_EXPAND_FILL
	_role_filter.item_selected.connect(func(_i: int) -> void: refresh_list())
	frow.add_child(_role_filter)
	v.add_child(frow)

	_show_resolved = CheckButton.new()
	_show_resolved.text = "Show resolved"
	_show_resolved.button_pressed = true
	_show_resolved.add_theme_font_size_override("font_size", 12)
	_show_resolved.toggled.connect(func(_on: bool) -> void: refresh_list())
	v.add_child(_show_resolved)

	_items = ItemList.new()
	_items.size_flags_vertical = SIZE_EXPAND_FILL
	_items.add_theme_font_size_override("font_size", 12)
	_items.item_activated.connect(func(_i: int) -> void: _on_list_open())
	v.add_child(_items)

	var brow := NoteUiKit.hbox(6)
	brow.add_child(NoteUiKit.button("Open", _on_list_open))
	brow.add_child(NoteUiKit.button("Go there", _on_list_goto))
	brow.add_child(NoteUiKit.spacer())
	var tour := NoteUiKit.button("Tour  ▶", _on_tour_pressed)
	tour.tooltip_text = "Visit the listed notes one by one.  ] next   [ previous"
	brow.add_child(tour)
	v.add_child(brow)


func _build_session_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Session"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var v := NoteUiKit.vbox(8)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(v)

	v.add_child(NoteUiKit.label("You", 14))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	v.add_child(_name_edit)
	_role_row = NoteUiKit.ChoiceRow.new(NoteData.ROLE_NAMES)
	v.add_child(_role_row)
	var arow := NoteUiKit.hbox()
	arow.alignment = BoxContainer.ALIGNMENT_END
	arow.add_child(NoteUiKit.button("Apply", _on_apply_identity))
	v.add_child(arow)
	_sync_identity()

	v.add_child(NoteUiKit.separator())
	v.add_child(NoteUiKit.label("Session", 14))
	v.add_child(NoteUiKit.small("Save writes a JSON file. Send it together with the media folder and the other person loads it in the same place."))

	var srow := NoteUiKit.hbox(6)
	_session_name = LineEdit.new()
	_session_name.placeholder_text = "session name"
	_session_name.size_flags_horizontal = SIZE_EXPAND_FILL
	srow.add_child(_session_name)
	srow.add_child(NoteUiKit.button("Save", _on_save_pressed))
	v.add_child(srow)

	var lrow := NoteUiKit.hbox(6)
	_session_opt = OptionButton.new()
	_session_opt.add_theme_font_size_override("font_size", 12)
	_session_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	lrow.add_child(_session_opt)
	lrow.add_child(NoteUiKit.button("Load", _on_load_pressed))
	v.add_child(lrow)

	v.add_child(NoteUiKit.separator())
	v.add_child(NoteUiKit.label("Report", 14))
	v.add_child(NoteUiKit.small("One HTML file with every note, screenshot, voice clip and reply, grouped by the part it is attached to. Opens in any browser, no Godot needed."))
	var rrow := NoteUiKit.hbox(6)
	rrow.add_child(NoteUiKit.button("Export report", _on_export_pressed))
	rrow.add_child(NoteUiKit.button("Open data folder", NoteManager.open_data_folder))
	v.add_child(rrow)

	v.add_child(NoteUiKit.separator())
	v.add_child(NoteUiKit.label("Microphone", 14))
	v.add_child(NoteUiKit.small("Used for clips and voice notes. Pick the headset mic and speak: the bar must move. If it never moves, the device is not delivering sound (Quest Link mic, Windows privacy, sound settings)."))
	_mic_opt = OptionButton.new()
	_mic_opt.add_theme_font_size_override("font_size", 12)
	_mic_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	var devs := NoteManager.mic_devices()
	for i in devs.size():
		_mic_opt.add_item(devs[i])
		if devs[i] == NoteManager.mic_device:
			_mic_opt.selected = i
	_mic_opt.item_selected.connect(func(i: int) -> void: NoteManager.set_mic_device(_mic_opt.get_item_text(i)))
	var mrow := NoteUiKit.hbox(6)
	_mic_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	mrow.add_child(_mic_opt)
	mrow.add_child(NoteUiKit.button("Reconnect mic", func() -> void: NoteManager.reconnect_mic()))
	v.add_child(mrow)
	_mic_level = ProgressBar.new()
	_mic_level.min_value = 0.0
	_mic_level.max_value = 1.0
	_mic_level.show_percentage = false
	_mic_level.custom_minimum_size = Vector2(0, 8)
	_mic_level.add_theme_stylebox_override("fill", NoteUiKit.flat_style(NoteData.TYPE_COLORS[4], 3))
	_mic_level.add_theme_stylebox_override("background", NoteUiKit.flat_style(NoteUiKit.BG_SOFTER, 3))
	v.add_child(_mic_level)
	_mic_text = NoteUiKit.small("")
	v.add_child(_mic_text)
	if NoteManager.clip_mode == "ffmpeg":
		v.add_child(NoteUiKit.small("Clips: 1280×720 24 fps via ffmpeg, voice from this microphone."))
	else:
		v.add_child(NoteUiKit.small("Clips: frame method (no ffmpeg). Put ffmpeg.exe in tools/ for real video."))

	v.add_child(NoteUiKit.separator())
	var crow := NoteUiKit.hbox()
	crow.add_child(NoteUiKit.spacer())
	crow.add_child(NoteUiKit.button("Clear all notes", _on_clear_pressed))
	v.add_child(crow)

	_status = NoteUiKit.small("")
	v.add_child(_status)


# =====================================================================
#  열기 / 닫기
# =====================================================================

func open_tab(tab: int) -> void:
	_tabs.current_tab = tab
	if tab == Tab.LIST:
		refresh_list()
	elif tab == Tab.SESSION:
		_refresh_sessions()
	show()


func is_on_tab(tab: int) -> bool:
	return visible and _tabs.current_tab == tab


## 새 노트 작성 모드로 연다. (NoteManager에는 아직 없는 노트)
func show_editor(n: NoteData) -> void:
	_stop_recording_if_any()
	note = n
	mode = Mode.EDIT
	_rebuild_note()
	open_tab(Tab.NOTE)
	if _text != null:
		_text.grab_focus()


## 기존 노트를 보기 모드로 연다.
func show_note(n: NoteData) -> void:
	_stop_recording_if_any()
	_pending_reply = null
	note = n
	mode = Mode.VIEW
	NoteManager.set_focused(n.id)
	_rebuild_note()
	open_tab(Tab.NOTE)


func close() -> void:
	_stop_recording_if_any()
	_player.stop()
	if mode == Mode.EDIT and note != null and not NoteManager.notes.has(note.id):
		NoteManager.discard_media(note)
		note = null
		mode = Mode.EMPTY
		_rebuild_note()
	NoteManager.set_focused("")
	hide()


func _on_close_pressed() -> void:
	close()
	closed.emit()


func _stop_recording_if_any() -> void:
	if NoteManager.is_clip_recording:
		NoteManager.cancel_clip()


# =====================================================================
#  Note 탭
# =====================================================================

func _clear_note_box() -> void:
	for c in _note_box.get_children():
		_note_box.remove_child(c)
		c.queue_free()
	_type_row = null
	_text = null
	_rec_btn = null
	_rec_time = null
	_reply_type = null
	_reply_edit = null
	_reply_rec = null


func _rebuild_note() -> void:
	_clear_note_box()
	match mode:
		Mode.EDIT:
			_build_editor()
		Mode.VIEW:
			_build_viewer()
		_:
			_build_empty()


func _build_empty() -> void:
	_note_box.add_child(NoteUiKit.label("No note selected", 14, NoteUiKit.MUTED))
	_note_box.add_child(NoteUiKit.small("Aim at a surface and hold N to place a note where you are looking. Aim at a pin and press E to read it."))
	var tips := NoteUiKit.vbox(4)
	for i in NoteData.TYPE_NAMES.size():
		var row := NoteUiKit.hbox(8)
		var sw := ColorRect.new()
		sw.color = NoteData.TYPE_COLORS[i]
		sw.custom_minimum_size = Vector2(10, 10)
		sw.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(sw)
		row.add_child(NoteUiKit.label(NoteData.TYPE_NAMES[i], 12))
		tips.add_child(row)
	_note_box.add_child(tips)


func _thumb(file: String, height: float) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(0, height)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture = NoteManager.load_screenshot(file)
	t.visible = t.texture != null
	return t


func _build_editor() -> void:
	var head := NoteUiKit.hbox()
	head.add_child(NoteUiKit.label("New note", 15))
	head.add_child(NoteUiKit.spacer())
	if note.anchor_name != "":
		head.add_child(NoteUiKit.label("on " + note.anchor_name, 12, NoteUiKit.MUTED))
	_note_box.add_child(head)

	_type_row = NoteUiKit.ChoiceRow.new(NoteData.TYPE_NAMES, NoteData.TYPE_COLORS)
	_type_row.set_selected(note.type)
	_note_box.add_child(_type_row)

	var cp := ClipPlayer.new(170.0)
	if cp.load_note(note):
		_note_box.add_child(cp)
	else:
		cp.queue_free()

	_text = TextEdit.new()
	_text.custom_minimum_size = Vector2(0, 96)
	_text.placeholder_text = "What do you want to say about this spot?"
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.text = note.text
	_note_box.add_child(_text)

	var arow := NoteUiKit.hbox(6)
	_rec_btn = NoteUiKit.button("●  Record clip", _on_record_pressed)
	arow.add_child(_rec_btn)
	_rec_time = NoteUiKit.label("", 12, NoteUiKit.MUTED)
	_rec_time.size_flags_vertical = SIZE_SHRINK_CENTER
	arow.add_child(_rec_time)
	_note_box.add_child(arow)
	_update_rec_button()

	_note_box.add_child(NoteUiKit.small("Signed as %s · %s" % [NoteManager.author_name, NoteData.ROLE_NAMES[NoteManager.author_role]]))

	var brow := NoteUiKit.hbox(6)
	brow.alignment = BoxContainer.ALIGNMENT_END
	brow.add_child(NoteUiKit.button("Cancel", _on_cancel_pressed, true))
	brow.add_child(NoteUiKit.button("Save note", _on_save_note_pressed))
	_note_box.add_child(brow)


func _build_viewer() -> void:
	if note == null or not NoteManager.notes.has(note.id):
		mode = Mode.EMPTY
		_build_empty()
		return
	note = NoteManager.notes[note.id]
	var c := note.color()

	var band := NoteUiKit.panel(c if not note.resolved else Color(0.6, 0.6, 0.6), 8)
	var brow := NoteUiKit.hbox()
	brow.add_child(NoteUiKit.label(note.type_name(), 14, NoteUiKit.DARK))
	brow.add_child(NoteUiKit.spacer())
	if note.resolved:
		brow.add_child(NoteUiKit.label("RESOLVED", 12, NoteUiKit.DARK))
	band.add_child(brow)
	_note_box.add_child(band)

	var meta := "%s · %s · %s" % [note.role_name(), note.author, note.short_time()]
	if note.anchor_name != "":
		meta += "   on " + note.anchor_name
	if NoteManager.is_conflict(note.anchor_name) and not note.resolved:
		meta += "   ·  conflict here"
	_note_box.add_child(NoteUiKit.small(meta))

	var cp := ClipPlayer.new(170.0)
	if cp.load_note(note):
		_note_box.add_child(cp)
	else:
		cp.queue_free()

	_note_box.add_child(NoteUiKit.label(note.text if note.text != "" else "(clip only)", 14, NoteUiKit.FG, true))

	var arow := NoteUiKit.hbox(6)
	arow.add_child(NoteUiKit.button("Go there", func() -> void: goto_requested.emit(note)))
	arow.add_child(NoteUiKit.button("Reopen" if note.resolved else "Resolve", _on_toggle_resolved))
	arow.add_child(NoteUiKit.spacer())
	arow.add_child(NoteUiKit.button("Delete", _on_delete_pressed, true))
	_note_box.add_child(arow)

	_note_box.add_child(NoteUiKit.separator())
	var replies := NoteManager.replies_of(note.id)
	_note_box.add_child(NoteUiKit.label("Replies  %d" % replies.size(), 12, NoteUiKit.MUTED))
	for r in replies:
		_note_box.add_child(_bubble(r))

	# ---- 답글 작성 ----
	var crow := NoteUiKit.hbox(4)
	_reply_type = NoteUiKit.type_option()
	_reply_type.selected = NoteData.default_type_for_role(NoteManager.author_role)
	_reply_type.custom_minimum_size = Vector2(112, 0)
	crow.add_child(_reply_type)
	_reply_edit = LineEdit.new()
	_reply_edit.placeholder_text = "Reply…"
	_reply_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_reply_edit.text_submitted.connect(func(_t: String) -> void: _send_reply())
	crow.add_child(_reply_edit)
	_reply_rec = NoteUiKit.button("●", _on_reply_record_pressed)
	_reply_rec.tooltip_text = "Record a clip reply"
	crow.add_child(_reply_rec)
	crow.add_child(NoteUiKit.button("Send", _send_reply))
	_note_box.add_child(crow)
	_rec_time = NoteUiKit.label("", 12, NoteUiKit.MUTED)
	_note_box.add_child(_rec_time)


func _bubble(r: NoteData) -> Control:
	var p := NoteUiKit.panel(NoteUiKit.BG_SOFT, 8)
	var h := NoteUiKit.hbox(8)
	p.add_child(h)
	var band := ColorRect.new()
	band.color = r.color()
	band.custom_minimum_size = Vector2(3, 0)
	band.size_flags_vertical = SIZE_FILL
	h.add_child(band)
	var v := NoteUiKit.vbox(3)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(NoteUiKit.small("%s · %s · %s · %s" % [r.type_name(), r.role_name(), r.author, r.short_time()]))
	if r.has_media():
		var cp := ClipPlayer.new(110.0)
		if cp.load_note(r):
			v.add_child(cp)
		else:
			cp.queue_free()
	if r.text != "":
		v.add_child(NoteUiKit.label(r.text, 13, NoteUiKit.FG, true))
	return p


func _process(_delta: float) -> void:
	if visible and NoteManager.is_clip_recording and _rec_time != null:
		_rec_time.text = "recording  %.1fs" % NoteManager.clip_elapsed
	if visible and _mic_level != null and _mic_level.is_visible_in_tree():
		_mic_level.value = NoteManager.mic_level()
		_mic_text.text = NoteManager.mic_check_text()


func _play(file: String) -> void:
	var s := NoteManager.load_audio(file)
	if s == null:
		return
	_player.stream = s
	_player.play()


# ---- 작성 ----

func _update_rec_button() -> void:
	if _rec_btn == null:
		return
	if NoteManager.is_clip_recording:
		_rec_btn.text = "■  Stop"
	elif note != null and note.has_media():
		_rec_btn.text = "●  Record again"
	else:
		_rec_btn.text = "●  Record clip"


func _apply_clip(target: NoteData, result: Dictionary) -> void:
	if result.is_empty():
		return
	target.clip_file = result["clip_file"]
	target.audio_file = result["audio_file"]
	target.screenshot_file = result["screenshot_file"]


func _on_record_pressed() -> void:
	if NoteManager.is_clip_recording:
		var result := NoteManager.stop_clip()
		_apply_clip(note, result)
		# 다시 그리기 전에 지금까지 적은 글과 고른 유형을 잃지 않게 보관
		note.text = _text.text
		note.type = _type_row.selected
		_rebuild_note()
		if _rec_time != null:
			_rec_time.text = "clip saved" if not result.is_empty() else "recording failed"
			if NoteManager.last_clip_warning != "":
				_rec_time.text += "  ·  " + NoteManager.last_clip_warning
	else:
		NoteManager.start_clip(note.id)
	_update_rec_button()


func _on_save_note_pressed() -> void:
	if NoteManager.is_clip_recording:
		_apply_clip(note, NoteManager.stop_clip())
	note.type = _type_row.selected
	note.text = _text.text.strip_edges()
	note.author = NoteManager.author_name
	note.role = NoteManager.author_role
	if note.text == "" and not note.has_media():
		_text.placeholder_text = "Write something or record a clip first."
		return
	var n := note
	NoteManager.add_note(n)
	show_note(n)


func _on_cancel_pressed() -> void:
	var n := note
	note = null
	mode = Mode.EMPTY
	if n != null and not NoteManager.notes.has(n.id):
		NoteManager.discard_media(n)
	_rebuild_note()
	closed.emit()


# ---- 답글 ----

func _ensure_pending_reply() -> NoteData:
	if _pending_reply == null:
		var r := NoteData.make_new()
		r.parent_id = note.id
		r.position = note.position
		r.normal = note.normal
		r.anchor_name = note.anchor_name
		r.camera_position = note.camera_position
		r.camera_rotation = note.camera_rotation
		r.author = NoteManager.author_name
		r.role = NoteManager.author_role
		_pending_reply = r
	return _pending_reply


func _on_reply_record_pressed() -> void:
	var r := _ensure_pending_reply()
	if NoteManager.is_clip_recording:
		var result := NoteManager.stop_clip()
		_apply_clip(r, result)
		_reply_rec.text = "● ✓" if not result.is_empty() else "●"
		_rec_time.text = "clip attached. Press Send." if not result.is_empty() else "recording failed"
	else:
		NoteManager.start_clip(r.id)
		_reply_rec.text = "■"


func _send_reply() -> void:
	var r := _ensure_pending_reply()
	if NoteManager.is_clip_recording:
		_apply_clip(r, NoteManager.stop_clip())
	r.text = _reply_edit.text.strip_edges()
	r.type = _reply_type.selected
	r.author = NoteManager.author_name
	r.role = NoteManager.author_role
	if r.text == "" and not r.has_media():
		_reply_edit.placeholder_text = "Type or record something first"
		return
	_pending_reply = null
	NoteManager.add_note(r)   # note_added -> _rebuild_note


func _on_toggle_resolved() -> void:
	if note != null:
		NoteManager.set_resolved(note.id, not note.resolved)


func _on_delete_pressed() -> void:
	_confirm_delete.popup_centered()


func _on_delete_confirmed() -> void:
	if note != null:
		NoteManager.remove_note(note.id)


func _on_apply_identity() -> void:
	NoteManager.set_identity(_name_edit.text, _role_row.selected)
	_status.text = "Now signing as %s (%s)" % [NoteManager.author_name, NoteData.ROLE_NAMES[NoteManager.author_role]]


func _on_clear_pressed() -> void:
	if not NoteManager.notes.is_empty():
		_confirm_clear.popup_centered()


# ---- NoteManager 신호 ----

func _on_note_changed(n: NoteData) -> void:
	if mode == Mode.VIEW and note != null and (n.id == note.id or n.parent_id == note.id):
		_rebuild_note()
	if visible and _tabs.current_tab == Tab.LIST:
		refresh_list()


func _on_note_removed(id: String) -> void:
	if note != null and id == note.id:
		note = null
		mode = Mode.EMPTY
		_rebuild_note()
	if visible and _tabs.current_tab == Tab.LIST:
		refresh_list()


func _on_reloaded() -> void:
	if mode == Mode.VIEW:
		note = null
		mode = Mode.EMPTY
		_rebuild_note()
	refresh_list()


# =====================================================================
#  List 탭
# =====================================================================

func refresh_list() -> void:
	if _items == null:
		return
	var prev := _selected_id()
	_items.clear()
	_shown_ids.clear()
	var all := NoteManager.top_level_notes()
	for n in all:
		if _type_filter.selected > 0 and n.type != _type_filter.selected - 1:
			continue
		if _role_filter.selected > 0 and n.role != _role_filter.selected - 1:
			continue
		if n.resolved and not _show_resolved.button_pressed:
			continue
		var replies := NoteManager.replies_of(n.id).size()
		var label := "%s  %s" % [n.role_initial(), n.short_text(34)]
		if n.text == "":
			label = "%s  (voice)" % n.role_initial()
		if n.anchor_name != "":
			label += "   @" + n.anchor_name
		if replies > 0:
			label += "   +%d" % replies
		if NoteManager.is_conflict(n.anchor_name) and not n.resolved:
			label += "   !"
		if n.resolved:
			label += "   ✓"
		var idx := _items.add_item(label)
		_items.set_item_metadata(idx, n.id)
		_items.set_item_tooltip(idx, "%s · %s · %s · %s" % [n.type_name(), n.role_name(), n.author, n.created_at])
		var c := n.color()
		if n.resolved:
			c = c.lerp(Color(0.6, 0.6, 0.6), 0.65)
		_items.set_item_custom_fg_color(idx, c)
		_shown_ids.append(n.id)
		if n.id == prev:
			_items.select(idx)
	var conflicts := NoteManager.conflict_anchors()
	var txt := "Notes  %d / %d" % [_shown_ids.size(), all.size()]
	if not conflicts.is_empty():
		txt += "     !  conflict on " + ", ".join(conflicts)
	_count.text = txt


func _selected_id() -> String:
	var sel := _items.get_selected_items()
	if sel.is_empty():
		return ""
	return str(_items.get_item_metadata(sel[0]))


func _on_list_open() -> void:
	var n := NoteManager.get_note(_selected_id())
	if n != null:
		show_note(n)


func _on_list_goto() -> void:
	var n := NoteManager.get_note(_selected_id())
	if n != null:
		goto_requested.emit(n)
		show_note(n)


func _on_tour_pressed() -> void:
	if _shown_ids.is_empty():
		_count.text = "Nothing to tour with these filters"
		return
	tour_requested.emit(_shown_ids.duplicate())


# =====================================================================
#  Session 탭
# =====================================================================

func _sync_identity() -> void:
	if _name_edit == null:
		return
	_name_edit.text = NoteManager.author_name
	_role_row.set_selected(NoteManager.author_role)


func _refresh_sessions() -> void:
	_session_opt.clear()
	for f in NoteManager.list_sessions():
		_session_opt.add_item(f)
	if _session_opt.item_count == 0:
		_session_opt.add_item("(no saved sessions)")
		_session_opt.disabled = true
	else:
		_session_opt.disabled = false


func _on_save_pressed() -> void:
	var path := NoteManager.save_session(_session_name.text)
	_status.text = ("Saved  " + path.get_file()) if path != "" else "Save failed"
	_refresh_sessions()


func _on_load_pressed() -> void:
	if _session_opt.disabled:
		return
	_pending_load = NoteManager.session_path(_session_opt.get_item_text(_session_opt.selected))
	if NoteManager.notes.is_empty():
		_on_load_confirmed()
	else:
		_confirm_load.popup_centered()


func _on_load_confirmed() -> void:
	var count := NoteManager.load_session(_pending_load, true)
	_status.text = "Loaded %d notes from %s" % [count, _pending_load.get_file()]


func _on_export_pressed() -> void:
	if NoteManager.notes.is_empty():
		_status.text = "No notes to export"
		return
	var path := NoteManager.export_report(_session_name.text)
	if path == "":
		_status.text = "Export failed"
		return
	_status.text = "Report saved  " + path.get_file()
	OS.shell_open(ProjectSettings.globalize_path(path))
