## Plays the opening sting once when the app starts (desktop and VR). Optional: silent when the
## file is missing. assets/audio/opening.wav is produced by tools/prepare_habitat_audio.py.
extends AudioStreamPlayer

const PATH := "res://assets/audio/opening.wav"


func _ready() -> void:
	if not ResourceLoader.exists(PATH):
		return
	stream = load(PATH)
	if stream == null:
		return
	# A beat after the scene is up, so it is not cut by the first-frame hitch.
	await get_tree().create_timer(0.6).timeout
	play()
