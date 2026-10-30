class_name VRPanel
extends Control
## VR 보드용 패널. 크고, 타이핑이 없고, 지금 무엇을 해야 하는지 맨 위에 늘 적혀 있다.
##   화면 하나 = 상태 한 줄 + 내용 + 큰 버튼들
##   화면: NOTE (비어 있음 / 작성 중 / 보기), LIST, SESSION

signal closed
signal goto_requested(note: NoteData)
signal tour_requested(ids: Array)
signal tour_step(direction: int)     # +1 다음, -1 이전, 0 종료
signal play_requested(note: NoteData)   # 몰입 재생

var tour_label: String = ""          # 비어 있지 않으면 투어 중

enum Tab { NOTE, LIST, SESSION }
enum Mode { EMPTY, EDIT, VIEW }

const F_STATUS := 22
const F_TITLE := 26
const F_BODY := 20
const F_SMALL := 17
const BTN_H := 64
const BTN_H_SMALL := 52

var mode: int = Mode.EMPTY
var note: NoteData = null
var tab: int = Tab.NOTE

var _status: Label
var _status_panel: PanelContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _nav: HBoxContainer
var _nav_buttons: Array[Button] = []
var _level: ProgressBar
var _level_text: Label
var _rec_btn: Button
var _clip: ClipPlayer
var _type_row: NoteUiKit.ChoiceRow
var _items: ItemList
var _shown_ids: Array = []
var _type_filter: OptionButton
var _role_filter: OptionButton
var _session_opt: OptionButton
var _role_row: NoteUiKit.ChoiceRow
var _pending_reply: NoteData = null
var _confirm_delete: ConfirmationDialog
var _confirm_clear: ConfirmationDialog
var _confirm_load: ConfirmationDialog
var _pending_load: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	var col := NoteUiKit.vbox(8)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 8)
	add_child(col)

	# 상태 한 줄
	_status_panel = NoteUiKit.panel(NoteUiKit.BG_SOFT, 10)
	col.add_child(_status_panel)
	_status = NoteUiKit.label("", F_STATUS, NoteUiKit.FG, true)
	_status_panel.add_child(_status)

	# 마이크 레벨
	_level = ProgressBar.new()
	_level.min_value = 0.0
	_level.max_value = 1.0
	_level.show_percentage = false
	_level.custom_minimum_size = Vector2(0, 10)
	_level.add_theme_stylebox_override("fill", NoteUiKit.flat_style(NoteData.TYPE_COLORS[0], 3))
	_level.add_theme_stylebox_override("background", NoteUiKit.flat_style(NoteUiKit.BG_SOFTER, 3))
	col.add_child(_level)
	_level_text = NoteUiKit.label("", F_SMALL, NoteUiKit.MUTED, true)
	_level_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_level_text)

	# 내용
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	col.add_child(_scroll)
	_body = NoteUiKit.vbox(10)
	_body.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	# 아래 탭
	_nav = NoteUiKit.hbox(6)
	col.add_child(_nav)
	for i in ["Note", "List", "Session"].size():
		var b := NoteUiKit.button(["Note", "List", "Session"][i], _on_nav.bind(i))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, BTN_H_SMALL)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", F_BODY)
		_nav.add_child(b)
		_nav_buttons.append(b)

	_confirm_delete = _dialog("Delete this note and all its replies?", _on_delete_confirmed)
	_confirm_clear = _dialog("Remove all notes from the scene? Saved sessions are kept.", NoteManager.clear_all)
	_confirm_load = _dialog("Replace the current notes with this session?", _on_load_confirmed)

	NoteManager.note_added.connect(_on_note_changed)
	NoteManager.note_updated.connect(_on_note_changed)
	NoteManager.note_removed.connect(_on_note_removed)
	NoteManager.notes_reloaded.connect(_on_reloaded)
	NoteManager.recording_state_changed.connect(func(_on: bool) -> void: _rebuild())
	NoteManager.clip_ready.connect(func(_id: String) -> void: _rebuild())
	_rebuild()


## 오른쪽 스틱으로 내용 스크롤. amount 는 픽셀.
func scroll_by(amount: float) -> void:
	_scroll.scroll_vertical += int(amount)


func _dialog(text: String, cb: Callable) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.dialog_text = text
	d.confirmed.connect(cb)
	add_child(d)
	return d


