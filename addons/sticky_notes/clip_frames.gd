class_name ClipFrames
extends RefCounted
## 클립 프레임을 필요할 때만 디코드해서 주는 도우미.
## 프레임 수백 장을 다 텍스처로 올리면 VRAM 을 수백 MB 먹으므로, 현재 프레임 하나만 들고 있는다.
## 1280px JPG 디코드는 몇 ms 걸리므로 다음 프레임은 WorkerThreadPool 에서 미리 디코드해 둔다 (VR 프레임이 안 끊기게).
## 작업이 self 를 붙들고 있으므로 작업이 끝나기 전에는 이 객체가 지워지지 않는다.

var meta: Dictionary = {}
var fps: float = 8.0
var frame_count: int = 0
var duration: float = 0.0
var audio_file: String = ""
var ready: bool = false            # 프레임이 1장 이상 있고 변환이 끝났는가
var failed: bool = false
var audio_silent: bool = false     # 녹음은 됐지만 마이크가 조용했다 (ffmpeg 변환 때 측정)

var _tex: ImageTexture = null
var _tex_index: int = -1
var _prefetch_task: int = -1          # WorkerThreadPool 작업 id. -1 이면 없음
var _prefetch_index: int = -1
var _prefetch_img: Image = null


func load(note: NoteData) -> bool:
	_join_prefetch()
	meta = NoteManager.load_clip(note.clip_file) if note.has_clip() else {}
	if meta.is_empty():
		ready = false
		return false
	fps = float(meta.get("fps", 8.0))
	frame_count = int(meta.get("frames", 0))
	duration = float(meta.get("duration", 0.0))
	audio_file = str(meta.get("audio_file", ""))
	failed = bool(meta.get("failed", false))
	audio_silent = bool(meta.get("audio_silent", false))
	ready = frame_count > 0 and not NoteManager.is_clip_converting(note.id)
	_tex = null
	_tex_index = -1
	return true


func index_at(t: float) -> int:
	if frame_count <= 0:
		return 1
	return clampi(int(t * fps) + 1, 1, frame_count)


## t초의 프레임 텍스처. 같은 프레임이면 디코드하지 않는다.
func texture_at(t: float) -> Texture2D:
	return texture_index(index_at(t))


func texture_index(i: int) -> Texture2D:
	if frame_count <= 0:
		return null
	i = clampi(i, 1, frame_count)
	if i == _tex_index and _tex != null:
		return _tex
	var img: Image = null
	if _prefetch_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_prefetch_task)
		_prefetch_task = -1
		if _prefetch_index == i:
			img = _prefetch_img
		_prefetch_img = null
	if img == null:
		img = Image.load_from_file(NoteManager.clip_frame_path(meta, i))
	if img == null:
		return _tex
	if _tex == null or _tex.get_size() != Vector2(img.get_size()):
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.update(img)
	_tex_index = i
	# 다음 프레임은 미리
	if i < frame_count:
		_prefetch_index = i + 1
		_prefetch_task = WorkerThreadPool.add_task(_decode.bind(NoteManager.clip_frame_path(meta, i + 1)))
	return _tex


func _decode(path: String) -> void:
	_prefetch_img = Image.load_from_file(path)


func _join_prefetch() -> void:
	if _prefetch_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_prefetch_task)
		_prefetch_task = -1
	_prefetch_img = null
	_prefetch_index = -1
