class_name NoteUiKit
extends RefCounted
## UI 공통 토큰과 빌더. 모든 UI는 코드로 만들어서 .tscn 없이 옮겨진다.
##
## 톤: 거의 무채색. 색은 노트 유형 다섯 가지에만 쓴다.

const BG := Color(0.10, 0.11, 0.13, 0.90)
const BG_SOFT := Color(1, 1, 1, 0.06)
const BG_SOFTER := Color(1, 1, 1, 0.03)
const FG := Color(0.93, 0.93, 0.92)
const MUTED := Color(0.93, 0.93, 0.92, 0.55)
const DARK := Color(0.08, 0.08, 0.08)
const RADIUS := 4


static func flat_style(color: Color, radius: int = RADIUS, pad: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


static func panel(color: Color = BG, pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat_style(color, RADIUS, pad))
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func label(text: String, size: int = 13, color: Color = FG, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func small(text: String = "") -> Label:
	return label(text, 12, MUTED, true)


static func button(text: String, callback: Callable, flat: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = flat
	b.add_theme_font_size_override("font_size", 13)
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


## 유형 색을 입힌 작은 버튼. 토글로 쓰면 꺼졌을 때 흐려진다.
static func color_button(text: String, c: Color, callback: Callable, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_stylebox_override("normal", flat_style(Color(c, 0.14), RADIUS, 5))
	b.add_theme_stylebox_override("hover", flat_style(Color(c, 0.28), RADIUS, 5))
	b.add_theme_stylebox_override("pressed", flat_style(c, RADIUS, 5))
	b.add_theme_stylebox_override("hover_pressed", flat_style(c.lightened(0.1), RADIUS, 5))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", c.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", DARK)
	b.add_theme_color_override("font_hover_pressed_color", DARK)
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func separator() -> HSeparator:
	var s := HSeparator.new()
	s.modulate = Color(1, 1, 1, 0.25)
	return s


static func type_option(include_all: bool = false) -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 12)
	if include_all:
		o.add_item("All types")
	for i in NoteData.TYPE_NAMES.size():
		o.add_item(NoteData.TYPE_NAMES[i])
	return o


static func role_option(include_all: bool = false) -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 12)
	if include_all:
		o.add_item("All roles")
	for i in NoteData.ROLE_NAMES.size():
		o.add_item(NoteData.ROLE_NAMES[i])
	return o


## 한 줄(넘치면 줄바꿈)로 늘어선 단일 선택 버튼들. 유형 선택, 역할 선택에 쓴다.
class ChoiceRow extends HFlowContainer:
	signal changed(index: int)
	var selected: int = 0
	var _buttons: Array[Button] = []

	func _init(names: Array, colors: Array = []) -> void:
		add_theme_constant_override("h_separation", 4)
		add_theme_constant_override("v_separation", 4)
		for i in names.size():
			var c: Color = colors[i] if i < colors.size() else NoteUiKit.FG
			var b := NoteUiKit.color_button(str(names[i]), c, Callable(), true)
			b.pressed.connect(_on_pressed.bind(i))
			add_child(b)
			_buttons.append(b)
		set_selected(0)

	func set_selected(i: int) -> void:
		selected = clampi(i, 0, _buttons.size() - 1)
		for k in _buttons.size():
			_buttons[k].set_pressed_no_signal(k == selected)

	func _on_pressed(i: int) -> void:
		set_selected(i)
		changed.emit(i)
