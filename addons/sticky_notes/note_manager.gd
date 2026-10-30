extends Node
## Autoload 이름: NoteManager
##
## 모든 노트 데이터의 주인. 생성·삭제·저장·불러오기, 스크린샷 캡처,
## 음성 녹음, 유형별 표시/숨김, 충돌 계산, 리포트 내보내기, 텔레포트 요청을
## 한곳에서 처리한다. 다른 프로젝트에 합칠 때는 이 스크립트를 Autoload로 등록하기만 하면 된다.

signal note_added(note: NoteData)
signal note_updated(note: NoteData)
signal note_removed(id: String)
signal notes_reloaded
signal teleport_requested(camera_position: Vector3, camera_rotation: Vector3)
signal recording_state_changed(is_recording: bool)
signal identity_changed
signal visibility_changed
signal focus_changed(id: String)
signal clip_ready(note_id: String)   # ffmpeg 변환이 끝나 재생 가능해졌을 때

const ROOT_DIR := "user://sticky_notes/"
const SESSION_DIR := ROOT_DIR + "sessions/"
const MEDIA_DIR := ROOT_DIR + "media/"
const REPORT_DIR := ROOT_DIR + "reports/"
const IDENTITY_FILE := ROOT_DIR + "identity.cfg"
const RECORD_BUS := "Record"

## 이 세션의 나. 명함 카드에서 한 번 정하면 모든 노트에 찍힌다.
var author_name: String = "Guest"
var author_role: int = NoteData.Role.ARCHITECT
var identity_set: bool = false

var notes: Dictionary = {}                 # id -> NoteData (원 노트 + 답글 모두)
var notes_root: Node3D = null              # 3D 노트들이 들어갈 부모. 비워두면 current_scene 아래에 자동 생성
var type_visible: Array[bool] = [true, true, true, true, true]
var focused_id: String = ""                # 패널에서 보고 있는 노트. 월드에서 강조된다
var is_recording: bool = false

var _instances: Dictionary = {}            # id -> StickyNote (원 노트만)
var _conflicts: Dictionary = {}            # anchor_name -> true (제약과 제안이 같은 부재에 붙음)
var _mic_player: AudioStreamPlayer
var _record_effect: AudioEffectRecord
var _audio_cache: Dictionary = {}          # file -> AudioStreamWAV


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SESSION_DIR)
	DirAccess.make_dir_recursive_absolute(MEDIA_DIR)
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	_load_identity()
	_ensure_input_actions()
	_setup_recorder()
	_setup_microphone()
	_setup_ffmpeg()


# =====================================================================
#  나 (identity)
# =====================================================================

func set_identity(new_name: String, role: int) -> void:
	var trimmed := new_name.strip_edges()
	author_name = trimmed if trimmed != "" else "Guest"
	author_role = clampi(role, 0, NoteData.ROLE_NAMES.size() - 1)
	identity_set = true
	_save_identity()
	identity_changed.emit()


## 마지막으로 쓴 이름·역할을 기억해 둔다. VR에서는 타이핑이 없으므로 이걸 그대로 쓴다.
func _save_identity() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("identity", "name", author_name)
	cfg.set_value("identity", "role", author_role)
	cfg.set_value("audio", "mic_device", mic_device)
	cfg.set_value("audio", "ffmpeg_device", ffmpeg_audio_device)
	cfg.save(IDENTITY_FILE)


func _load_identity() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(IDENTITY_FILE) != OK:
		return
	author_name = str(cfg.get_value("identity", "name", author_name))
	author_role = int(cfg.get_value("identity", "role", author_role))
	mic_device = str(cfg.get_value("audio", "mic_device", ""))
	ffmpeg_audio_device = str(cfg.get_value("audio", "ffmpeg_device", ""))


# =====================================================================
#  노트 CRUD
# =====================================================================

func add_note(note: NoteData) -> void:
	notes[note.id] = note
	if not note.is_reply():
		_spawn_instance(note)
	_after_change()
	note_added.emit(note)


func update_note(note: NoteData) -> void:
	notes[note.id] = note
	_after_change()
	note_updated.emit(note)


func set_resolved(id: String, value: bool) -> void:
	if not notes.has(id):
		return
	var n: NoteData = notes[id]
	n.resolved = value
	update_note(n)


## 노트와 그 답글, 딸린 미디어 파일까지 지운다.
func remove_note(id: String) -> void:
	if not notes.has(id):
		return
	var target: NoteData = notes[id]
	for r in replies_of(id):
		_delete_media(r)
		notes.erase(r.id)
		note_removed.emit(r.id)
	_delete_media(target)
	notes.erase(id)
	if _instances.has(id):
		var inst: Node = _instances[id]
		_instances.erase(id)
		if is_instance_valid(inst):
			inst.queue_free()
	if focused_id == id:
		focused_id = ""
	_after_change()
	note_removed.emit(id)


func clear_all() -> void:
	for inst in _instances.values():
		if is_instance_valid(inst):
			inst.queue_free()
	_instances.clear()
	notes.clear()
	focused_id = ""
	_conflicts.clear()
	notes_reloaded.emit()


func get_note(id: String) -> NoteData:
	return notes.get(id, null)


## 원 노트만 (답글 제외), 오래된 순
func top_level_notes() -> Array[NoteData]:
	var out: Array[NoteData] = []
	for n in notes.values():
		if not n.is_reply():
			out.append(n)
	out.sort_custom(func(a: NoteData, b: NoteData) -> bool: return a.created_at < b.created_at)
	return out


