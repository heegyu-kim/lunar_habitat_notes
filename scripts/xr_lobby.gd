extends Node3D
## VR main lobby: the title and a START button, shown before the habitat.
##
## main.gd adds this under the XROrigin3D once OpenXR runs and calls open(). While the lobby is open
## walking, the ladder, the map and the sticky notes are switched off; START puts the player back
## where the habitat begins.
##
## style "screen" (default): a 16:9 picture on a very large flat screen in front of you, about 100
## degrees wide, with nothing but black around it (the player is parked far above the habitat).
## The picture is res://assets/lobby/lobby_background.png (or .jpg / .jpeg / .webp), 3840 x 2160;
## without one a plain placeholder is shown. See assets/lobby/README.txt.
##
## style "surface": you stand on the real lunar ground outside the habitat, SURFACE_DISTANCE metres
## from it, facing the Earth, with the title as 3D lettering in the landscape. No picture is used.
##
## Point either controller at the button and pull its trigger.

signal started
signal exiting

## The lettering in the landscape (style "surface").
const TITLE := "AstroNote"
## Where you stand: this far from the habitat's centre, on the side away from the Earth, swung
## SURFACE_TURN degrees around the habitat so that it is beside the view and not in front of the Earth.
const SURFACE_DISTANCE := 45.0
const SURFACE_TURN := -40.0
## The title: how far ahead it stands, how tall its capital letters are (metres), and how far above
## eye level its middle is (degrees).
const TITLE_DISTANCE := 90.0
const TITLE_HEIGHT := 9.0
const TITLE_ELEVATION := 13.0
## START in the landscape: metres below eye level, on the same invisible plane SCREEN_DISTANCE ahead.
const SURFACE_BUTTON_DROP := 0.55

const BACKGROUND_TYPES := ["png", "jpg", "jpeg", "webp"]
## The layout of the screen: its width and height in layout metres (600 px of a 3840 x 2160 picture
## each), which BUTTONS and BUTTON_SIZE are given in.
const SCREEN_SIZE := Vector2(6.4, 3.6)
## How large the picture screen really is: the layout times this. 2.25 = 14.4 m x 8.1 m, which at
## SCREEN_DISTANCE fills about 100 degrees across and 68 up and down. The button grows with it.
const SCREEN_SCALE := 2.25
## How far in front of you the screen stands (metres).
const SCREEN_DISTANCE := 6.0
## The screen's centre is this far above your eyes.
const SCREEN_RISE := 0.1
const BUTTON_SIZE := Vector2(0.625, 0.21)
## id, text, centre on the screen in metres from the screen's centre (x right, y up).
## Only START is shown. An ["exit", "EXIT", Vector2(x, y)] line here brings back a button that quits the app.
const BUTTONS := [
	["start", "START", Vector2(0.0, -1.05)],
]
## Where the origin is parked while the lobby is open: far enough that nothing of the habitat is
## seen or heard.
const AWAY := Vector3(0.0, 500.0, 0.0)
const FADE_SEC := 0.45
## Black and white, to sit on any picture: START is white with black text, EXIT black with a white
## outline, and the button you point at turns white and glows.
## Per button: fill, text. LIT is what both turn into under the pointer.
const THEME := {
	"start": [Color(0.9, 0.9, 0.9, 0.96), Color(0.03, 0.03, 0.03)],
	"exit": [Color(0.0, 0.0, 0.0, 0.78), Color(1.0, 1.0, 1.0)],
}
## On the lunar surface the ground behind START is sunlit and nearly white, so there it is black with
## a white outline until you point at it.
const SURFACE_FILL := Color(0.0, 0.0, 0.0, 0.84)
const SURFACE_TEXT := Color(1.0, 1.0, 1.0)
const LIT := Color(1.0, 1.0, 1.0, 1.0)
const LIT_TEXT := Color(0.0, 0.0, 0.0)
const LINE := Color(1.0, 1.0, 1.0)

