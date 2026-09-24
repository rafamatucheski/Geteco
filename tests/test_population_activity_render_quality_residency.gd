extends SceneTree

const ACTIVITY := preload("res://systems/PopulationActivity.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)


func _run() -> void:
	var settings := root.get_node("SettingsManager")
	var quality := _render_quality_node(settings)
	_check(quality != null, "RenderQuality must be installed")
	if quality == null:
		quit(1)
		return
	var original: int = settings.msaa_3d
	settings.msaa_3d = Viewport.MSAA_2X
	settings.display_settings_changed.emit()

	var holder := Node.new()
	holder.name = "PopulationRenderQualityFixture"
	root.add_child(holder)
	var activity = ACTIVITY.new()
	var actors: Array[Node2D] = []
	var views: Array[SubViewport] = []
	for index in 10:
		var actor := Node2D.new()
		actor.name = "Resident_%d" % index
		holder.add_child(actor)
		var viewport := SubViewport.new()
		viewport.name = "ResidentView_%d" % index
		viewport.size = Vector2i(256, 256)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		actor.add_child(viewport)
		actors.append(actor)
		views.append(viewport)
	await process_frame

	for actor in actors:
		activity.set_active(actor, false)
	for viewport in views:
		_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "PopulationActivity must put resident views to sleep")
		_check(viewport.msaa_3d == Viewport.MSAA_2X, "fixture must start at global 2x")

	settings.msaa_3d = Viewport.MSAA_4X
	settings.display_settings_changed.emit()
	for _frame in 120:
		var snapshot: Dictionary = quality.get_refresh_stats()
		if bool(snapshot.idle):
			break
		await process_frame
	var idle_stats: Dictionary = quality.get_refresh_stats()
	_check(bool(idle_stats.idle), "RenderQuality must become idle with sleeping population")
	_check(int(idle_stats.pending) == 0, "active refresh queue must be empty after grace")
	_check(not quality.is_processing(), "sleeping population must not leave a per-frame quality poller")
	for viewport in views:
		_check(viewport.msaa_3d == Viewport.MSAA_2X, "sleeping caches must not allocate 4x before residency")
		_check(viewport.has_meta("quality_residency_hook"), "sleeping cache must retain the production residency hook")

	# This is the production call path, after the grace timer is already stopped.
	activity.set_active(actors[0], true)
	_check(views[0].msaa_3d == Viewport.MSAA_4X, "PopulationActivity must apply pending quality before late wake")
	_check(views[0].render_target_update_mode == SubViewport.UPDATE_ALWAYS, "PopulationActivity must restore the authored live mode")
	_check(not views[0].has_meta("quality_residency_hook"), "late wake must consume the hook")
	for index in range(1, views.size()):
		_check(views[index].msaa_3d == Viewport.MSAA_2X, "one late wake must not allocate unrelated sleeping views")
		_check(views[index].render_target_update_mode == SubViewport.UPDATE_DISABLED, "one late wake must not wake unrelated population")
	var wake_stats: Dictionary = quality.get_refresh_stats()
	_check(bool(wake_stats.idle) and int(wake_stats.pending) == 0, "event-driven late wake must leave RenderQuality idle")

	settings.msaa_3d = original
	settings.display_settings_changed.emit()
	holder.queue_free()
	await process_frame
	print("POPULATION_RENDER_QUALITY_RESIDENCY_RESULT failures=%d idle=%s" % [failures, JSON.stringify(wake_stats)])
	quit(0 if failures == 0 else 1)


func _render_quality_node(settings: Node) -> Node:
	for child in settings.get_children():
		if child.get_script() == preload("res://systems/RenderQuality.gd"):
			return child
	return null