func replies_of(parent_id: String) -> Array[NoteData]:
	var out: Array[NoteData] = []
	for n in notes.values():
		if n.parent_id == parent_id:
			out.append(n)
	out.sort_custom(func(a: NoteData, b: NoteData) -> bool: return a.created_at < b.created_at)
	return out


func counts_by_type() -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0, 0]
	for n in top_level_notes():
		out[clampi(n.type, 0, 4)] += 1
	return out


## 에디터에서 취소했을 때, 이미 찍힌 스크린샷·음성을 지운다.
func discard_media(note: NoteData) -> void:
	if is_clip_recording and _clip_id == note.id:
		cancel_clip()
	_delete_media(note)


func request_teleport(note: NoteData) -> void:
	teleport_requested.emit(note.camera_position, note.camera_rotation)


# =====================================================================
#  표시/숨김, 강조, 충돌
# =====================================================================

func set_type_visible(t: int, on: bool) -> void:
	t = clampi(t, 0, 4)
	if type_visible[t] == on:
		return
	type_visible[t] = on
	_refresh_all()
	visibility_changed.emit()


func toggle_type_visible(t: int) -> void:
	set_type_visible(t, not type_visible[clampi(t, 0, 4)])


func set_focused(id: String) -> void:
	if focused_id == id:
		return
	var old := focused_id
	focused_id = id
	_refresh_instance(old)
	_refresh_instance(id)
	focus_changed.emit(id)


## 같은 부재에 열린 Constraint와 Proposal이 함께 붙어 있으면 충돌로 본다.
func is_conflict(anchor_name: String) -> bool:
	return anchor_name != "" and _conflicts.has(anchor_name)


func conflict_anchors() -> Array:
	var out := _conflicts.keys()
	out.sort()
	return out


func _recompute_conflicts() -> void:
	_conflicts.clear()
	var per_anchor: Dictionary = {}   # anchor -> {type: true}
	for n in notes.values():
		if n.resolved or n.anchor_name == "":
			continue
		if n.is_reply():
			var p: NoteData = notes.get(n.parent_id, null)
			if p != null and p.resolved:
				continue
		if not per_anchor.has(n.anchor_name):
			per_anchor[n.anchor_name] = {}
		per_anchor[n.anchor_name][n.type] = true
	for a in per_anchor:
		var types: Dictionary = per_anchor[a]
		if types.has(NoteData.Type.CONSTRAINT) and types.has(NoteData.Type.PROPOSAL):
			_conflicts[a] = true


func _after_change() -> void:
	_recompute_conflicts()
	_refresh_all()


# =====================================================================
#  3D 인스턴스
# =====================================================================

func _get_notes_root() -> Node3D:
	if is_instance_valid(notes_root) and notes_root.is_inside_tree():
		return notes_root
	var scene := get_tree().current_scene
	if scene == null:
		return null
	notes_root = Node3D.new()
	notes_root.name = "StickyNotesRoot"
	scene.add_child(notes_root)
	return notes_root


func _spawn_instance(note: NoteData) -> void:
	var root := _get_notes_root()
	if root == null:
		push_warning("StickyNotes: current_scene이 없어 노트를 표시할 수 없습니다.")
		return
	var inst := StickyNote.new()
	inst.name = "Note_" + note.id
	root.add_child(inst)
	inst.setup(note)
	_instances[note.id] = inst


func _refresh_instance(id: String) -> void:
	if id != "" and _instances.has(id) and is_instance_valid(_instances[id]):
		_instances[id].refresh()


func _refresh_all() -> void:
	for inst in _instances.values():
		if is_instance_valid(inst):
			inst.refresh()


# =====================================================================
#  녹화 카메라 (스크린샷·클립 공용)
#  내 머리를 따라가는 SubViewport 하나로 찍는다. 모니터 미러나 데스크톱과는
#  무관하게 언제나 VR 시점(머리 방향 단안 뷰)만 들어간다.
#
#  ffmpeg 가 있으면  Godot 이 그린 프레임을 ffmpeg 의 stdin 으로 파이프 → x264 mp4.
#                   음성은 Godot 마이크(AudioEffectRecord)로 같은 시계에 맞춰 녹음해 두었다가 끝날 때 합친다.
#                   Godot 이 마이크를 못 열면 ffmpeg 가 dshow 로 직접 받는다 (폴백).
#  ffmpeg 가 없으면  초당 CLIP_FPS 장 JPG + Godot 마이크 (Quest 단독 실행)
# =====================================================================

const REC_W := 1280                 # 스크린샷·클립 해상도
const REC_H := 720
const REC_FPS := 24.0               # ffmpeg 파이프 녹화 프레임 수
const CLIP_CRF := 20                # x264 품질. 낮을수록 좋고 파일이 커진다 (18~23)
const FALLBACK_W := 640             # ffmpeg 없을 때(프레임 방식) 해상도
const FALLBACK_H := 360
const CLIP_FPS := 8.0               # 프레임 방식 fps
const CLIP_MAX_SEC := 30.0
const PLAY_FPS := 15.0              # 재생용 JPG 프레임 (mp4 에서 뽑는다)
const PLAY_W := 1280
const SILENT_DB := -55.0            # 녹음된 음성이 이보다 조용하면 "마이크가 안 잡혔다"고 알린다

var _rec_vp: SubViewport
var _rec_cam: Camera3D

## 클립 녹화 상태
var is_clip_recording: bool = false
var clip_elapsed: float = 0.0
var last_clip_warning: String = ""     # 마지막 녹화에서 생긴 문제. 비어 있으면 정상
var _clip_dir: String = ""
var _clip_id: String = ""
var _clip_frames: int = 0
var _clip_next_t: float = 0.0
var _clip_has_audio: bool = false