const BUTTON_SHADER := "
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;
uniform vec2 size = vec2(0.625, 0.21);
uniform float margin = 0.07;
uniform float border = 0.008;
uniform vec4 fill : source_color = vec4(0.0, 0.0, 0.0, 0.78);
uniform vec4 rim : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 lit : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float hover = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * (size + margin * 2.0);
	float r = size.y * 0.5;
	vec2 q = abs(p) - size * 0.5 + r;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	float aa = max(fwidth(d), 0.0005);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float edge = inside * smoothstep(-border - aa, -border + aa, d);
	vec3 body = mix(fill.rgb, lit.rgb, hover);
	vec3 col = mix(body, mix(rim.rgb, vec3(1.0), hover * 0.5), edge);
	float glow = hover * exp(-max(d, 0.0) * 48.0) * 0.6 * (1.0 - inside);
	ALBEDO = mix(col, rim.rgb, 1.0 - inside);
	ALPHA = inside * mix(mix(fill.a, lit.a, hover), 1.0, edge) + glow;
}
"

## "surface" or "screen", see the top of this file. Set before open().
var style := "screen"
## The background picture of style "screen", without the file type. Set before open() to use another one.
var background := "res://assets/lobby/lobby_background"
## false = a picture was found and is on the screen.
var placeholder := true
## The lobby is up and takes input (false while fading in or out).
var interactive := false

var _origin: XROrigin3D
var _camera: XRCamera3D
var _world: WorldEnvironment
var _stage: Node3D
var _screen: Node3D
var _buttons: Array[Dictionary] = []
var _hands: Array[Dictionary] = []
var _dot_mat: StandardMaterial3D
var _fade: MeshInstance3D
var _fade_mat: StandardMaterial3D
var _fade_value := 1.0
var _fade_target := 1.0
var _open := false
var _locked := false
var _tracked_for := 0.0
var _age := 0.0
var _suspended := false
var _home := Transform3D.IDENTITY
var _was_enabled := {}
var _hidden: Array[Node3D] = []
var _notes: Node
var _notes_mode := Node.PROCESS_MODE_INHERIT
var _env_saved := {}
## Style "surface": the lunar scene, where you stand on it (world, y = the ground) and which way you face.
var _moon: Node3D
var _spot := Vector3.ZERO
var _facing := 0.0
var _title: MeshInstance3D


func open(origin: XROrigin3D, camera: XRCamera3D, world: WorldEnvironment = null) -> void:
	_origin = origin
	_camera = camera
	_world = world
	if style == "surface" and not _find_spot():
		push_warning("Lobby|WARN: no lunar exterior in the scene, using the picture screen instead")
		style = "screen"
	_build()
	_suspend_game()
	_open = true
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.has_signal(&"pose_recentered"):
		xr.connect(&"pose_recentered", reanchor)
	if style == "surface":
		print("Lobby|INFO: open on the lunar surface at %s, facing the Earth" % str(_spot.snapped(Vector3.ONE * 0.1)))
	else:
		print("Lobby|INFO: open, background %s" % ("placeholder (no picture at %s.png)" % background if placeholder else "picture"))


## Style "surface": picks the place to stand and the direction to face. false without a lunar scene.
func _find_spot() -> bool:
	_moon = get_tree().get_first_node_in_group(&"lunar_exterior") as Node3D
	if _moon == null or not _moon.has_method(&"ground_y"):
		return false
	var earth := _moon.get_node_or_null("Earth") as Node3D
	var toward := Vector3(earth.global_position.x, 0.0, earth.global_position.z).normalized() if earth != null else Vector3.FORWARD
	var away := (-toward).rotated(Vector3.UP, deg_to_rad(SURFACE_TURN)) * SURFACE_DISTANCE
	_spot = Vector3(away.x, 0.0, away.z)
	var look := (earth.global_position - _spot) if earth != null else toward
	_facing = atan2(-look.x, -look.z)
	return true


## Puts the lobby in front of where you look now (after the headset's view is reset).
func reanchor() -> void:
	_locked = false
	_tracked_for = 0.5


func _process(delta: float) -> void:
	if not _open:
		return
	_age += delta
	_hide_notes_rig()
	if not _locked:
		_anchor(delta)
	_update_pointers(delta)
	_update_fade(delta)


# ------------------------------------------------------------------ building

