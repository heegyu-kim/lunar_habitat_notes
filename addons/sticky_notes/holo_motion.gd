class_name HoloMotion
extends RefCounted
## Holonote motion: the author's head and both hands, sampled at a fixed rate while they talk.
## Played back as a ghost in world space (HoloPlayer), in sync with the voice wav.
##
## Saved as media/holo_<id>/holo.json next to voice.wav:
##   { "format": "holonote", "version": 1, "hz": 30, "frames": N, "duration": s, "audio": bool,
##     "tracks": { "head": [px,py,pz, qx,qy,qz,qw, ...], "left": [...], "right": [...] },
##     "valid":  { "head": "111...", "left": "1100...", "right": "..." } }
## A hand that lost tracking keeps its last pose and is marked 0 in "valid" (hidden on playback).

const FORMAT := "holonote"
const VERSION := 1
const HZ := 30.0
const TRACKS: Array[String] = ["head", "left", "right"]
const STRIDE := 7                  # position xyz + quaternion xyzw

var hz: float = HZ
var frame_count: int = 0
var duration: float = 0.0
var has_audio: bool = false
var audio_file: String = ""        # media-relative, filled by NoteManager.load_holo

var _pose: Dictionary = {}         # track -> PackedFloat32Array (STRIDE floats per frame)
var _valid: Dictionary = {}        # track -> PackedByteArray (1 per frame)


func _init() -> void:
	for t in TRACKS:
		_pose[t] = PackedFloat32Array()
		_valid[t] = PackedByteArray()


## poses: track -> Transform3D (tracked) or null (not tracked this frame).
func add_frame(poses: Dictionary) -> void:
	for t in TRACKS:
		var arr: PackedFloat32Array = _pose[t]
		var ok: PackedByteArray = _valid[t]
		var xf: Variant = poses.get(t)
		if xf is Transform3D:
			var q: Quaternion = (xf as Transform3D).basis.orthonormalized().get_rotation_quaternion()
			var o: Vector3 = (xf as Transform3D).origin
			arr.append_array(PackedFloat32Array([o.x, o.y, o.z, q.x, q.y, q.z, q.w]))
			ok.append(1)
		elif frame_count > 0:
			arr.append_array(arr.slice((frame_count - 1) * STRIDE, frame_count * STRIDE))
			ok.append(0)
		else:
			arr.append_array(PackedFloat32Array([0, 0, 0, 0, 0, 0, 1]))
			ok.append(0)
		# Packed arrays are copied on write: store them back.
		_pose[t] = arr
		_valid[t] = ok
	frame_count += 1
	duration = float(frame_count - 1) / hz


## Interpolated pose of a track at time t (seconds). Identity if there are no frames.
func pose_at(track: String, t: float) -> Transform3D:
	if frame_count == 0 or not _pose.has(track):
		return Transform3D.IDENTITY
	var f := clampf(t * hz, 0.0, float(frame_count - 1))
	var i := int(floor(f))
	var j := mini(i + 1, frame_count - 1)
	var w := f - float(i)
	var arr: PackedFloat32Array = _pose[track]
	var a := i * STRIDE
	var b := j * STRIDE
	var pa := Vector3(arr[a], arr[a + 1], arr[a + 2])
	var pb := Vector3(arr[b], arr[b + 1], arr[b + 2])
	var qa := Quaternion(arr[a + 3], arr[a + 4], arr[a + 5], arr[a + 6]).normalized()
	var qb := Quaternion(arr[b + 3], arr[b + 4], arr[b + 5], arr[b + 6]).normalized()
	return Transform3D(Basis(qa.slerp(qb, w)), pa.lerp(pb, w))


## Was this track tracked at time t (nearest frame)?
func valid_at(track: String, t: float) -> bool:
	if frame_count == 0 or not _valid.has(track):
		return false
	var i := clampi(int(round(t * hz)), 0, frame_count - 1)
	return (_valid[track] as PackedByteArray)[i] == 1


## True if the track was tracked for at least one frame (e.g. a desktop recording has no left hand).
func has_track(track: String) -> bool:
	if not _valid.has(track):
		return false
	return (_valid[track] as PackedByteArray).has(1)


func to_dict() -> Dictionary:
	var tracks := {}
	var valid := {}
	for t in TRACKS:
		var arr: PackedFloat32Array = _pose[t]
		var out: Array = []
		out.resize(arr.size())
		for k in arr.size():
			# 1 mm for positions, 1e-4 for quaternions keeps the file small.
			out[k] = snappedf(arr[k], 0.001 if (k % STRIDE) < 3 else 0.0001)
		tracks[t] = out
		var bits := ""
		for v in (_valid[t] as PackedByteArray):
			bits += "1" if v == 1 else "0"
		valid[t] = bits
	return {
		"format": FORMAT,
		"version": VERSION,
		"hz": hz,
		"frames": frame_count,
		"duration": duration,
		"audio": has_audio,
		"tracks": tracks,
		"valid": valid,
	}


static func from_dict(d: Dictionary) -> HoloMotion:
	if str(d.get("format", "")) != FORMAT:
		return null
	var m := HoloMotion.new()
	m.hz = maxf(float(d.get("hz", HZ)), 1.0)
	m.has_audio = bool(d.get("audio", false))
	var n := int(d.get("frames", 0))
	var tracks: Dictionary = d.get("tracks", {})
	var valid: Dictionary = d.get("valid", {})
	for t in TRACKS:
		var src: Array = tracks.get(t, [])
		var bits := str(valid.get(t, ""))
		if src.size() != n * STRIDE or bits.length() != n:
			push_warning("HoloMotion: track '%s' has the wrong length, ignored" % t)
			src = []
			bits = ""
		var arr := PackedFloat32Array()
		arr.resize(n * STRIDE)
		var ok := PackedByteArray()
		ok.resize(n)
		for k in src.size():
			arr[k] = float(src[k])
		if src.is_empty():
			for f in n:
				arr[f * STRIDE + 6] = 1.0      # identity quaternion
		for f in bits.length():
			ok[f] = 1 if bits[f] == "1" else 0
		m._pose[t] = arr
		m._valid[t] = ok
	m.frame_count = n
	m.duration = float(maxi(n - 1, 0)) / m.hz
	return m