var ffmpeg_path: String = ""
var ffmpeg_audio_device: String = ""              # dshow 친화 이름 (UI·저장용)
var ffmpeg_audio_devices: Array[String] = []
var clip_mode: String = "frames"                  # "ffmpeg" 또는 "frames"
var _ff_alt_names: Dictionary = {}                # 친화 이름 -> dshow 대체 이름 (@device_cm_...). 이쪽이 확실하다
var _jobs: Array[ClipJob] = []                    # 녹화 중이거나 변환 중인 작업
var _job: ClipJob = null                          # 지금 녹화 중인 작업
var _ff_checked: bool = false
var _pipe_sent: int = 0


## 녹화 하나 = ffmpeg 프로세스 하나 + 프레임을 파이프에 써 주고 끝나면 변환까지 하는 스레드 하나.
## 메인 스레드는 큐에 프레임을 넣기만 하므로 VR 프레임이 끊기지 않는다.
class ClipJob:
	var id: String = ""
	var dir: String = ""
	var pipe: Dictionary = {}
	var pid: int = -1
	var has_audio: bool = false       # 최종 mp4 에 음성이 들어가는가
	var dshow: bool = false           # ffmpeg 가 dshow 로 직접 녹음 중 (폴백)
	var godot_wav: String = ""        # Godot 이 녹음한 wav (절대 경로). 끝날 때 영상과 합친다
	var mutex := Mutex.new()
	var sem := Semaphore.new()
	var queue: Array[PackedByteArray] = []
	var stop: bool = false
	var cancel: bool = false
	var dropped: int = 0
	var keep_dir: bool = false     # 취소해도 폴더는 남긴다 (마이크 없이 다시 시작할 때)
	var thread: Thread = null

	func push(data: PackedByteArray) -> void:
		mutex.lock()
		if queue.size() >= 12:
			dropped += 1
		else:
			queue.append(data)
		mutex.unlock()
		sem.post()

	func finish(cancelled: bool) -> void:
		mutex.lock()
		stop = true
		cancel = cancelled
		mutex.unlock()
		sem.post()


func _setup_ffmpeg() -> void:
	# 내보낸 빌드에서는 res:// 가 pck 안이라 실행할 수 없으므로 exe 옆(과 그 아래 tools/)을 먼저 본다.
	var exe_dir := OS.get_executable_path().get_base_dir()
	var candidates := [
		exe_dir.path_join("ffmpeg.exe"),
		exe_dir.path_join("tools/ffmpeg.exe"),
		ProjectSettings.globalize_path("res://tools/ffmpeg.exe"),
		ProjectSettings.globalize_path("res://tools/ffmpeg"),
		"ffmpeg",
	]
	for c in candidates:
		var out := []
		if OS.execute(c, ["-version"], out, true) == 0:
			ffmpeg_path = c
			break
	if ffmpeg_path == "":
		clip_mode = "frames"
		print("habitat_notes: ffmpeg not found. Clips use the frame method. Put ffmpeg.exe in res://tools/ for real video.")
		return
	clip_mode = "ffmpeg"
	# dshow 오디오 장치 목록. 친화 이름 바로 아래 줄의 "Alternative name" 이 확실한 식별자다.
	var out := []
	OS.execute(ffmpeg_path, ["-hide_banner", "-list_devices", "true", "-f", "dshow", "-i", "dummy"], out, true)
	var devices: Array[String] = []
	var last_audio := ""
	for line in "\n".join(out).split("\n"):
		if line.contains("(audio)"):
			var n := _quoted(line)
			if n != "":
				devices.append(n)
			last_audio = n
		elif line.contains("(video)"):
			last_audio = ""
		elif last_audio != "" and line.contains("Alternative name"):
			var alt := _quoted(line)
			if alt != "":
				_ff_alt_names[last_audio] = alt
			last_audio = ""
	ffmpeg_audio_devices = devices
	print("habitat_notes: ffmpeg found. dshow audio devices = ", devices)
	ffmpeg_audio_device = _pick_device(devices, ffmpeg_audio_device)


static func _quoted(line: String) -> String:
	var a := line.find("\"")
	var b := line.find("\"", a + 1)
	if a >= 0 and b > a:
		return line.substr(a + 1, b - a - 1)
	return ""


func _pick_device(devices: Array, saved: String) -> String:
	if saved != "" and devices.has(saved):
		return saved
	for d in devices:
		var low := str(d).to_lower()
		if low.contains("oculus") or low.contains("quest") or low.contains("headset"):
			return str(d)
	return str(devices[0]) if not devices.is_empty() else ""


func set_ffmpeg_audio_device(name_: String) -> void:
	ffmpeg_audio_device = name_
	_save_identity()


## dshow 에 넘길 장치 이름. 대체 이름이 있으면 그것을 쓴다 (이름이 겹치거나 공백·특수문자가 있어도 안전).
func _dshow_audio_input() -> String:
	return str(_ff_alt_names.get(ffmpeg_audio_device, ffmpeg_audio_device))


func _setup_recorder() -> void:
	_rec_vp = SubViewport.new()
	_rec_vp.name = "RecorderViewport"
	_rec_vp.size = Vector2i(REC_W, REC_H)
	_rec_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_rec_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_rec_vp)
	_rec_cam = Camera3D.new()
	_rec_cam.fov = 80.0
	_rec_cam.current = true
	_rec_vp.add_child(_rec_cam)


func _follow_head() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and _rec_cam != null:
		_rec_cam.global_transform = cam.global_transform


func _grab_frame() -> Image:
	_follow_head()
	_rec_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	return _rec_vp.get_texture().get_image()