func _process(_delta: float) -> void:
	if visible:
		_level.value = NoteManager.mic_level()
		if _level_text != null:
			_level_text.text = "Mic  " + NoteManager.mic_check_text()
		if NoteManager.is_clip_recording and _rec_btn != null:
			_rec_btn.text = "■  Stop   %.0fs" % NoteManager.clip_elapsed


# =====================================================================
#  열기 / 닫기 (XRNotePlacer가 부르는 API)
# =====================================================================

func open_tab(t: int) -> void:
	tab = t
	_rebuild()
	show()


func is_on_tab(t: int) -> bool:
	return visible and tab == t


func show_editor(n: NoteData) -> void:
	note = n
	mode = Mode.EDIT
	tab = Tab.NOTE
	_rebuild()
	show()


func show_note(n: NoteData) -> void:
	_pending_reply = null
	note = n
	mode = Mode.VIEW
	tab = Tab.NOTE
	NoteManager.set_focused(n.id)
	_rebuild()
	show()


func close() -> void:
	if mode == Mode.EDIT and note != null and not NoteManager.notes.has(note.id):
		NoteManager.discard_media(note)
	note = null
	mode = Mode.EMPTY
	NoteManager.set_focused("")
	hide()


## 그립을 쥐었을 때 (작성 중이면 녹화 시작/정지, 보기 중이면 답글 녹화 시작/정지)
func toggle_record_from_grip() -> void:
	if tab != Tab.NOTE:
		return
	if mode == Mode.EDIT or mode == Mode.VIEW:
		_on_record_pressed()


# =====================================================================
#  빌드
# =====================================================================

func _clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_rec_btn = null
	_clip = null
	_type_row = null
	_items = null


func _rebuild() -> void:
	if not is_node_ready():
		return
	_clear_body()
	for i in _nav_buttons.size():
		_nav_buttons[i].set_pressed_no_signal(i == tab)
	match tab:
		Tab.LIST:
			_build_list()
		Tab.SESSION:
			_build_session()
		_:
			match mode:
				Mode.EDIT:
					_build_editor()
				Mode.VIEW:
					_build_viewer()
				_:
					_build_empty()


func _set_status(text: String, color: Color = NoteUiKit.FG) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _big(text: String, cb: Callable, color: Color = Color.TRANSPARENT) -> Button:
	var b: Button
	if color == Color.TRANSPARENT:
		b = NoteUiKit.button(text, cb)
	else:
		b = NoteUiKit.color_button(text, color, cb)
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", F_BODY)
	return b


func _swatch_row(parent: Control, n: NoteData) -> void:
	var band := NoteUiKit.panel(n.color() if not n.resolved else Color(0.6, 0.6, 0.6), 8)
	var h := NoteUiKit.hbox()
	h.add_child(NoteUiKit.label(n.type_name().to_upper(), F_TITLE, NoteUiKit.DARK))
	h.add_child(NoteUiKit.spacer())
	h.add_child(NoteUiKit.label("RESOLVED" if n.resolved else n.role_name(), F_SMALL, NoteUiKit.DARK))
	band.add_child(h)
	parent.add_child(band)


func _build_empty() -> void:
	_set_status("Pull the trigger on a wall to leave a note.\nPoint at a note and hold the trigger 3 s to record.")
	var v := NoteUiKit.vbox(6)
	for i in NoteData.TYPE_NAMES.size():
		var row := NoteUiKit.hbox(12)
		var sw := ColorRect.new()
		sw.color = NoteData.TYPE_COLORS[i]
		sw.custom_minimum_size = Vector2(18, 18)
		sw.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(sw)
		row.add_child(NoteUiKit.label(NoteData.TYPE_NAMES[i], F_BODY))
		v.add_child(row)
	_body.add_child(v)
	_body.add_child(NoteUiKit.label(NoteManager.mic_status, F_SMALL, NoteUiKit.MUTED, true))


