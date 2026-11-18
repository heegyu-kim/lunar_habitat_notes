## Wrist board at 2x render scale: a ray "click" at a button's layout position still presses it.
##   Godot --headless --path . res://tests/board_click.tscn --quit-after 100000
extends Node


func _ready() -> void:
	var board := WristBoard.new()
	add_child(board)
	for i in 5:
		await get_tree().process_frame
	board.identity.visible = false
	var target: Button = null
	for b in board.panel.find_children("*", "Button", true, false):
		if (b as Button).text == "List" and (b as Button).is_visible_in_tree():
			target = b
	var fired := [false]
	if target != null:
		target.pressed.connect(func() -> void: fired[0] = true)
		var px := target.get_global_rect().get_center()
		board.pointer_move(px)
		board.pointer_button(px, true)
		await get_tree().process_frame
		board.pointer_button(px, false)
		await get_tree().process_frame
	var ok: bool = target != null and bool(fired[0])
	print(("TEST|PASS  " if ok else "TEST|FAIL  ") + "board click lands on the List button at 2x (%s)" % (str(target.get_global_rect()) if target else "no button"))
	print("TEST|INFO  viewport size %s, layout %s" % [board.viewport.size, board.viewport.size_2d_override])
	get_tree().quit(0 if ok else 1)