## 내 시점 한 장을 media 폴더에 저장하고 파일 이름을 돌려준다.
func capture_screenshot(note_id: String) -> String:
	var img: Image = await _grab_frame()
	if img == null:
		return ""
	var file := "shot_%s.png" % note_id
	if img.save_png(MEDIA_DIR + file) != OK:
		push_warning("StickyNotes: 스크린샷 저장 실패")
		return ""
	return file


func load_screenshot(file: String) -> Texture2D:
	if file == "":
		return null
	var path := MEDIA_DIR + file
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


# ---------------- 클립 (화면 + 음성) ----------------

## 녹화 시작. ffmpeg 가 있으면 진짜 영상, 없으면 프레임 방식. 마이크가 없어도 화면은 녹화한다.
func start_clip(note_id: String) -> bool:
	if is_clip_recording:
		return false
	_clip_id = note_id
	_clip_dir = MEDIA_DIR + "clip_%s/" % note_id
	DirAccess.make_dir_recursive_absolute(_clip_dir)
	_clip_frames = 0
	_clip_next_t = 0.0
	clip_elapsed = 0.0
	last_clip_warning = ""
	if clip_mode == "ffmpeg":
		_ff_checked = false
		_pipe_sent = 0
		# 음성: Godot 마이크가 있으면 Godot 이 녹음 (영상과 같은 시계). 없으면 ffmpeg 가 dshow 로.
		var use_dshow := not can_record() and ffmpeg_audio_device != ""
		_job = _launch_job(note_id, _clip_dir, use_dshow)
		if _job == null:
			push_warning("StickyNotes: ffmpeg 실행 실패, 프레임 방식으로 전환")
			clip_mode = "frames"
		else:
			_clip_has_audio = false
			if not use_dshow:
				_clip_has_audio = start_recording()
				if not _clip_has_audio:
					last_clip_warning = "microphone could not be opened, recording without sound"
			_rec_vp.size = Vector2i(REC_W, REC_H)
			_follow_head()
			_rec_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if clip_mode == "frames":
		_clip_has_audio = start_recording()
		_rec_vp.size = Vector2i(FALLBACK_W, FALLBACK_H)
		_rec_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	is_clip_recording = true
	recording_state_changed.emit(true)
	return true


func _process(delta: float) -> void:
	# 끝난 작업 (변환 완료) 정리
	for i in range(_jobs.size() - 1, -1, -1):
		var job := _jobs[i]
		if job.thread != null and not job.thread.is_alive():
			job.thread.wait_to_finish()
			_jobs.remove_at(i)
			if not job.cancel:
				_finalize_ffmpeg_clip(job.id)
				clip_ready.emit(job.id)
	if not is_clip_recording:
		return
	clip_elapsed += delta
	if clip_mode == "ffmpeg" and _job != null:
		_pump_pipe()
		if clip_elapsed >= CLIP_MAX_SEC:
			stop_clip()
		return
	_follow_head()
	if clip_elapsed >= _clip_next_t:
		_clip_next_t += 1.0 / CLIP_FPS
		var img := _rec_vp.get_texture().get_image()
		if img != null:
			_clip_frames += 1
			img.save_jpg(_clip_dir + "f%04d.jpg" % _clip_frames, 0.85)
	if clip_elapsed >= CLIP_MAX_SEC:
		stop_clip()


## 매 프레임: 녹화 시계에 맞춰 뷰포트 이미지를 큐에 넣는다. 늦어진 만큼 같은 프레임을 반복해서
## 영상 길이가 실제 시간(= 마이크 음성)과 맞게 유지한다.
func _pump_pipe() -> void:
	# ffmpeg 가 1초 안에 죽었으면 대개 마이크를 못 연 것. 마이크 없이 다시 시작한다.
	if not _ff_checked and clip_elapsed > 1.0:
		_ff_checked = true
		if not OS.is_process_running(_job.pid):
			_job.keep_dir = true
			_job.finish(true)
			if _job.dshow:
				last_clip_warning = "ffmpeg could not open the microphone, recording without sound. See ffmpeg_record.log"
				print("habitat_notes: ", last_clip_warning)
				_job = _launch_job(_clip_id, _clip_dir, false)
				_pipe_sent = 0
				clip_elapsed = 0.0
				if _job != null:
					return
			last_clip_warning = "ffmpeg could not start. See ffmpeg_record.log in the clip folder"
			push_warning("StickyNotes: " + last_clip_warning)
			cancel_clip()
			return
	var target := int(clip_elapsed * REC_FPS)
	if _pipe_sent >= target:
		return
	var img := _rec_vp.get_texture().get_image()
	if img != null and not img.is_empty():
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var data := img.get_data()
		var count := mini(target - _pipe_sent, 4)
		for i in count:
			_job.push(data)
		_pipe_sent += count
	_follow_head()
	_rec_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## 녹화를 끝내고 {clip_file, audio_file, screenshot_file} 를 돌려준다. 실패하면 빈 Dictionary.
func stop_clip() -> Dictionary:
	if not is_clip_recording:
		return {}
	is_clip_recording = false
	_rec_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if clip_mode == "ffmpeg" and _job != null:
		return _stop_ffmpeg_clip()
	_rec_vp.size = Vector2i(REC_W, REC_H)
	var audio_rel := ""
	if _clip_has_audio:
		var rec := _finish_recording()
		if rec != null and rec.save_to_wav(_clip_dir + "voice.wav") == OK:
			audio_rel = "clip_%s/voice.wav" % _clip_id
			_audio_cache[audio_rel] = rec
	recording_state_changed.emit(false)
	if _clip_frames == 0:
		return {}
	_write_clip_meta(_clip_dir, {"fps": CLIP_FPS, "frames": _clip_frames, "duration": clip_elapsed, "audio": audio_rel != ""})
	# 첫 프레임을 썸네일로
	var shot := ""
	var first := Image.load_from_file(_clip_dir + "f0001.jpg")
	if first != null and first.save_png(MEDIA_DIR + "shot_%s.png" % _clip_id) == OK:
		shot = "shot_%s.png" % _clip_id
	return {
		"clip_file": "clip_%s/clip.json" % _clip_id,
		"audio_file": audio_rel,
		"screenshot_file": shot,
	}