func _build_editor() -> void:
	var rec := NoteManager.is_clip_recording
	if rec:
		_set_status("●  Recording what you see and say.  Press Stop or release grip.", NoteData.TYPE_COLORS[0])
	elif note.has_media():
		_set_status("Clip attached. Pick a type, then press Save (or A).")
	else:
		_set_status("New note on %s.  Press Record (or hold grip) and talk." % note.anchor_name)

	_type_row = NoteUiKit.ChoiceRow.new(NoteData.TYPE_NAMES, NoteData.TYPE_COLORS)
	for b in _type_row.get_children():
		if b is Button:
			b.custom_minimum_size = Vector2(0, BTN_H_SMALL)
			b.add_theme_font_size_override("font_size", F_SMALL)
	_type_row.set_selected(note.type)
	_body.add_child(_type_row)

	_rec_btn = _big("■  Stop" if rec else ("●  Record again" if note.has_media() else "●  Record clip"), _on_record_pressed, NoteData.TYPE_COLORS[0])
	_rec_btn.custom_minimum_size = Vector2(0, BTN_H + 16)
	_rec_btn.add_theme_font_size_override("font_size", F_TITLE)
	_rec_btn.disabled = false
	_body.add_child(_rec_btn)

	if note.has_media() and not rec:
		_clip = ClipPlayer.new(200.0, true, true)
		_clip.play_requested.connect(func(n: NoteData) -> void: play_requested.emit(n))
		_clip.load_note(note)
		_body.add_child(_clip)

	var row := NoteUiKit.hbox(8)
	row.add_child(_big("Cancel", _on_cancel_pressed))
	var save := _big("Save   (A)", _on_save_pressed)
	save.disabled = not note.has_media() or rec
	row.add_child(save)
	_body.add_child(row)


func _build_viewer() -> void:
	if note == null or not NoteManager.notes.has(note.id):
		mode = Mode.EMPTY
		_build_empty()
		return
	note = NoteManager.notes[note.id]
	var rec := NoteManager.is_clip_recording
	if rec:
		_set_status("●  Recording screen and voice.  Pull the trigger again to stop.", NoteData.TYPE_COLORS[0])
	elif not note.has_media():
		_set_status("Note placed on %s.  Hold the trigger on it for 3 s to record." % note.anchor_name)
	else:
		var s := "%s · %s" % [note.author, note.short_time()]
		if note.anchor_name != "":
			s += "   on " + note.anchor_name
		if NoteManager.is_conflict(note.anchor_name) and not note.resolved:
			s += "\n!  Constraint and Proposal disagree here"
		_set_status(s)

	_swatch_row(_body, note)

	# 유형은 언제든 바꿀 수 있다
	_type_row = NoteUiKit.ChoiceRow.new(NoteData.TYPE_NAMES, NoteData.TYPE_COLORS)
	for b in _type_row.get_children():
		if b is Button:
			b.custom_minimum_size = Vector2(0, BTN_H_SMALL)
			b.add_theme_font_size_override("font_size", F_SMALL)
	_type_row.set_selected(note.type)
	_type_row.changed.connect(_on_type_changed)
	_body.add_child(_type_row)

	_clip = ClipPlayer.new(220.0, true, true)
	_clip.play_requested.connect(func(n: NoteData) -> void: play_requested.emit(n))
	if not _clip.load_note(note):
		_clip.queue_free()
		_clip = null
	else:
		_body.add_child(_clip)
	if note.text != "":
		_body.add_child(NoteUiKit.label(note.text, F_BODY, NoteUiKit.FG, true))

	if tour_label != "":
		_body.add_child(NoteUiKit.label(tour_label, F_SMALL, NoteUiKit.MUTED))
		var trow := NoteUiKit.hbox(8)
		trow.add_child(_big("◀  Prev", func() -> void: tour_step.emit(-1)))
		trow.add_child(_big("Next  ▶", func() -> void: tour_step.emit(1), NoteData.TYPE_COLORS[2]))
		trow.add_child(_big("End tour", func() -> void: tour_step.emit(0)))
		_body.add_child(trow)

	var row := NoteUiKit.hbox(8)
	row.add_child(_big("Go there", func() -> void: goto_requested.emit(note)))
	row.add_child(_big("Reopen" if note.resolved else "Resolve", _on_toggle_resolved))
	_body.add_child(row)

	var replies := NoteManager.replies_of(note.id)
	_body.add_child(NoteUiKit.label("Replies  %d" % replies.size(), F_SMALL, NoteUiKit.MUTED))
	for r in replies:
		_body.add_child(_bubble(r))

	var rec_label := "■  Stop recording"
	if not rec:
		rec_label = "●  Record a reply" if note.has_media() else "●  Record for this note"
	_rec_btn = _big(rec_label, _on_record_pressed, NoteData.TYPE_COLORS[0])
	_rec_btn.custom_minimum_size = Vector2(0, BTN_H + 16)
	_rec_btn.add_theme_font_size_override("font_size", F_TITLE)
	_body.add_child(_rec_btn)

	var row2 := NoteUiKit.hbox(8)
	row2.add_child(_big("Delete", func() -> void: _confirm_delete.popup_centered()))
	row2.add_child(_big("Close", _on_close_pressed))
	_body.add_child(row2)