func _build() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)

	# The button's plane. In style "surface" it is invisible: only START floats on it.
	_screen = Node3D.new()
	_screen.name = "Screen"
	_stage.add_child(_screen)
	if style == "surface":
		_build_title()
	else:
		_build_picture_screen()
	_build_buttons()
	_build_pointers()

	# Black in front of the eyes, for fading in and out.
	_fade = MeshInstance3D.new()
	var veil := QuadMesh.new()
	veil.size = Vector2(3.0, 3.0)
	_fade.mesh = veil
	_fade_mat = StandardMaterial3D.new()
	_fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_mat.no_depth_test = true
	_fade_mat.render_priority = 127
	_fade_mat.albedo_color = Color(0, 0, 0, 1)
	_fade.material_override = _fade_mat
	_fade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fade.position = Vector3(0, 0, -0.25)
	_camera.add_child(_fade)


## Style "surface": the title as solid letters far out in the landscape, lit by the sun.
func _build_title() -> void:
	var text := TextMesh.new()
	text.text = TITLE
	# TextMesh takes font sizes up to 127. A capital letter is about 0.72 of the font size tall.
	text.font_size = 96
	text.pixel_size = TITLE_HEIGHT / (96.0 * 0.72)
	text.depth = TITLE_HEIGHT * 0.16
	text.curve_step = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.9)
	mat.roughness = 0.85
	# A little light of its own, so the side away from the sun is grey and not black like the lunar shadows.
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 0.12
	_title = _item(_stage, text, mat, Vector3.ZERO)


## Style "screen": black all around you, and the picture.
func _build_picture_screen() -> void:
	# A black sphere seen from the inside hides the lunar scene; there is no floor and no frame.
	var space := SphereMesh.new()
	space.radius = 40.0
	space.height = 80.0
	space.radial_segments = 32
	space.rings = 16
	var black := _flat(Color.BLACK)
	black.cull_mode = BaseMaterial3D.CULL_FRONT
	_item(_stage, space, black, Vector3(0, 1.5, 0))

	var plane := QuadMesh.new()
	plane.size = SCREEN_SIZE
	var picture := _load_background()
	placeholder = picture == null
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if picture != null:
		mat.albedo_texture = picture
		# Fill the screen: a picture that is not 16:9 loses its sides or its top and bottom.
		var shape := float(picture.get_width()) / float(picture.get_height())
		var want := SCREEN_SIZE.x / SCREEN_SIZE.y
		var keep := Vector2(minf(want / shape, 1.0), minf(shape / want, 1.0))
		mat.uv1_scale = Vector3(keep.x, keep.y, 1.0)
		mat.uv1_offset = Vector3((1.0 - keep.x) * 0.5, (1.0 - keep.y) * 0.5, 0.0)
	else:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.03, 0.07, 0.11))
		ramp.set_color(1, Color(0.05, 0.2, 0.26))
		var tex := GradientTexture2D.new()
		tex.gradient = ramp
		tex.fill_from = Vector2(0.2, 0.0)
		tex.fill_to = Vector2(0.8, 1.0)
		tex.width = 256
		tex.height = 144
		mat.albedo_texture = tex
	_item(_screen, plane, mat, Vector3.ZERO)

	if placeholder:
		_text(_screen, "LUNAR HABITAT NOTES", 150, Vector3(0, 0.62, 0.02), Color.WHITE)
		_text(_screen, "VR design review", 64, Vector3(0, 0.22, 0.02), Color(0.75, 0.75, 0.75))
		_text(_screen, "No background picture yet: assets/lobby/lobby_background.png, 3840 x 2160", 46, Vector3(0, 1.58, 0.02), Color(0.8, 0.8, 0.8, 0.6))


