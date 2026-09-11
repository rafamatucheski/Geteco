extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	check(root.msaa_2d == Viewport.MSAA_2X, "Cenário 2D deve usar MSAA.")
	var model := SubViewport.new()
	model.own_world_3d = true
	model.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(model)
	check(model.msaa_3d == Viewport.MSAA_2X, "Modelo criado em runtime deve usar MSAA.")
	check(model.render_target_update_mode == SubViewport.UPDATE_DISABLED, "AA deve preservar cache de renderização.")
	var portrait := SubViewport.new()
	portrait.msaa_3d = Viewport.MSAA_4X
	root.add_child(portrait)
	check(portrait.msaa_3d == Viewport.MSAA_4X, "Preservar qualidade explícita maior.")
	var bridge := SubViewport.new()
	bridge.disable_3d = true
	root.add_child(bridge)
	check(bridge.msaa_2d == Viewport.MSAA_2X, "Arte 2D em viewport próprio também precisa de AA.")
	model.queue_free()
	portrait.queue_free()
	bridge.queue_free()
	await process_frame
	print("RENDER_QUALITY_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)