func _bubble(r: NoteData) -> Control:
	var p := NoteUiKit.panel(NoteUiKit.BG_SOFT, 8)
	var v := NoteUiKit.vbox(6)
	p.add_child(v)
	var h := NoteUiKit.hbox(8)
	var band := ColorRect.new()
	band.color = r.color()
	band.custom_minimum_size = Vector2(6, 0)
	band.size_flags_vertical = SIZE_FILL
	h.add_child(band)
	h.add_child(NoteUiKit.label("%s · %s · %s" % [r.type_name(), r.author, r.short_time()], F_SMALL, NoteUiKit.MUTED, true))
	v.add_child(h)
	if r.has_media():
		var cp := ClipPlayer.new(140.0, true, true)
		cp.play_requested.connect(func(n: NoteData) -> void: play_requested.emit(n))
		if cp.load_note(r):
			v.add_child(cp)
		else:
			cp.queue_free()
	if r.text != "":
		v.add_child(NoteUiKit.label(r.text, F_BODY, NoteUiKit.FG, true))
	return p


func _build_list() -> void:
	var conflicts := NoteManager.conflict_anchors()
	_set_status("Notes  %d" % NoteManager.top_level_notes().size() + ("\n!  conflict on " + ", ".join(conflicts) if not conflicts.is_empty() else ""))

	var frow := NoteUiKit.hbox(6)
	_type_filter = NoteUiKit.type_option(true)
	_type_filter.add_theme_font_size_override("font_size", F_SMALL)
	_type_filter.custom_minimum_size = Vector2(0, BTN_H_SMALL)
	_type_filter.size_flags_horizontal = SIZE_EXPAND_FILL
	_type_filter.item_selected.connect(func(_i: int) -> void: _fill_items())
	frow.add_child(_type_filter)
	_role_filter = NoteUiKit.role_option(true)
	_role_filter.add_theme_font_size_override("font_size", F_SMALL)
	_role_filter.custom_minimum_size = Vector2(0, BTN_H_SMALL)
	_role_filter.size_flags_horizontal = SIZE_EXPAND_FILL
	_role_filter.item_selected.connect(func(_i: int) -> void: _fill_items())
	frow.add_child(_role_filter)
	_body.add_child(frow)

	_items = ItemList.new()
	_items.custom_minimum_size = Vector2(0, 300)
	_items.add_theme_font_size_override("font_size", F_BODY)
	_items.add_theme_constant_override("v_separation", 10)
	_items.item_activated.connect(func(_i: int) -> void: _on_list_open())
	_body.add_child(_items)
	_fill_items()

	var row := NoteUiKit.hbox(8)
	row.add_child(_big("Open", _on_list_open))
	row.add_child(_big("Go there", _on_list_goto))
	_body.add_child(row)
	_body.add_child(_big("Tour  ▶   (left stick ◀ ▶,  B ends)", _on_tour_pressed, NoteData.TYPE_COLORS[2]))


func _fill_items() -> void:
	if _items == null:
		return
	_items.clear()
	_shown_ids.clear()
	for n in NoteManager.top_level_notes():
		if _type_filter.selected > 0 and n.type != _type_filter.selected - 1:
			continue
		if _role_filter.selected > 0 and n.role != _role_filter.selected - 1:
			continue
		var label := "%s  %s" % [n.type_name(), n.author]
		if n.anchor_name != "":
			label += "   @" + n.anchor_name
		var replies := NoteManager.replies_of(n.id).size()
		if replies > 0:
			label += "   +%d" % replies
		if NoteManager.is_conflict(n.anchor_name) and not n.resolved:
			label += "   !"
		if n.resolved:
			label += "   ✓"
		var idx := _items.add_item(label)
		_items.set_item_metadata(idx, n.id)
		_items.set_item_custom_fg_color(idx, n.color() if not n.resolved else Color(0.6, 0.6, 0.6))
		_shown_ids.append(n.id)


