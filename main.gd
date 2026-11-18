## Main scene root.
##
## With a headset:  starts OpenXR and runs the VR rig under XROrigin3D
##                  (ladder, grab, passthrough, hand tracking, sticky notes on the wrist board).
## Without one:     hides the VR rig and spawns the desktop first-person player
##                  (WASD + mouse, Space / C for the ladder, N / E / Tab for sticky notes).
##
## Godot propagates _ready() up through children, so everything under XROrigin3D is set up
## before this script runs.
extends Node3D

var xr_interface: OpenXRInterface

## Preferred refresh rate. Will fall back to what the headset reports.
@export var target_refresh_rate := 72.0
## Render resolution relative to the headset's recommended size. Above 1.0 supersamples: straight
## edges stop crawling and text gets sharper, at the cost of GPU time. 1.0 = headset default.
@export_range(0.5, 2.0, 0.05) var render_scale := 1.2
## Shadows from the interior fill lights in VR. On the Quest every shadow-casting omni light shares
## one small shadow atlas, so 15 of them give blocky, crawling shadows (and redraw the habitat once
## per light). Off by default in VR; desktop keeps them. The sun keeps its shadows either way.
@export var vr_interior_light_shadows := false
## Sun shadow range in VR (metres). Smaller = sharper shadows near you. The desktop keeps the light's own value.
@export var vr_sun_shadow_distance := 30.0
## Baked lighting (LightmapGI + reflection probes in the "baked_lighting" group) is made for the
## Quest's Mobile renderer, which has no SDFGI / SSIL / SSAO / SSR. The desktop (Forward+) has those,
## so by default it hides the bake and keeps its own look.
@export var baked_lighting_on_desktop := false
## Prints frame timing to the log every 2 s in VR (adb logcat -s godot). For finding frame drops.
@export var log_performance := true

@export_group("Desktop fallback")
## Run the desktop player even when a headset is connected. Useful for typing note text at a desk.
@export var force_desktop := false
## Where the desktop player's feet start (world space). (0, 0, 0) is where the VR origin starts.
@export var desktop_start := Vector3(0.45, 0.05, 0.48)
@export var desktop_player_scene: PackedScene = preload("res://scenes/desktop_player.tscn")

## true once OpenXR is running. Scripts can check Main.is_vr via get_tree().current_scene.
var is_vr := false

@onready var xr_origin: XROrigin3D = $XROrigin3D


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface

	var xr_ok := false
	if force_desktop:
		print("Main|INFO: desktop mode forced")
	elif xr_interface == null:
		push_warning("Main|WARN: OpenXR interface not found (Project Settings -> XR). Running desktop.")
	elif xr_interface.is_initialized() or xr_interface.initialize():
		xr_ok = true
	else:
		print("Main|INFO: OpenXR failed to initialise (no headset connected?). Running desktop.")

	if not xr_ok:
		_start_desktop()
		return

	print("Main|INFO: OpenXR initialised successfully")
	var size_before := xr_interface.get_render_target_size()
	xr_interface.render_target_size_multiplier = render_scale
	print("Main|INFO: render target %s -> %s (scale %.2f)" % [size_before, xr_interface.get_render_target_size(), xr_interface.render_target_size_multiplier])

	# XR runtime frame pacing
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	get_viewport().use_xr = true
	# Screen-space AA (SMAA/FXAA from Project Settings) breaks on the Quest's multiview render target
	# ("Layers of our texture doesn't match view count"). VR uses MSAA + render_scale instead.
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if not vr_interior_light_shadows:
		var n := 0
		for l in find_children("*", "OmniLight3D", true, false) + find_children("*", "SpotLight3D", true, false):
			if (l as Light3D).shadow_enabled:
				(l as Light3D).shadow_enabled = false
				n += 1
		print("Main|INFO: VR: shadows off on %d interior lights (vr_interior_light_shadows)" % n)
	_apply_vr_quality()
	if log_performance:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		var t := Timer.new()
		t.wait_time = 2.0
		t.autostart = true
		t.timeout.connect(_log_performance)
		add_child(t)
	is_vr = true

	xr_interface.session_begun.connect(_on_session_begun)


func _on_session_begun() -> void:
	var rates := xr_interface.get_available_display_refresh_rates()
	if target_refresh_rate in rates:
		xr_interface.display_refresh_rate = target_refresh_rate
	elif not rates.is_empty():
		print("Main|WARN: %s Hz unavailable, runtime offers %s" % [target_refresh_rate, rates])

	# Match physics to the actual rate.
	var actual: float = xr_interface.display_refresh_rate
	if actual > 0.0:
		Engine.physics_ticks_per_second = int(round(actual))
	print("Main|INFO: running at %s Hz, render target %s, msaa %s" % [Engine.physics_ticks_per_second, xr_interface.get_render_target_size(), get_viewport().msaa_3d])


func _log_performance() -> void:
	var vp := get_viewport().get_viewport_rid()
	print("Perf|fps=%d process=%.1fms physics=%.1fms render_cpu=%.1fms render_gpu=%.1fms draws=%d objects=%d prims=%dk phys_active=%d pairs=%d mem=%dMB vram=%dMB" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.viewport_get_measured_render_time_gpu(vp),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
	])


## Quest (Mobile renderer) image quality. Every item here is cheap on the Quest's GPU.
func _apply_vr_quality() -> void:
	var vp := get_viewport()
	# Floors and walls are mostly seen at a grazing angle in VR; plain mipmaps blur them within a metre.
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
	var mats := 0
	for gi in find_children("*", "GeometryInstance3D", true, false):
		mats += _anisotropic_materials(gi as GeometryInstance3D)
	# The Mobile renderer's 10-bit colour buffer bands on smooth grey walls.
	vp.use_debanding = true
	# Sun shadows: spend the shadow map on the space around you, not 100 m of terrain.
	for d in find_children("*", "DirectionalLight3D", true, false):
		(d as DirectionalLight3D).directional_shadow_max_distance = vr_sun_shadow_distance
	var baked := get_tree().get_nodes_in_group("baked_lighting").size()
	print("Main|INFO: VR quality: 8x anisotropic on %d materials, debanding on, sun shadow %.0f m, %d baked-lighting nodes" % [mats, vr_sun_shadow_distance, baked])


func _anisotropic_materials(gi: GeometryInstance3D) -> int:
	var seen := 0
	var list: Array[Material] = [gi.material_override]
	var mi := gi as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			list.append(mi.get_surface_override_material(s))
			list.append(mi.mesh.surface_get_material(s))
	for m in list:
		var b := m as BaseMaterial3D
		if b != null and b.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
			b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			seen += 1
	return seen


## No headset: park the VR rig and bring in the desktop player.
func _start_desktop() -> void:
	xr_origin.visible = false
	if not baked_lighting_on_desktop:
		for n in get_tree().get_nodes_in_group("baked_lighting"):
			if n is Node3D:
				(n as Node3D).visible = false
		# The interior lights are Static (fully baked) for the Quest; on desktop make them real-time
		# again so SDFGI and real-time shadows light the habitat exactly as before the bake.
		for l in find_children("*", "Light3D", true, false):
			if (l as Light3D).light_bake_mode == Light3D.BAKE_STATIC:
				(l as Light3D).light_bake_mode = Light3D.BAKE_DYNAMIC
	xr_origin.process_mode = Node.PROCESS_MODE_DISABLED

	var player := desktop_player_scene.instantiate() as Node3D
	player.name = "DesktopPlayer"
	add_child(player)
	player.global_position = desktop_start
	print("Main|INFO: desktop player ready. WASD move, mouse look, Space / C ladder, N hold place note, E open, Tab list")
