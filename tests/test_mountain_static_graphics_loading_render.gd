extends SceneTree

const VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")
const WINTER_MODEL := preload("res://world/mountain_pass/transit/MountainWinterDressing3D.gd")
const FRAME_BUDGET_USEC := 16667
const RENDER_SIZE := Vector2i(960, 800)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("STATIC_GRAPHICS_LOADING_RENDER: " + message)

func _add_probe(view: Node2D) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 3.2, 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.32, 0.08, 1.0)
	box.material = material
	mesh.mesh = box
	mesh.position = Vector3(0, 1.6, 0)
	view.model.add_child(mesh)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("STATIC_GRAPHICS_LOADING_RENDER skipped_headless=true")
		quit(0)
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	VIEW.reset_global_graphics_prewarm_for_tests()
	var loading_session := VIEW.begin_graphics_prewarm_loading_session()
	var loading_cover := ColorRect.new()
	loading_cover.name = "LoadingCover"
	loading_cover.color = Color(0.03, 0.04, 0.07, 1.0)
	loading_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(loading_cover)
	var bootstrap: Dictionary = await VIEW.prewarm_graphics_backend(self, 3000, loading_session)
	_check(bool(bootstrap.get("ready", false)), "global loading bootstrap must finish")
	_check(not bool(bootstrap.get("timed_out", true)), "global loading bootstrap must not time out")
	_check(String(bootstrap.get("charged_to", "")) == "loading",
		"global bootstrap must be accounted to loading, not the static model")
	_check(bool(bootstrap.get("temporary_viewport_released", false)),
		"bootstrap viewport must be released before model preparation")
	_check(root.find_child("MountainStaticGraphicsPrewarm", true, false) == null,
		"bootstrap must not create a persistent viewport")
	_check(is_instance_valid(loading_cover) and loading_cover.visible,
		"loading cover must stay visible during bootstrap")

	var view := VIEW.new()
	view.position = Vector2(5000, 5000)
	root.add_child(view)
	view.build_view(WINTER_MODEL, 26.0, 18.0, Vector3(0, 1, 0), Vector3(0, 24, 20), RENDER_SIZE)
	view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_add_probe(view)
	for frame in 48:
		await process_frame
		if bool(view.get_render_profile().get("prepared_for_first_presentation", false)):
			break
	var prepared: Dictionary = view.get_render_profile()
	_check(bool(prepared.get("prepared_for_first_presentation", false)),
		"first post-loading view must finish background preparation")
	_check(int(prepared.get("prepare_bootstrap_frame", -1)) == -1,
		"post-loading view must not repeat the cold 1x1 bootstrap")
	_check(int(prepared.get("prepare_target_frame", -1)) >= 0,
		"post-loading view must still prepare its real target")
	_check(int(prepared.get("prepare_full_frame", -1)) >= 0,
		"post-loading view must still render its full-quality model")

	view.position = Vector2(160, 140)
	var activation_started := Time.get_ticks_usec()
	view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	var activation_usec := Time.get_ticks_usec() - activation_started
	var presented: Dictionary = view.get_render_profile()
	_check(bool(presented.get("first_presentation_reused", false)),
		"first visible presentation must reuse the prepared image")
	_check(activation_usec <= FRAME_BUDGET_USEC,
		"first post-loading presentation exceeded 16.67 ms: %d usec" % activation_usec)
	await RenderingServer.frame_post_draw
	var image := view.viewport_3d.get_texture().get_image()
	var viewport_size: Vector2i = view.viewport_3d.size
	var image_size: Vector2i = image.get_size() if image != null else Vector2i.ZERO
	_check(viewport_size == RENDER_SIZE,
		"prepared view must preserve the configured 960x800 target")
	_check(image != null and not image.is_empty(),
		"prepared view must retain a readable rendered image")
	loading_cover.queue_free()
	view.queue_free()
	await process_frame
	print("STATIC_GRAPHICS_LOADING_RENDER bootstrap=", bootstrap,
		" prepared=", prepared, " presented=", presented,
		" activation_usec=", activation_usec,
		" viewport_size=", viewport_size,
		" image_size=", image_size,
		" failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