func _build_session() -> void:
	_set_status("Signed as %s · %s" % [NoteManager.author_name, NoteData.ROLE_NAMES[NoteManager.author_role]])
	_body.add_child(NoteUiKit.label("Role", F_SMALL, NoteUiKit.MUTED))
	_role_row = NoteUiKit.ChoiceRow.new(NoteData.ROLE_NAMES)
	for b in _role_row.get_children():
		if b is Button:
			b.custom_minimum_size = Vector2(0, BTN_H_SMALL)
			b.add_theme_font_size_override("font_size", F_SMALL)
	_role_row.set_selected(NoteManager.author_role)
	_role_row.changed.connect(_on_role_changed)
	_body.add_child(_role_row)

	_body.add_child(NoteUiKit.separator())
	_body.add_child(NoteUiKit.label("Session", F_SMALL, NoteUiKit.MUTED))
	_body.add_child(_big("Save session now", _on_save_pressed_session))
	var lrow := NoteUiKit.hbox(6)
	_session_opt = OptionButton.new()
	_session_opt.add_theme_font_size_override("font_size", F_SMALL)
	_session_opt.custom_minimum_size = Vector2(0, BTN_H_SMALL)
	_session_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	for f in NoteManager.list_sessions():
		_session_opt.add_item(f)
	if _session_opt.item_count == 0:
		_session_opt.add_item("(no saved sessions)")
		_session_opt.disabled = true
	lrow.add_child(_session_opt)
	var load := _big("Load", _on_load_pressed)
	load.size_flags_horizontal = SIZE_SHRINK_END
	load.custom_minimum_size = Vector2(120, BTN_H_SMALL)
	lrow.add_child(load)
	_body.add_child(lrow)
	_body.add_child(_big("Export HTML report", _on_export_pressed))

	_body.add_child(NoteUiKit.separator())
	_body.add_child(NoteUiKit.label("Recording", F_SMALL, NoteUiKit.MUTED))
	if NoteManager.clip_mode == "ffmpeg":
		_body.add_child(NoteUiKit.label("Real video via ffmpeg. Fallback microphone for ffmpeg (used only if Godot cannot open a mic):", F_SMALL, NoteUiKit.FG, true))
		var fo := OptionButton.new()
		fo.add_theme_font_size_override("font_size", F_SMALL)
		fo.custom_minimum_size = Vector2(0, BTN_H_SMALL)
		for i in NoteManager.ffmpeg_audio_devices.size():
			fo.add_item(NoteManager.ffmpeg_audio_devices[i])
			if NoteManager.ffmpeg_audio_devices[i] == NoteManager.ffmpeg_audio_device:
				fo.selected = i
		if fo.item_count == 0:
			fo.add_item("(no audio device found)")
			fo.disabled = true
		fo.item_selected.connect(func(i: int) -> void: NoteManager.set_ffmpeg_audio_device(fo.get_item_text(i)))
		_body.add_child(fo)
	else:
		_body.add_child(NoteUiKit.label("Frame clips (no ffmpeg). Put ffmpeg.exe in tools/ for real video.", F_SMALL, NoteUiKit.FG, true))
	_body.add_child(NoteUiKit.label("Microphone for clips and voice notes (watch the level bar move):", F_SMALL, NoteUiKit.FG, true))
	var mo := OptionButton.new()
	mo.add_theme_font_size_override("font_size", F_SMALL)
	mo.custom_minimum_size = Vector2(0, BTN_H_SMALL)
	var devs := NoteManager.mic_devices()
	for i in devs.size():
		mo.add_item(devs[i])
		if devs[i] == NoteManager.mic_device:
			mo.selected = i
	mo.item_selected.connect(func(i: int) -> void: NoteManager.set_mic_device(mo.get_item_text(i)))
	_body.add_child(mo)
	_body.add_child(_big("Reconnect mic  (after Quest Link reconnects)", func() -> void: NoteManager.reconnect_mic()))
	_body.add_child(NoteUiKit.separator())
	_body.add_child(_big("Clear all notes", _on_clear_pressed))


# =====================================================================
#  동작
# =====================================================================

func _on_nav(i: int) -> void:
	open_tab(i)


func _on_role_changed(i: int) -> void:
	NoteManager.set_identity(NoteManager.author_name, i)
	_rebuild()


func _on_clear_pressed() -> void:
	if not NoteManager.notes.is_empty():
		_confirm_clear.popup_centered()


func _on_record_pressed() -> void:
	if NoteManager.is_clip_recording:
		_stop_and_attach()
		return
	if mode == Mode.EDIT and note != null:
		NoteManager.start_clip(note.id)
	elif mode == Mode.VIEW and note != null and not note.has_media():
		_pending_reply = null
		NoteManager.start_clip(note.id)
	elif mode == Mode.VIEW and note != null:
		var r := NoteData.make_new()
		r.parent_id = note.id
		r.position = note.position
		r.normal = note.normal
		r.anchor_name = note.anchor_name
		r.camera_position = note.camera_position
		r.camera_rotation = note.camera_rotation
		r.author = NoteManager.author_name
		r.role = NoteManager.author_role
		r.type = NoteData.default_type_for_role(NoteManager.author_role)
		_pending_reply = r
		NoteManager.start_clip(r.id)
	_rebuild()