func _build_buttons() -> void:
	for spec: Array in BUTTONS:
		var at: Vector2 = spec[2]
		if style == "surface":
			at.y = -SURFACE_BUTTON_DROP - SCREEN_RISE
		var node := Node3D.new()
		node.position = Vector3(at.x, at.y, 0.03)
		_screen.add_child(node)
		var look: Array = [SURFACE_FILL, SURFACE_TEXT] if style == "surface" else THEME[spec[0]]
		var bmat := _shader_mat(BUTTON_SHADER)
		bmat.render_priority = 1
		bmat.set_shader_parameter(&"size", BUTTON_SIZE)
		bmat.set_shader_parameter(&"fill", look[0])
		bmat.set_shader_parameter(&"lit", LIT)
		bmat.set_shader_parameter(&"rim", LINE)
		var quad := QuadMesh.new()
		quad.size = BUTTON_SIZE + Vector2(0.14, 0.14)
		_item(node, quad, bmat, Vector3.ZERO)
		var label := _text(node, spec[1], 52, Vector3(0, 0, 0.012), look[1])
		label.render_priority = 2
		_buttons.append({"id": spec[0], "at": at, "node": node, "mat": bmat, "label": label, "text": look[1], "hover": 0.0})


## One pointer per hand, on the aim pose (the template's own controller nodes use the grip pose).
func _build_pointers() -> void:
	_dot_mat = _flat(Color.WHITE)
	_dot_mat.render_priority = 3
	var beam := _flat(Color(LINE.r, LINE.g, LINE.b, 0.7))
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for tracker: StringName in [&"left_hand", &"right_hand"]:
		var ctrl := XRController3D.new()
		ctrl.name = "Lobby_" + String(tracker)
		ctrl.tracker = tracker
		ctrl.pose = &"default"
		_origin.add_child(ctrl)
		var ray := _item(ctrl, _box(Vector3(0.003, 0.003, 1.0)), beam, Vector3.ZERO)
		var tip := SphereMesh.new()
		tip.radius = 0.018
		tip.height = 0.036
		tip.radial_segments = 16
		tip.rings = 8
		var dot := _item(_screen, tip, _dot_mat, Vector3.ZERO)
		dot.visible = false
		ray.visible = false
		# down starts true, so a trigger held while the lobby appears does nothing until it is let go.
		_hands.append({"ctrl": ctrl, "ray": ray, "dot": dot, "down": true, "over": ""})


## The picture, with mipmaps so it does not shimmer in the headset. null when there is none.
func _load_background() -> Texture2D:
	for type: String in BACKGROUND_TYPES:
		var path := "%s.%s" % [background, type]
		var image: Image = null
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null and RenderingServer.get_current_rendering_method() != "forward_plus":
				# On the headset the picture is used as the project imports it (compressed, with mipmaps,
				# 2560 px wide: see lobby_background.png.import); unpacking it there would cost time and memory.
				print("Lobby|INFO: background %s, %d x %d as imported" % [path, tex.get_width(), tex.get_height()])
				return tex
			if tex != null:
				image = tex.get_image()
		elif FileAccess.file_exists(path):
			# Copied in but not imported by the editor yet.
			image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null or image.is_empty():
			continue
		if image.is_compressed():
			image.decompress()
		image.generate_mipmaps()
		print("Lobby|INFO: background %s, %d x %d" % [path, image.get_width(), image.get_height()])
		return ImageTexture.create_from_image(image)
	return null


# ------------------------------------------------------------------ placing

## Stands the screen in front of where the head looks, at eye height. Runs every frame until the
## headset has been tracked for a moment (the first frames of a session have no head pose yet).
func _anchor(delta: float) -> void:
	var head := _camera.position
	var tracked := head.length() > 0.2
	var forward := -_camera.transform.basis.z
	forward.y = 0.0
	var yaw := atan2(-forward.x, -forward.z) if forward.length() > 0.1 else 0.0
	var eyes := clampf(head.y, 0.9, 1.95) if tracked else 1.6
	_stage.position = Vector3(head.x, 0.0, head.z)
	_stage.rotation = Vector3(0.0, yaw, 0.0)
	_screen.position = Vector3(0.0, eyes + SCREEN_RISE, -SCREEN_DISTANCE)
	_screen.scale = Vector3.ONE * (SCREEN_SCALE if style == "screen" else 1.0)
	if style == "surface":
		# Turn and move the play space so that the head is over the spot, the real floor is the lunar
		# ground there, and looking straight ahead is looking at the Earth.
		_spot.y = float(_moon.call(&"ground_y", _spot.x, _spot.z, _spot.y))
		var turn := Basis(Vector3.UP, _facing - yaw)
		_origin.global_transform = Transform3D(turn, _spot - turn * Vector3(head.x, 0.0, head.z))
		_title.position = Vector3(0.0, eyes + tan(deg_to_rad(TITLE_ELEVATION)) * TITLE_DISTANCE, -TITLE_DISTANCE)
	if tracked:
		_tracked_for += delta
	if _tracked_for > 0.6 or _age > 4.0:
		_locked = true
		interactive = true
		_fade_target = 0.0