func _stop_ffmpeg_clip() -> Dictionary:
	var job := _job
	_job = null
	if _clip_has_audio:
		var rec := _finish_recording()
		if rec != null and rec.save_to_wav(_clip_dir + "voice_godot.wav") == OK:
			job.godot_wav = ProjectSettings.globalize_path(_clip_dir + "voice_godot.wav")
			job.has_audio = true
		_clip_has_audio = false
	# 변환이 끝나기 전까지 frames = 0 (재생기는 "processing" 표시)
	_write_clip_meta(_clip_dir, {"mode": "ffmpeg", "fps": PLAY_FPS, "frames": 0, "duration": clip_elapsed,
		"audio": job.has_audio, "mp4": "clip_%s/clip.mp4" % _clip_id})
	if job.dropped > 0:
		print("habitat_notes: clip %s dropped %d frames (encoder could not keep up)" % [_clip_id, job.dropped])
	# 파이프를 닫으면 ffmpeg 가 파일을 마무리한다. 기다리기와 변환은 작업 스레드가 한다.
	job.finish(false)
	recording_state_changed.emit(false)
	return {
		"clip_file": "clip_%s/clip.json" % _clip_id,
		"audio_file": "",
		"screenshot_file": "",
	}


## ffmpeg 를 띄우고 프레임을 써 줄 스레드를 시작한다. 실패하면 null.
func _launch_job(note_id: String, dir: String, with_audio: bool) -> ClipJob:
	# dshow 음성이 있으면 바로 clip.mp4, 아니면 clip_video.mp4 (끝날 때 Godot 음성과 합쳐 clip.mp4 가 된다)
	var mp4 := ProjectSettings.globalize_path(dir + ("clip.mp4" if with_audio else "clip_video.mp4"))
	var args: PackedStringArray = ["-y", "-hide_banner", "-nostats", "-loglevel", "warning",
		"-f", "rawvideo", "-pix_fmt", "rgba", "-video_size", "%dx%d" % [REC_W, REC_H],
		"-framerate", str(int(REC_FPS)), "-i", "pipe:0"]
	if with_audio:
		args.append_array(["-f", "dshow", "-audio_buffer_size", "50", "-i", "audio=" + _dshow_audio_input()])
	args.append_array(["-map", "0:v"])
	if with_audio:
		args.append_array(["-map", "1:a"])
	args.append_array(["-c:v", "libx264", "-preset", "veryfast", "-crf", str(CLIP_CRF),
		"-g", str(int(REC_FPS)), "-pix_fmt", "yuv420p"])
	if with_audio:
		args.append_array(["-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "1", "-shortest"])
	args.append_array(["-movflags", "+frag_keyframe+empty_moov", "-t", str(int(CLIP_MAX_SEC) + 2), mp4])
	OS.set_environment("FFREPORT", "file=%s:level=24" % ProjectSettings.globalize_path(dir + "ffmpeg_record.log").replace("\\", "/").replace(":", "\\:"))
	var pipe := OS.execute_with_pipe(ffmpeg_path, args, false)
	OS.set_environment("FFREPORT", "")
	var pid := int(pipe.get("pid", -1))
	if pid <= 0 or pipe.get("stdio", null) == null:
		return null
	var job := ClipJob.new()
	job.id = note_id
	job.dir = dir
	job.pipe = pipe
	job.pid = pid
	job.has_audio = with_audio
	job.dshow = with_audio
	job.thread = Thread.new()
	job.thread.start(_clip_job_run.bind(job))
	_jobs.append(job)
	print("habitat_notes: ffmpeg record started pid %d, %dx%d @ %d fps, mic=%s" % [pid, REC_W, REC_H, int(REC_FPS), ("dshow " + ffmpeg_audio_device) if with_audio else (("godot " + mic_device) if can_record() else "(none)")])
	return job


## [작업 스레드] 큐의 프레임을 ffmpeg stdin 에 쓴다 → 끝나면 파이프를 닫고 ffmpeg 가 끝나길 기다린다
## → mp4 를 재생용 JPG 프레임과 voice.wav 로 변환하고 음성 크기를 잰다.
func _clip_job_run(job: ClipJob) -> void:
	var stdio: FileAccess = job.pipe.get("stdio", null)
	var last := PackedByteArray()
	while true:
		job.sem.wait()
		job.mutex.lock()
		var data := PackedByteArray()
		if not job.queue.is_empty():
			data = job.queue.pop_front()
		var done: bool = job.stop and job.queue.is_empty()
		var cancelled: bool = job.cancel
		job.mutex.unlock()
		if not data.is_empty() and stdio != null and not cancelled:
			stdio.store_buffer(data)
			last = data
		if done:
			break
	# 마이크 소리는 영상보다 0.3~0.5초 늦게 들어온다. -shortest 가 끝부분을 자르지 않도록
	# 마지막 프레임을 조금 더 보내 영상이 음성을 기다리게 한다.
	if job.dshow and not job.cancel and stdio != null and not last.is_empty():
		for i in int(REC_FPS * 0.75):
			stdio.store_buffer(last)
	if stdio != null:
		stdio.close()
	var waited := 0
	while waited < 15000 and OS.is_process_running(job.pid):
		OS.delay_msec(50)
		waited += 50
	if OS.is_process_running(job.pid):
		OS.kill(job.pid)
	var err: FileAccess = job.pipe.get("stderr", null)
	var stderr_text := ""
	if err != null:
		stderr_text = err.get_as_text()
		err.close()
	if job.cancel:
		if not job.keep_dir:
			_remove_dir(job.dir)
		return
	var g_mp4 := ProjectSettings.globalize_path(job.dir + "clip.mp4")
	var log := "ffmpeg stderr:\n%s\n" % stderr_text
	var out := []
	var code := 0
	if not job.dshow:
		var g_video := ProjectSettings.globalize_path(job.dir + "clip_video.mp4")
		if job.godot_wav != "" and FileAccess.file_exists(job.godot_wav):
			# 영상 + Godot 음성 → clip.mp4 (영상은 그대로 복사, 음성만 aac)
			code = OS.execute(ffmpeg_path, ["-y", "-hide_banner", "-loglevel", "error", "-i", g_video, "-i", job.godot_wav,
				"-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-ac", "1",
				"-movflags", "+faststart", g_mp4], out, true)
			log += "mux exit %d\n%s\n" % [code, "\n".join(out)]
			if code == 0 and FileAccess.file_exists(g_mp4):
				DirAccess.remove_absolute(g_video)
				DirAccess.remove_absolute(job.godot_wav)
			else:
				job.has_audio = false
				DirAccess.rename_absolute(g_video, g_mp4)
		else:
			job.has_audio = false
			DirAccess.rename_absolute(g_video, g_mp4)
	out = []
	code = OS.execute(ffmpeg_path, ["-y", "-hide_banner", "-loglevel", "error", "-i", g_mp4,
		"-vf", "fps=%d,scale=%d:-2" % [int(PLAY_FPS), PLAY_W], "-q:v", "3",
		ProjectSettings.globalize_path(job.dir + "f%04d.jpg")], out, true)
	log += "frames exit %d\n%s\n" % [code, "\n".join(out)]
	var audio_max_db := -200.0
	if job.has_audio:
		out = []
		code = OS.execute(ffmpeg_path, ["-y", "-hide_banner", "-loglevel", "error", "-i", g_mp4,
			"-vn", "-ac", "1", "-ar", "22050", ProjectSettings.globalize_path(job.dir + "voice.wav")], out, true)
		log += "audio exit %d\n%s\n" % [code, "\n".join(out)]
		out = []
		OS.execute(ffmpeg_path, ["-hide_banner", "-i", ProjectSettings.globalize_path(job.dir + "voice.wav"),
			"-af", "volumedetect", "-f", "null", "-"], out, true)
		for line in "\n".join(out).split("\n"):
			if line.contains("max_volume:"):
				audio_max_db = float(line.get_slice("max_volume:", 1).strip_edges().trim_suffix("dB").strip_edges())
		log += "audio max volume %.1f dB\n" % audio_max_db
	var f := FileAccess.open(job.dir + "ffmpeg_convert.log", FileAccess.WRITE)
	if f != null:
		f.store_string(log)
		f.close()
	var r := FileAccess.open(job.dir + "convert.json", FileAccess.WRITE)
	if r != null:
		r.store_string(JSON.stringify({"audio_max_db": audio_max_db, "dropped": job.dropped}))
		r.close()


func _write_clip_meta(dir: String, meta: Dictionary) -> void:
	var f := FileAccess.open(dir + "clip.json", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(meta))
	f.close()


## [메인 스레드] 변환이 끝났을 때: 프레임 수를 세서 meta 를 완성하고 썸네일을 만든다.
func _finalize_ffmpeg_clip(note_id: String) -> void:
	var dir := MEDIA_DIR + "clip_%s/" % note_id
	var count := 0
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("f") and f.ends_with(".jpg"):
			count += 1
	var meta := load_clip("clip_%s/clip.json" % note_id)
	if meta.is_empty():
		meta = {"mode": "ffmpeg", "fps": PLAY_FPS, "duration": 0.0}
	meta.erase("dir")
	meta.erase("audio_file")
	meta.erase("mp4_path")
	meta["frames"] = count
	meta["audio"] = FileAccess.file_exists(dir + "voice.wav")
	var result: Dictionary = {}
	if FileAccess.file_exists(dir + "convert.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "convert.json"))
		if parsed is Dictionary:
			result = parsed
	var max_db := float(result.get("audio_max_db", -200.0))
	meta["audio_max_db"] = max_db
	meta["audio_silent"] = bool(meta["audio"]) and max_db < SILENT_DB
	if count == 0:
		push_warning("habitat_notes: clip %s has no frames. See %s" % [note_id, ProjectSettings.globalize_path(dir + "ffmpeg_convert.log")])
		meta["failed"] = true
	else:
		print("habitat_notes: clip %s ready, %d frames, audio=%s (max %.1f dB)" % [note_id, count, str(meta["audio"]), max_db])
	if bool(meta["audio_silent"]):
		last_clip_warning = "the microphone was silent. Check the Quest Link mic and the device in the Session tab"
		push_warning("habitat_notes: clip %s: %s" % [note_id, last_clip_warning])
	if count > 0 and float(meta.get("duration", 0.0)) <= 0.0:
		meta["duration"] = count / PLAY_FPS
	_write_clip_meta(dir, meta)
	var n: NoteData = notes.get(note_id, null)
	if n != null:
		if count > 0:
			var first := Image.load_from_file(dir + "f0001.jpg")
			if first != null and first.save_png(MEDIA_DIR + "shot_%s.png" % note_id) == OK:
				n.screenshot_file = "shot_%s.png" % note_id
		if bool(meta["audio"]):
			n.audio_file = "clip_%s/voice.wav" % note_id
		update_note(n)


func cancel_clip() -> void:
	if not is_clip_recording:
		return
	is_clip_recording = false
	_rec_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_rec_vp.size = Vector2i(REC_W, REC_H)
	cancel_recording()
	if _job != null:
		_job.finish(true)      # 스레드가 ffmpeg 종료를 기다린 뒤 클립 폴더를 지운다
		_job = null
	else:
		_remove_dir(_clip_dir)
	recording_state_changed.emit(false)


func is_clip_converting(note_id: String) -> bool:
	for job in _jobs:
		if job.id == note_id and not job.cancel:
			return true
	return false


## 클립 메타와 프레임 경로 목록. {fps, frames, duration, dir, audio_file}
func load_clip(clip_file: String) -> Dictionary:
	if clip_file == "":
		return {}
	var path := MEDIA_DIR + clip_file
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var meta: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (meta is Dictionary):
		return {}
	var dir := clip_file.get_base_dir() + "/"
	meta["dir"] = MEDIA_DIR + dir
	meta["audio_file"] = (dir + "voice.wav") if bool(meta.get("audio", false)) else ""
	if str(meta.get("mode", "frames")) == "ffmpeg":
		meta["mp4_path"] = MEDIA_DIR + str(meta.get("mp4", ""))
	return meta


func clip_frame_path(meta: Dictionary, index: int) -> String:
	return "%sf%04d.jpg" % [meta["dir"], clampi(index, 1, int(meta["frames"]))]


## 종료할 때 녹화 중이면 취소하고 스레드를 정리한다.
func _exit_tree() -> void:
	if is_clip_recording:
		cancel_clip()
	for job in _jobs:
		if job.thread != null:
			job.finish(true)
			job.thread.wait_to_finish()
	_jobs.clear()


# =====================================================================
#  마이크
# =====================================================================

var mic_device: String = ""
var mic_status: String = "no microphone"


func set_mic_device(name_: String) -> void:
	AudioServer.input_device = name_
	mic_device = name_
	mic_status = "mic: " + name_
	_save_identity()


## 캡처 스트림을 다시 연다. Quest Link 가 끊겼다 다시 붙으면 Windows 장치가 새로 만들어져서
## 실행 중인 Godot 이 옛 스트림을 붙든 채 무음이 될 수 있다. 장치를 잠깐 Default 로 돌렸다가 되돌린다.
func reconnect_mic() -> void:
	var wanted := mic_device
	if wanted == "":
		wanted = AudioServer.input_device
	AudioServer.input_device = "Default" if wanted != "Default" else AudioServer.get_input_device_list()[-1]
	await get_tree().create_timer(0.4).timeout
	AudioServer.input_device = wanted
	mic_device = wanted
	mic_status = "mic: " + wanted
	if _mic_player != null and not _mic_player.playing:
		_mic_player.play()
	print("habitat_notes: microphone reconnected: ", wanted, " (devices ", AudioServer.get_input_device_list(), ")")


func mic_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func _setup_microphone() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		mic_status = "audio input disabled in Project Settings"
		push_warning("StickyNotes: Project Settings > Audio > Driver > Enable Input 이 꺼져 있어 녹음이 안 됩니다.")
		return
	# Quest Link 헤드셋 마이크가 있으면 그걸 고른다
	var devices := AudioServer.get_input_device_list()
	print("habitat_notes: input devices = ", devices)
	var chosen := _pick_device(Array(devices), mic_device)
	if chosen != "":
		AudioServer.input_device = chosen
	mic_device = AudioServer.input_device
	mic_status = "mic: " + mic_device

	# Record 버스 (녹음 이펙트, 레벨 측정) → MicSink 버스 (음소거) 로 흘려서 내 목소리가 안 들리게
	var sink_idx := AudioServer.get_bus_index("MicSink")
	if sink_idx == -1:
		sink_idx = AudioServer.bus_count
		AudioServer.add_bus(sink_idx)
		AudioServer.set_bus_name(sink_idx, "MicSink")
		AudioServer.set_bus_mute(sink_idx, true)
	var bus_idx := AudioServer.get_bus_index(RECORD_BUS)
	if bus_idx == -1:
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, RECORD_BUS)
		AudioServer.add_bus_effect(bus_idx, AudioEffectRecord.new())
	AudioServer.set_bus_mute(bus_idx, false)
	AudioServer.set_bus_send(bus_idx, "MicSink")
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var fx := AudioServer.get_bus_effect(bus_idx, i)
		if fx is AudioEffectRecord:
			_record_effect = fx
			break
	if _record_effect == null:
		mic_status = "Record bus has no Record effect"
		return
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "MicPlayer"
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = RECORD_BUS
	add_child(_mic_player)
	# 레벨 바를 위해 마이크는 항상 열어 둔다
	_mic_player.play()


func can_record() -> bool:
	return _record_effect != null and _mic_player != null


## 마이크 피크 (dB). 신호가 없으면 -200. 마이크 진단 표시에 쓴다.
func mic_peak_db() -> float:
	if not can_record():
		return -200.0
	var idx := AudioServer.get_bus_index(RECORD_BUS)
	if idx == -1:
		return -200.0
	return AudioServer.get_bus_peak_volume_left_db(idx, 0)


## 마이크 상태 한 줄. "-23 dB" / "silent" 등. 패널의 레벨 바 옆에 보여 준다.
func mic_check_text() -> String:
	if not can_record():
		return mic_status
	var db := mic_peak_db()
	if db < -70.0:
		return "silent"
	if db < -45.0:
		return "%.0f dB  ·  very quiet" % db
	return "%.0f dB  ·  OK" % db


## 0~1. 마이크로 들어오는 소리 크기. 레벨 바에 쓴다.
func mic_level() -> float:
	if not can_record():
		return 0.0
	var idx := AudioServer.get_bus_index(RECORD_BUS)
	if idx == -1:
		return 0.0
	var db := AudioServer.get_bus_peak_volume_left_db(idx, 0)
	return clampf((db + 50.0) / 50.0, 0.0, 1.0)


func start_recording() -> bool:
	if not can_record() or is_recording:
		return false
	if not _mic_player.playing:
		_mic_player.play()
	_record_effect.set_recording_active(true)
	is_recording = true
	return true


func _finish_recording() -> AudioStreamWAV:
	if not is_recording:
		return null
	_record_effect.set_recording_active(false)
	is_recording = false
	return _record_effect.get_recording()


## 음성만 wav로 저장 (데스크톱 호환). 파일 이름을 돌려준다.
func stop_recording(note_id: String) -> String:
	var rec := _finish_recording()
	recording_state_changed.emit(false)
	if rec == null:
		return ""
	var file := "voice_%s.wav" % note_id
	if rec.save_to_wav(MEDIA_DIR + file) != OK:
		return ""
	_audio_cache[file] = rec
	return file


func cancel_recording() -> void:
	if not is_recording:
		return
	_record_effect.set_recording_active(false)
	is_recording = false
	recording_state_changed.emit(false)


func load_audio(file: String) -> AudioStream:
	if file == "":
		return null
	if _audio_cache.has(file):
		return _audio_cache[file]
	var path := MEDIA_DIR + file
	if not FileAccess.file_exists(path):
		return null
	var stream := AudioStreamWAV.load_from_file(path)
	if stream != null:
		_audio_cache[file] = stream
	return stream


# =====================================================================
#  세션 저장 / 불러오기 / 리포트  (= 전송 기능)
# =====================================================================

func _safe_name(session_name: String, prefix: String) -> String:
	var safe := session_name.strip_edges().validate_filename()
	if safe == "":
		safe = prefix + Time.get_datetime_string_from_system(false, false).replace(":", "-")
	return safe


func save_session(session_name: String) -> String:
	var list: Array = []
	for n in notes.values():
		list.append(n.to_dict())
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["created_at"] < b["created_at"])
	var data := {
		"format": "sticky_notes",
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"notes": list,
	}
	var path := SESSION_DIR + _safe_name(session_name, "session_") + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("StickyNotes: 세션 저장 실패 %s" % path)
		return ""
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return path


## replace=true면 현재 노트를 다 지우고 불러온다. false면 겹쳐 올린다.
func load_session(path: String, replace: bool = true) -> int:
	if not FileAccess.file_exists(path):
		push_warning("StickyNotes: 세션 파일이 없습니다 %s" % path)
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not parsed.has("notes"):
		push_warning("StickyNotes: 세션 파일 형식이 다릅니다 %s" % path)
		return 0
	if replace:
		clear_all()
	var loaded: Array[NoteData] = []
	for d in parsed["notes"]:
		if d is Dictionary:
			loaded.append(NoteData.from_dict(d))
	loaded.sort_custom(_sort_parents_first)
	for n in loaded:
		notes[n.id] = n
		if not n.is_reply():
			_spawn_instance(n)
	_after_change()
	notes_reloaded.emit()
	return loaded.size()


## 원 노트를 먼저, 답글을 나중에. 각각 오래된 순.
static func _sort_parents_first(a: NoteData, b: NoteData) -> bool:
	if a.is_reply() != b.is_reply():
		return not a.is_reply()
	return a.created_at < b.created_at


func list_sessions() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(SESSION_DIR):
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out


func session_path(file_name: String) -> String:
	return SESSION_DIR + file_name


## 현재 노트 전체를 HTML 한 장으로 내보낸다. 이미지·음성은 파일 안에 포함된다.
func export_report(title: String) -> String:
	var safe := _safe_name(title, "review_")
	var html := NoteReport.build(title if title.strip_edges() != "" else safe)
	var path := REPORT_DIR + safe + ".html"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("StickyNotes: 리포트 저장 실패 %s" % path)
		return ""
	f.store_string(html)
	f.close()
	return path


## 세션 json + media + reports 폴더가 있는 곳을 OS 파일 탐색기로 연다.
func open_data_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(ROOT_DIR))


# =====================================================================
#  내부
# =====================================================================

func _delete_media(note: NoteData) -> void:
	for file in [note.screenshot_file, note.audio_file]:
		if file != "" and FileAccess.file_exists(MEDIA_DIR + file):
			DirAccess.remove_absolute(MEDIA_DIR + file)
		_audio_cache.erase(file)
	if note.clip_file != "":
		_remove_dir(MEDIA_DIR + note.clip_file.get_base_dir())


func _remove_dir(path: String) -> void:
	if path == "" or not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


## 다른 프로젝트에 합쳤는데 Input Map에 액션이 없으면 기본 키를 런타임에 등록한다.
func _ensure_input_actions() -> void:
	var defaults := {
		"note_place": KEY_N,
		"note_interact": KEY_E,
		"note_list": KEY_TAB,
		"note_tour_next": KEY_BRACKETRIGHT,
		"note_tour_prev": KEY_BRACKETLEFT,
		"note_type_1": KEY_1,
		"note_type_2": KEY_2,
		"note_type_3": KEY_3,
		"note_type_4": KEY_4,
		"note_type_5": KEY_5,
	}
	for action in defaults:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = defaults[action]
		InputMap.action_add_event(action, ev)
