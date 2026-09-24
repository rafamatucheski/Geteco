extends SceneTree

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
	_check(quality != null, "RenderQuality must be installed by SettingsManager")
	if quality == null:
		quit(1)
		return
	var original: int = settings.msaa_3d
	settings.msaa_3d = Viewport.MSAA_2X

	var holder := Node.new()
	holder.name = "RenderQualityCadenceFixture"
	root.add_child(holder)
	var authored: Array[SubViewport] = []
	var dormant: Array[SubViewport] = []
	var live: Array[SubViewport] = []
	for index in 6:
		var viewport := _viewport("Authored_%d" % index, Vector2i(640, 360), SubViewport.UPDATE_DISABLED, Viewport.MSAA_2X)
		holder.add_child(viewport)
		authored.append(viewport)
	for index in 10:
		var viewport := _viewport("Dormant_%d" % index, Vector2i(512, 512), SubViewport.UPDATE_DISABLED, Viewport.MSAA_DISABLED)
		holder.add_child(viewport)
		dormant.append(viewport)
	for index in 6:
		var viewport := _viewport("Live_%d" % index, Vector2i(256, 256), SubViewport.UPDATE_ALWAYS, Viewport.MSAA_DISABLED)
		holder.add_child(viewport)
		live.append(viewport)
	await process_frame

	settings.msaa_3d = Viewport.MSAA_4X
	settings.display_settings_changed.emit()
	for viewport in authored:
		_check(viewport.msaa_3d == Viewport.MSAA_2X, "authored 2x view must not be globally promoted")
	for viewport in dormant:
		_check(viewport.msaa_3d == Viewport.MSAA_2X, "dormant generic view must keep its resident cache until reactivated")
		_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "quality refresh must not wake dormant caches together")

	for _frame in 8:
		await process_frame
	for viewport in live:
		_check(viewport.msaa_3d == Viewport.MSAA_4X, "live generic view must receive global quality through the bounded queue")
	for viewport in dormant:
		_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "dormant cache must remain asleep while not resident")

	# Existing owners that resume immediately after the settings menu are caught
	# by a short, finite grace window without needing a per-frame watcher.
	var immediate_return := dormant[0]
	immediate_return.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _frame in 12:
		await process_frame
	_check(immediate_return.msaa_3d == Viewport.MSAA_4X, "view reactivated during grace must receive pending global quality")

	# The grace sweep has a hard stop. After it ends there must be no process or
	# timer polling, even while other dormant caches retain pending metadata.
	for _frame in 120:
		var snapshot: Dictionary = quality.get_refresh_stats()
		if bool(snapshot.idle):
			break
		await process_frame
	var stats: Dictionary = quality.get_refresh_stats()
	_check(int(stats.max_applied_in_frame) <= 4, "refresh cadence must cap viewport changes per frame")
	_check(int(stats.awakened) == 0, "quality increase must not wake dormant cached views")
	_check(int(stats.deferred_dormant) >= 10, "telemetry must expose deferred dormant views")
	_check(int(stats.pending) == 0, "active refresh queue must drain completely")
	_check(bool(stats.idle), "RenderQuality must become fully idle after the finite grace window")
	_check(not quality.is_processing(), "RenderQuality must not keep a per-frame dormant polling loop")
	_check(int(stats.grace_checks) <= 512, "residency grace must perform a finite bounded number of checks")

	# Long-lived caches carry a lightweight event hook in metadata. Their owner
	# invokes it immediately before waking the viewport, with no global scan.
	var late_return := dormant[1]
	var residency_hook: Callable = late_return.get_meta("quality_residency_hook", Callable())
	_check(residency_hook.is_valid(), "dormant cache must expose a residency hook")
	if residency_hook.is_valid():
		_check(bool(residency_hook.call()), "residency hook must apply pending quality")
	late_return.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_check(late_return.msaa_3d == Viewport.MSAA_4X, "late reactivated view must already have current quality")
	_check(not late_return.has_meta("quality_pending_msaa"), "residency hook must consume pending metadata")
	for index in range(2, dormant.size()):
		_check(dormant[index].render_target_update_mode == SubViewport.UPDATE_DISABLED, "late residency hook must not wake unrelated caches")

	settings.msaa_3d = original
	settings.display_settings_changed.emit()
	holder.queue_free()
	await process_frame
	print("RENDER_QUALITY_CADENCE_RESULT failures=%d stats=%s" % [failures, JSON.stringify(stats)])
	quit(0 if failures == 0 else 1)


func _viewport(name_value: String, size_value: Vector2i, update_mode: SubViewport.UpdateMode, msaa: Viewport.MSAA) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = name_value
	viewport.size = size_value
	viewport.own_world_3d = true
	viewport.msaa_3d = msaa
	viewport.render_target_update_mode = update_mode
	return viewport


func _render_quality_node(settings: Node) -> Node:
	for child in settings.get_children():
		if child.get_script() == preload("res://systems/RenderQuality.gd"):
			return child
	return null