# ------------------------------------------------------------------ pointing

func _update_pointers(delta: float) -> void:
	var to_screen := _screen.global_transform.affine_inverse()
	var hovered := {}
	for hand: Dictionary in _hands:
		var ctrl: XRController3D = hand["ctrl"]
		var ray: MeshInstance3D = hand["ray"]
		var dot: MeshInstance3D = hand["dot"]
		var live := interactive and ctrl.get_is_active() and ctrl.get_has_tracking_data()
		ray.visible = live
		dot.visible = false
		var over := ""
		var reach := 2.5
		if live:
			var from := to_screen * ctrl.global_position
			var along := to_screen.basis * (-ctrl.global_basis.z)
			if along.z < -0.02 and from.z > 0.0:
				var hit := from + along * (-from.z / along.z)
				if absf(hit.x) < SCREEN_SIZE.x * 0.5 + 0.6 and absf(hit.y) < SCREEN_SIZE.y * 0.5 + 0.6:
					reach = ctrl.global_position.distance_to(_screen.global_transform * hit)
					dot.visible = true
					dot.position = Vector3(hit.x, hit.y, 0.05)
					for b: Dictionary in _buttons:
						var off: Vector2 = Vector2(hit.x, hit.y) - (b["at"] as Vector2)
						if absf(off.x) < BUTTON_SIZE.x * 0.5 + 0.04 and absf(off.y) < BUTTON_SIZE.y * 0.5 + 0.04:
							over = b["id"]
					# On a button the dot would sit on its text; the button lighting up shows where you point.
					dot.visible = over == ""
			ray.position = Vector3(0, 0, -reach * 0.5)
			ray.scale = Vector3(1, 1, reach)
		if over != "" and over != hand["over"]:
			ctrl.trigger_haptic_pulse(&"haptic", 0.0, 0.25, 0.04, 0.0)
		hand["over"] = over
		if over != "":
			hovered[over] = true
		var down := ctrl.is_button_pressed(&"trigger_click") or ctrl.get_float(&"trigger") > 0.75
		var pressed: bool = live and down and not hand["down"]
		hand["down"] = down
		if pressed and over != "":
			ctrl.trigger_haptic_pulse(&"haptic", 0.0, 0.6, 0.08, 0.0)
			_choose(over)
	for b: Dictionary in _buttons:
		b["hover"] = move_toward(b["hover"], 1.0 if hovered.has(b["id"]) else 0.0, delta * 9.0)
		(b["mat"] as ShaderMaterial).set_shader_parameter(&"hover", b["hover"])
		(b["node"] as Node3D).scale = Vector3.ONE * (1.0 + 0.045 * float(b["hover"]))
		(b["label"] as Label3D).modulate = (b["text"] as Color).lerp(LIT_TEXT, float(b["hover"]))


func _choose(id: String) -> void:
	if not interactive:
		return
	interactive = false
	print("Lobby|INFO: %s" % id)
	if id == "start":
		_start()
	else:
		_exit()


func _start() -> void:
	await _fade_to(1.0)
	# The trigger that pressed START is the note trigger too: wait until it is let go.
	var waited := 0.0
	while _any_trigger() and waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_stage.visible = false
	for hand: Dictionary in _hands:
		(hand["ray"] as Node3D).visible = false
	_resume_game()
	# A few frames for the habitat's lighting to settle around the new position before it is shown.
	await get_tree().create_timer(0.4).timeout
	await _fade_to(0.0)
	started.emit()
	close()


