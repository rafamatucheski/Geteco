extends SceneTree
## Graphics preferences: real viewport application, presets, migration, persistence and menu rollback.
const OPTIONS := preload("res://runtime/GraphicsOptions.gd")
var failures: Array[String] = []
var checks := 0
class ReflectionFixture extends "res://world/city_look/CoastalPlanarReflections.gd":
	# Isolate the production quality subscriber from world registration/capture work.
	func _ready() -> void: set_process(false)
	func _exit_tree() -> void: pass

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ")+label)

func run() -> void:
	var settings := root.get_node("V2Settings")
	var stage := Node3D.new()
	root.add_child(stage)
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 8.0
		stage.add_child(camera)
		camera.position = Vector3(4,4,4)
		camera.look_at(Vector3.ZERO)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45,-35,0)
		stage.add_child(light)
		var cube := MeshInstance3D.new()
		cube.mesh = BoxMesh.new()
		stage.add_child(cube)
	var original := {}
	for key in OPTIONS.KEYS: original[key] = settings.get(key)
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "forward_plus","Forward+ desktop default")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "mobile","Mobile platform override preserved")
	var menu: Control = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.open()
	for key in ["graphics_preset","aa_mode","upscale_mode","anisotropy","shadow_distance","reflection_quality","detail_quality","ssao","volumetric_fog","glow","glow_strength"]:
		check(menu._widgets.has(key),"menu graphics option: "+key)
	check(menu._widgets.aa_mode.item_count == 3 and menu._widgets.upscale_mode.item_count == 2 and not menu._widgets.has("ssr"),"high-memory shader options removed from menu")
	var fps_before := Engine.max_fps
	var window_before: int = settings.window_mode
	var brightness_before: float = settings.brightness
	var config_path: String = settings.default_path().get_base_dir().path_join("graphics-roundtrip.cfg")
	DirAccess.make_dir_recursive_absolute(config_path.get_base_dir())
	for preset in [1,2,3]:
		settings.set_graphics_preset(preset)
		check(settings.graphics_preset() == preset,"preset recognised: "+str(preset))
		check(settings.window_mode == window_before and Engine.max_fps == fps_before and settings.brightness == brightness_before,"preset preserves display, frame cap and brightness: "+str(preset))
		check(settings.save_settings(config_path) == OK,"save preset: "+str(preset))
		settings.detail_quality = (settings.detail_quality+1)%3
		check(settings.load_settings(config_path) == OK and settings.graphics_preset() == preset,"reload preset: "+str(preset))
	settings.set_graphics_preset(2)
	menu._refresh_graphics_widgets()
	menu._widgets.graphics_preset.item_selected.emit(1)
	check(settings.graphics_preset() == 1 and menu._widgets.graphics_preset.selected == 1,"preset menu applies low")
	menu._widgets.anisotropy.item_selected.emit(4)
	check(settings.anisotropy == 4 and menu._widgets.graphics_preset.selected == 0,"individual change selects Custom")
	for mode in [0,1,2]:
		settings.aa_mode = mode
		settings.msaa = 2
		settings.upscale_mode = 1
		settings.apply_settings()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
		if mode == 0: check(root.msaa_3d == Viewport.MSAA_4X and not root.use_taa,"MSAA4x active exclusively")
		elif OPTIONS.modern_renderer():
			check(root.msaa_3d == Viewport.MSAA_DISABLED,"post-process AA does not stack with MSAA: "+str(mode))
			if mode == 1: check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA,"FXAA applied")
			if mode == 2: check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA,"SMAA applied")
		check(not root.use_taa,"supported AA keeps temporal shaders off: "+str(mode))
	# Even stale direct callers cannot reactivate the process-wide advanced shader group.
	settings.aa_mode = 3
	settings.upscale_mode = 2
	settings.render_scale = .75
	settings.apply_settings()
	check(root.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2 and not root.use_taa,"legacy direct settings cannot activate FSR2 or TAA")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	settings.upscale_mode = 1
	settings.aa_mode = 0
	settings.apply_settings()
	check(not root.use_taa and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED,"leaving temporal AA clears viewport flags")
	var env := Environment.new()
	settings.ssao = true
	settings.volumetric_fog = true
	settings.apply_environment(env)
	env.ssr_enabled = true
	settings.apply_environment(env)
	check(env.ssao_enabled == OPTIONS.forward_plus() and not env.ssr_enabled and env.volumetric_fog_enabled == OPTIONS.forward_plus(),"supported effects respect renderer and stale SSR is disabled")
	settings.ssao = false
	settings.volumetric_fog = false
	settings.apply_environment(env)
	check(not env.ssao_enabled and not env.ssr_enabled and not env.volumetric_fog_enabled,"advanced effects turn off")
	var detail := MeshInstance3D.new()
	detail.mesh = BoxMesh.new()
	detail.visibility_range_end = 100.0
	OPTIONS.tag_detail(detail)
	root.add_child(detail)
	await process_frame
	settings.detail_quality = 0
	settings.apply_settings()
	check(is_equal_approx(detail.visibility_range_end,80.0),"existing decorative detail follows low quality")
	settings.detail_quality = 2
	settings.apply_settings()
	settings.apply_settings()
	check(is_equal_approx(detail.visibility_range_end,140.0),"detail changes do not compound")
	var streamed := MeshInstance3D.new()
	streamed.mesh = BoxMesh.new()
	streamed.visibility_range_end = 100.0
	OPTIONS.tag_detail(streamed)
	root.add_child(streamed)
	await process_frame
	check(is_equal_approx(streamed.visibility_range_end,140.0),"new streamed detail inherits quality")
	var reflections := ReflectionFixture.new()
	reflections.ground_view = SubViewport.new()
	reflections.facade_view = SubViewport.new()
	reflections.add_child(reflections.ground_view)
	reflections.add_child(reflections.facade_view)
	root.add_child(reflections)
	settings.reflection_quality = 0
	reflections._apply_graphics_quality()
	check(reflections.ground_view.size == Vector2i(320,180) and reflections.facade_view.size == Vector2i(256,144),"low reflections resize real capture targets")
	settings.reflection_quality = 2
	reflections._apply_graphics_quality()
	check(reflections.ground_view.size == Vector2i(960,540) and reflections.facade_view.size == Vector2i(768,432),"high reflections resize real capture targets")
	reflections.queue_free()
	var legacy := ConfigFile.new()
	legacy.set_value("display","msaa",2)
	legacy.set_value("display","render_scale",.8)
	legacy.save(config_path)
	settings.load_settings(config_path)
	check(settings.msaa == 2 and is_equal_approx(settings.render_scale,.8) and settings.aa_mode == 0 and not settings.ssao,"legacy config preserves choices and uses safe defaults")
	legacy.set_value("graphics","aa_mode",3)
	legacy.set_value("graphics","upscale_mode",2)
	legacy.set_value("graphics","ssr",true)
	legacy.save(config_path)
	settings.load_settings(config_path)
	settings.apply_settings()
	check(settings.aa_mode == 2 and settings.upscale_mode == 1 and settings.msaa == 2 and is_equal_approx(settings.render_scale,.8),"legacy temporal preferences migrate without changing resolution or MSAA choice")
	check(settings.save_settings(config_path) == OK,"migrated preferences save")
	var migrated := ConfigFile.new()
	migrated.load(config_path)
	check(not migrated.has_section_key("graphics","ssr"),"removed SSR preference is no longer persisted")
	menu.close()
	for key in OPTIONS.KEYS: check(settings.get(key) == original[key],"Cancel restores "+key)
	menu.open()
	menu._widgets.graphics_preset.item_selected.emit(3)
	menu._save()
	settings.set_graphics_preset(1)
	check(settings.load_settings() == OK and settings.graphics_preset() == 3,"Save commits graphics menu choices")
	for key in OPTIONS.KEYS: settings.set(key,original[key])
	settings.apply_settings()
	settings.save_settings()
	if DisplayServer.get_name() != "headless":
		settings.set_graphics_preset(2)
		menu.open()
		menu.show()
		for index in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/settings-forward-20261019/menu-top.png")
		menu._pages[0].scroll_vertical = 550
		for index in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/settings-forward-20261019/menu-quality.png")
		menu._pages[0].scroll_vertical = 5000
		for index in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/settings-forward-20261019/menu-effects.png")
		menu.close()
		for key in OPTIONS.KEYS: settings.set(key,original[key])
		settings.apply_settings()
	detail.queue_free()
	streamed.queue_free()
	menu.queue_free()
	stage.queue_free()
	await process_frame
	print("GRAPHICS_SETTINGS ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	quit(0 if failures.is_empty() else 1)
