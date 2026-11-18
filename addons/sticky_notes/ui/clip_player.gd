class_name ClipPlayer
extends Control
## 클립 재생기 (2D). 프레임 JPG + 음성 WAV.
##   immersive = true (VR 보드) 면 직접 재생하지 않고 play_requested 를 내보내 몰입 재생기에 넘긴다.
##   변환 중이면 "processing…", 클립이 없으면 썸네일만.

signal play_requested(note: NoteData)

var big: bool = false
var immersive: bool = false

var _image: TextureRect
var _btn: Button
var _time: Label
var _player: AudioStreamPlayer
var _frames := ClipFrames.new()
var _note: NoteData = null
var _playing: bool = false
var _t: float = 0.0
var _has_audio: bool = false
var _holo: HoloMotion = null      # set when the note has a holonote (played as a ghost, not here)


func _init(height: float = 180.0, is_big: bool = false, is_immersive: bool = false) -> void:
	big = is_big
	immersive = is_immersive
	custom_minimum_size = Vector2(0, height)
	clip_contents = true

	_image = TextureRect.new()
	_image.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_image)

	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE, PRESET_MODE_MINSIZE, 6)
	bar.grow_vertical = GROW_DIRECTION_BEGIN
	add_child(bar)
	_btn = NoteUiKit.color_button("▶  Play", NoteData.TYPE_COLORS[2], _toggle) if big else NoteUiKit.button("▶  Play", _toggle)
	if big:
		_btn.custom_minimum_size = Vector2(0, 60)
		_btn.add_theme_font_size_override("font_size", 22)
		_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(_btn)
	_time = NoteUiKit.label("", 20 if big else 12, NoteUiKit.FG)
	_time.size_flags_vertical = SIZE_SHRINK_CENTER
	bar.add_child(_time)

	_player = AudioStreamPlayer.new()
	add_child(_player)


func _ready() -> void:
	NoteManager.clip_ready.connect(_on_clip_ready)
	NoteManager.holo_playback_changed.connect(_on_holo_playback)


func _on_holo_playback(id: String, on: bool) -> void:
	if _holo == null or _note == null or id != _note.id:
		return
	_btn.text = "■  Stop" if on else _holo_label()


func _holo_label() -> String:
	return "▶  Play holonote"


func _on_clip_ready(id: String) -> void:
	if _note != null and id == _note.id:
		var n := NoteManager.get_note(id)
		if n != null:
			load_note(n)


## note의 클립 / 음성 / 썸네일 중 있는 것을 보여준다. 보여줄 게 없으면 false.
func load_note(note: NoteData) -> bool:
	stop()
	_note = note
	_has_audio = false
	_image.texture = null
	_btn.visible = false
	_time.text = ""
	_holo = NoteManager.load_holo(note.holo_file) if note.has_holo() else null

	if _holo != null:
		_image.texture = NoteManager.load_screenshot(note.screenshot_file)
		_btn.visible = true
		_btn.text = "■  Stop" if NoteManager.is_holo_playing(note.id) else _holo_label()
		_time.text = "%.0fs" % _holo.duration
		if not _holo.has_audio:
			_time.text += "  ·  no voice"
		return true

	if _frames.load(note):
		if not _frames.ready:
			_image.texture = NoteManager.load_screenshot(note.screenshot_file)
			_time.text = "video conversion failed (see ffmpeg_convert.log)" if _frames.failed else "processing video…"
			return true
		_image.texture = _frames.texture_index(1)
		if _frames.audio_file != "":
			_player.stream = NoteManager.load_audio(_frames.audio_file)
			_has_audio = _player.stream != null
		_btn.visible = true
		_btn.text = "▶  Play clip" if immersive else "▶  Play"
		_time.text = "%.0fs" % _frames.duration
		if _frames.audio_silent:
			_time.text += "  ·  mic was silent"
		return true

	if note.audio_file != "":
		_player.stream = NoteManager.load_audio(note.audio_file)
		_has_audio = _player.stream != null
		_btn.visible = _has_audio
		_btn.text = "▶  Play voice"
	_image.texture = NoteManager.load_screenshot(note.screenshot_file)
	return _image.texture != null or _has_audio


func _toggle() -> void:
	if _holo != null:
		print("Holo|INFO: play button pressed (note %s, immersive=%s, playing=%s)" % [_note.id, immersive, NoteManager.is_holo_playing(_note.id)])
		if NoteManager.is_holo_playing(_note.id):
			NoteManager.stop_holo_playback()
		elif immersive:
			play_requested.emit(_note)        # VR: the theater fades and moves you behind the ghost
		else:
			NoteManager.play_holo(_note)      # desktop: step behind the ghost and watch
		return
	if immersive and _frames.ready:
		play_requested.emit(_note)
		return
	if _playing:
		stop()
	else:
		play()


func play() -> void:
	_t = 0.0
	_playing = true
	_btn.text = "■  Stop"
	if _has_audio:
		_player.play()


func stop() -> void:
	_playing = false
	_player.stop()
	_btn.text = "▶  Play"
	if _frames.ready:
		_image.texture = _frames.texture_index(1)


func _process(delta: float) -> void:
	if not _playing:
		return
	_t = _player.get_playback_position() if _has_audio and _player.playing else _t + delta
	var dur := _frames.duration if _frames.ready else 0.0
	if _frames.ready:
		_image.texture = _frames.texture_at(_t)
		_time.text = "%.1f / %.0fs" % [_t, dur]
	var finished := (_has_audio and not _player.playing) or (not _has_audio and dur > 0.0 and _t >= dur)
	if finished:
		stop()
