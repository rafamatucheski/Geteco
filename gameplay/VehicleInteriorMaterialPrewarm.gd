extends RefCounted
## Submit the two real shared interior materials under the existing loading cover.
## This prepares their shaders, not every mesh-specific graphics pipeline.
const INTERIOR = preload("res://gameplay/VehicleInterior.gd")
const GUARDS = preload("res://gameplay/emergency/EffectsPrewarm.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
static var _drawn := false

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _drawn or not INTERIOR.enabled or DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var tree := host.get_tree()
	INTERIOR.prepare_shared_materials()
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	for frame in MAX_WAIT_FRAMES:
		await tree.process_frame
		if not GUARDS._covered_loading(host, curtain) or not GUARDS._current_camera(host, camera): break
		if draws[0] >= DRAW_FRAMES:
			_drawn = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw):
		RenderingServer.frame_post_draw.disconnect(count_draw)
