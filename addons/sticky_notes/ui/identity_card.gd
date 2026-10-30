class_name IdentityCard
extends Control
## 세션 시작 때 한 번 뜨는 명함. 이름과 역할을 정하면 이후 모든 노트에 찍힌다.
## compact = true (VR 보드)면 타이핑이 없으므로 이름은 마지막으로 쓴 것을 그대로 쓰고 역할만 고른다.

signal done

var compact: bool = false

var _name: LineEdit
var _name_label: Label
var _role: NoteUiKit.ChoiceRow


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.3)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := NoteUiKit.panel(NoteUiKit.BG, 20)
	panel.custom_minimum_size = Vector2(340 if compact else 380, 0)
	center.add_child(panel)
	var v := NoteUiKit.vbox(10)
	panel.add_child(v)

	v.add_child(NoteUiKit.label("Who are you in this review?", 18))
	if compact:
		v.add_child(NoteUiKit.small("Pick your role. Your name is the last one used on this computer. To change it, open the project on desktop once."))
		_name_label = NoteUiKit.label("", 14)
		v.add_child(_name_label)
	else:
		v.add_child(NoteUiKit.small("Your name and role are stamped on every note you leave. You can change them later in the Session tab."))
		_name = LineEdit.new()
		_name.placeholder_text = "Your name"
		_name.text_submitted.connect(func(_t: String) -> void: _submit())
		v.add_child(_name)

	_role = NoteUiKit.ChoiceRow.new(NoteData.ROLE_NAMES)
	v.add_child(_role)

	var row := NoteUiKit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(NoteUiKit.button("Start", _submit))
	v.add_child(row)
	hide()


func open() -> void:
	if compact:
		_name_label.text = "Name  " + NoteManager.author_name
	else:
		_name.text = NoteManager.author_name if NoteManager.identity_set else ""
		_name.grab_focus()
	_role.set_selected(NoteManager.author_role)
	show()


func close() -> void:
	hide()


func _submit() -> void:
	var n := NoteManager.author_name if compact else _name.text
	NoteManager.set_identity(n, _role.selected)
	done.emit()
