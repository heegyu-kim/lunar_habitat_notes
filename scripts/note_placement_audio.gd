extends AudioStreamPlayer3D
## Confirm a new physical note at its location in either desktop or VR mode.
## Edits, replies, and session loads should not replay the placement sound.

func _ready() -> void:
	const PATH := "res://assets/audio/sticky_note_placed.wav"
	if ResourceLoader.exists(PATH):
		stream = load(PATH) as AudioStreamWAV
		if stream:
			NoteManager.note_added.connect(_on_note_added)


func _on_note_added(note: NoteData) -> void:
	if note.is_reply():
		return
	global_position = note.position + note.normal * 0.025
	play()