func _stop_and_attach() -> void:
	var result := NoteManager.stop_clip()
	if mode == Mode.EDIT and note != null:
		if not result.is_empty():
			note.clip_file = result["clip_file"]
			note.audio_file = result["audio_file"]
			note.screenshot_file = result["screenshot_file"]
		if _type_row != null:
			note.type = _type_row.selected
	elif mode == Mode.VIEW and _pending_reply != null:
		if not result.is_empty():
			_pending_reply.clip_file = result["clip_file"]
			_pending_reply.audio_file = result["audio_file"]
			_pending_reply.screenshot_file = result["screenshot_file"]
			NoteManager.add_note(_pending_reply)
		_pending_reply = null
	elif mode == Mode.VIEW and note != null:
		if not result.is_empty():
			note.clip_file = result["clip_file"]
			note.audio_file = result["audio_file"]
			note.screenshot_file = result["screenshot_file"]
			NoteManager.update_note(note)
	_rebuild()


## XRNotePlacer 가 트리거로 녹화를 시작/정지할 때 부른다. 대상 노트를 열어 둔 채로.
func record_for_note(n: NoteData) -> void:
	if NoteManager.is_clip_recording:
		_stop_and_attach()
		return
	show_note(n)
	_on_record_pressed()


func stop_record_from_trigger() -> void:
	if NoteManager.is_clip_recording:
		_stop_and_attach()


func _on_type_changed(i: int) -> void:
	if note != null and NoteManager.notes.has(note.id):
		note.type = i
		NoteManager.update_note(note)


func _on_save_pressed() -> void:
	if note == null or mode != Mode.EDIT:
		return
	if NoteManager.is_clip_recording:
		_stop_and_attach()
	if not note.has_media():
		_set_status("Record a clip first.", NoteData.TYPE_COLORS[0])
		return
	if _type_row != null:
		note.type = _type_row.selected
	note.author = NoteManager.author_name
	note.role = NoteManager.author_role
	var n := note
	NoteManager.add_note(n)
	show_note(n)


func _on_cancel_pressed() -> void:
	close()
	closed.emit()


func _on_close_pressed() -> void:
	close()
	closed.emit()


func _on_toggle_resolved() -> void:
	if note != null:
		NoteManager.set_resolved(note.id, not note.resolved)


func _on_delete_confirmed() -> void:
	if note != null:
		NoteManager.remove_note(note.id)


func _on_note_changed(n: NoteData) -> void:
	if not visible:
		return
	if tab == Tab.LIST:
		_fill_items()
	elif mode == Mode.VIEW and note != null and (n.id == note.id or n.parent_id == note.id):
		_rebuild()


func _on_note_removed(id: String) -> void:
	if note != null and id == note.id:
		note = null
		mode = Mode.EMPTY
	if visible:
		_rebuild()


func _on_reloaded() -> void:
	if mode == Mode.VIEW:
		note = null
		mode = Mode.EMPTY
	if visible:
		_rebuild()


func _selected_id() -> String:
	if _items == null:
		return ""
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
		_set_status("Nothing to tour with these filters")
		return
	tour_requested.emit(_shown_ids.duplicate())


func _on_save_pressed_session() -> void:
	var path := NoteManager.save_session("")
	_set_status(("Saved  " + path.get_file()) if path != "" else "Save failed")


func _on_load_pressed() -> void:
	if _session_opt == null or _session_opt.disabled:
		return
	_pending_load = NoteManager.session_path(_session_opt.get_item_text(_session_opt.selected))
	if NoteManager.notes.is_empty():
		_on_load_confirmed()
	else:
		_confirm_load.popup_centered()


func _on_load_confirmed() -> void:
	var count := NoteManager.load_session(_pending_load, true)
	_set_status("Loaded %d notes" % count)


func _on_export_pressed() -> void:
	if NoteManager.notes.is_empty():
		_set_status("No notes to export")
		return
	var path := NoteManager.export_report("")
	_set_status(("Report saved  " + path.get_file()) if path != "" else "Export failed")
