## Holonote recorder: records moving head / hand nodes through the normal clip entry points,
## writes holo.json, and reads it back with the same poses.
##   Godot --headless --path . res://tests/holo_smoke.tscn --quit-after 100000   (headless runs uncapped, so the frame cap must be high)
extends Node

var _fails := 0


func _check(cond: bool, what: String) -> void:
	print(("TEST|PASS  " if cond else "TEST|FAIL  ") + what)
	if not cond:
		_fails += 1


func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var head := Node3D.new()
	var right := Node3D.new()
	var left := Node3D.new()
	add_child(head)
	add_child(right)
	add_child(left)
	left.visible = false                       # untracked hand
	head.global_position = Vector3(0.0, 1.6, 0.0)
	right.global_position = Vector3(0.3, 1.0, -0.3)
	NoteManager.register_holo_sources(head, left, right)
	for i in 5:
		await get_tree().process_frame           # skip the long first frame after startup
	var saved_mode := NoteManager.record_mode
	NoteManager.record_mode = "holo"

	_check(NoteManager.start_clip("smoke_holo"), "start_clip starts a holonote in holo mode")
	_check(NoteManager.is_clip_recording, "is_clip_recording is true while recording")
	# Walk 1 m along +x over ~1 s while the right hand rises.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		var k := (Time.get_ticks_msec() - t0) / 1000.0
		head.global_position = Vector3(k, 1.6, 0.0)
		right.global_position = Vector3(k + 0.3, 1.0 + k * 0.5, -0.3)
		right.rotation.y = k
		await get_tree().process_frame
	var end_head := head.global_position
	var end_right := right.global_transform
	await get_tree().process_frame
	var res := NoteManager.stop_clip()
	_check(not NoteManager.is_clip_recording, "stop_clip ends the recording")
	_check(res.get("holo_file", "") == "holo_smoke_holo/holo.json", "stop_clip returns holo_file (%s)" % res.get("holo_file", "-"))
	_check(res.get("clip_file", "x") == "", "stop_clip returns an empty clip_file for holonotes")

	var m := NoteManager.load_holo(str(res.get("holo_file", "")))
	_check(m != null, "holo.json loads back")
	if m != null:
		_check(m.frame_count >= 25 and m.frame_count <= 40, "about 30 frames for 1 s (%d)" % m.frame_count)
		_check(absf(m.duration - (m.frame_count - 1) / m.hz) < 0.001, "duration matches frame count (%.2fs)" % m.duration)
		_check(m.pose_at("head", 0.0).origin.distance_to(Vector3(0, 1.6, 0)) < 0.05, "head starts at the start position")
		_check(m.pose_at("head", m.duration).origin.distance_to(end_head) < 0.06, "head ends at the end position")
		var r := m.pose_at("right", m.duration)
		_check(r.origin.distance_to(end_right.origin) < 0.06, "right hand position round-trips")
		_check(absf(r.basis.get_euler().y - end_right.basis.get_euler().y) < 0.06, "right hand rotation round-trips")
		var mid := m.pose_at("head", m.duration * 0.5).origin.x
		_check(mid > 0.35 and mid < 0.65, "interpolated midpoint is halfway (%.2f)" % mid)
		_check(m.has_track("right") and not m.has_track("left"), "untracked left hand is marked invalid")
		_check(not m.valid_at("left", 0.5) and m.valid_at("right", 0.5), "valid_at reflects tracking")

	# Ghost playback follows the recorded head.
	var pn := NoteData.make_new()
	pn.holo_file = str(res.get("holo_file", ""))
	pn.author = "Smoke"
	var events: Array = []
	NoteManager.holo_playback_changed.connect(func(id: String, on: bool) -> void: events.append(on))
	_check(NoteManager.play_holo(pn, false), "play_holo starts the ghost")
	_check(NoteManager.is_holo_playing(pn.id), "is_holo_playing reports the note")
	var ghost: HoloPlayer = NoteManager._holo_player
	var spot := ghost.viewer_spot(m)
	_check(spot.size() == 2 and (spot[0] as Vector3).distance_to(Vector3(0, 1.6, 0)) > 1.0, "viewer spot stands back from the author (%s)" % str(spot[0] if spot.size() else "-"))
	await get_tree().create_timer(0.5).timeout
	var gx := ghost._head.global_position.x
	var want := m.pose_at("head", ghost.t).origin.x
	_check(ghost.t > 0.3 and absf(gx - want) < 0.01 and gx > 0.15, "ghost head follows the recording (t=%.2f x=%.2f want %.2f)" % [ghost.t, gx, want])
	_check(ghost._hands["right"].visible and not ghost._hands["left"].visible, "ghost shows only the tracked hand")
	await get_tree().create_timer(m.duration + 1.5).timeout
	_check(not NoteManager.is_holo_playing(), "ghost finishes on its own")
	_check(events == [true, false], "holo_playback_changed fires start and finish (%s)" % str(events))

	# Scripts that use holonotes compile, and the 2D player offers the holonote.
	for path in ["res://addons/sticky_notes/xr/clip_theater.gd", "res://addons/sticky_notes/ui/clip_player.gd",
			"res://scripts/xr_notes.gd", "res://addons/sticky_notes/ui/vr_panel.gd", "res://addons/sticky_notes/ui/note_panel.gd"]:
		var sc: Script = load(path)
		_check(sc != null and sc.can_instantiate(), "compiles: " + path.get_file())
	var cp: Control = load("res://addons/sticky_notes/ui/clip_player.gd").new(180.0)
	add_child(cp)
	_check(cp.load_note(pn) and cp._btn.visible and cp._btn.text.contains("holonote"), "ClipPlayer shows ▶ Play holonote")
	cp._toggle()
	_check(NoteManager.is_holo_playing(pn.id) and cp._btn.text.contains("Stop"), "ClipPlayer starts the ghost and shows Stop")
	cp._toggle()
	_check(not NoteManager.is_holo_playing(), "ClipPlayer stops the ghost")
	cp.queue_free()

	# apply_recording replaces an old video clip and keeps the screenshot when there is none.
	var an := NoteData.make_new()
	an.clip_file = "clip_x/clip.json"
	an.screenshot_file = "shot_x.png"
	NoteManager.apply_recording(an, {"holo_file": "holo_x/holo.json", "audio_file": "", "screenshot_file": "", "clip_file": ""})
	_check(an.holo_file == "holo_x/holo.json" and an.clip_file == "" and an.screenshot_file == "shot_x.png", "apply_recording swaps a clip for a holonote")
	_check(NoteManager.record_noun() == "holonote", "record buttons say holonote in holo mode")

	# Note data keeps the field through a save round-trip.
	var n := NoteData.make_new()
	n.holo_file = str(res.get("holo_file", ""))
	var back := NoteData.from_dict(JSON.parse_string(JSON.stringify(n.to_dict())))
	_check(back.holo_file == n.holo_file and back.has_holo() and back.has_media(), "NoteData serialises holo_file")
	_check(not NoteData.from_dict({"id": "old"}).has_holo(), "old notes without holo_file still load")

	# Deleting the note removes the holo folder.
	NoteManager._delete_media(n)
	_check(not DirAccess.dir_exists_absolute(NoteManager.MEDIA_DIR + "holo_smoke_holo"), "deleting the note removes its holo folder")

	# Cancel leaves nothing behind.
	NoteManager.start_clip("smoke_cancel")
	await get_tree().process_frame
	NoteManager.cancel_clip()
	_check(not NoteManager.is_clip_recording and not DirAccess.dir_exists_absolute(NoteManager.MEDIA_DIR + "holo_smoke_cancel"), "cancel_clip discards a holonote")

	NoteManager.record_mode = saved_mode
	await get_tree().process_frame
	for f in ["shot_holo_smoke_holo.png", "shot_holo_smoke_cancel.png"]:
		if FileAccess.file_exists(NoteManager.MEDIA_DIR + f):
			DirAccess.remove_absolute(NoteManager.MEDIA_DIR + f)
	print("TEST|DONE  failures=%d" % _fails)
	get_tree().quit(_fails)