func _exit() -> void:
	exiting.emit()
	await _fade_to(1.0)
	get_tree().quit()


func _any_trigger() -> bool:
	for hand: Dictionary in _hands:
		var ctrl: XRController3D = hand["ctrl"]
		if ctrl.is_button_pressed(&"trigger_click") or ctrl.get_float(&"trigger") > 0.3:
			return true
	return false


## Removes the lobby. START does this by itself; call it to drop the lobby without a choice.
func close() -> void:
	_resume_game()
	_open = false
	for hand: Dictionary in _hands:
		(hand["ctrl"] as Node).queue_free()
	_hands.clear()
	if is_instance_valid(_fade):
		_fade.queue_free()
	queue_free()


# ------------------------------------------------------------------ the game behind

func _suspend_game() -> void:
	_suspended = true
	_home = _origin.global_transform
	if style != "surface":
		_origin.global_position += AWAY
		# Nothing of the world is seen from the lobby, so it is not drawn either (it would cost the
		# headset as much as standing in the habitat).
		for path in ["LunarHabitat", "LunarExterior"]:
			var part := _origin.get_parent().get_node_or_null(path) as Node3D
			if part != null and part.visible:
				part.visible = false
				_hidden.append(part)
	for path in ["XRMovement", "XRLadder", "XRMinimap"]:
		var n := _origin.get_node_or_null(path)
		if n != null and "enabled" in n:
			_was_enabled[n] = n.get("enabled")
			n.set("enabled", false)
	_notes = _origin.get_node_or_null("XRNotes")
	if _notes != null:
		_notes_mode = _notes.process_mode
		_notes.process_mode = Node.PROCESS_MODE_DISABLED
	# Show the picture as it was made: no film-like tone curve and no bloom on it. The lunar surface
	# keeps the scene's own look.
	if style != "surface" and _world != null and _world.environment != null:
		var env := _world.environment
		for prop in ["tonemap_mode", "tonemap_exposure", "glow_enabled", "fog_enabled", "volumetric_fog_enabled", "adjustment_enabled"]:
			_env_saved[prop] = env.get(prop)
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		env.glow_enabled = false
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.adjustment_enabled = false


func _resume_game() -> void:
	if not _suspended:
		return
	_suspended = false
	_origin.global_transform = _home
	for part in _hidden:
		if is_instance_valid(part):
			part.visible = true
	_hidden.clear()
	for n: Object in _was_enabled:
		if is_instance_valid(n):
			n.set("enabled", _was_enabled[n])
	_was_enabled.clear()
	if _notes != null:
		_notes.process_mode = _notes_mode
		for key in ["left", "right"]:
			var aim := _notes.get(key) as Node3D
			if aim != null:
				aim.visible = true
		_notes = null
	if _world != null and _world.environment != null:
		for prop: String in _env_saved:
			_world.environment.set(prop, _env_saved[prop])
	_env_saved.clear()


## The wrist board and the note pointer hang on XRNotes' own aim controllers, which it creates a
## frame after the scene starts; keep them out of sight while the lobby is open.
func _hide_notes_rig() -> void:
	if _notes == null:
		return
	for key in ["left", "right"]:
		var aim := _notes.get(key) as Node3D
		if aim != null and aim.visible:
			aim.visible = false


# ------------------------------------------------------------------ fading

func _update_fade(delta: float) -> void:
	if _fade_value != _fade_target:
		_fade_value = move_toward(_fade_value, _fade_target, delta / FADE_SEC)
	_fade_mat.albedo_color = Color(0, 0, 0, _fade_value)
	_fade.visible = _fade_value > 0.001


func _fade_to(value: float) -> void:
	_fade_target = value
	while absf(_fade_value - _fade_target) > 0.001:
		await get_tree().process_frame


# ------------------------------------------------------------------ small helpers

func _shader_mat(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


func _item(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(item)
	item.position = at
	return item


func _text(parent: Node3D, content: String, points: int, at: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = content
	label.font_size = points
	label.pixel_size = 0.0016
	label.outline_size = 0
	label.modulate = color
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	parent.add_child(label)
	label.position = at
	return label
