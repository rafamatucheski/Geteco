extends SceneTree
## Paired rendered diagnostic: rejected V2 HUD versus the mounted V1 adapter.
## The same world, state, resolution and process are reused to limit drift.

const REJECTED := preload("res://ui/GameplayHUD.gd")
var world: Node
var classic: CanvasLayer
var rejected: CanvasLayer
var samples := {"before": [], "after": []}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	root.add_child(world)
	for frame in 900:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		print("HUD_AB_REPORT unavailable=session_not_ready")
		quit(1)
		return
	classic = world.hud
	for mode in ["before", "after", "before", "after"]:
		await _activate(mode)
		for frame in 45: await process_frame
		await _sample(mode, 4.0)
	await _activate("after")
	var before: Array = samples.before
	var after: Array = samples.after
	before.sort()
	after.sort()
	var report := {
		"resolution": "1280x720",
		"before_frames": before.size(),
		"after_frames": after.size(),
		"before_median_ms": _percentile(before, 0.50),
		"after_median_ms": _percentile(after, 0.50),
		"before_p95_ms": _percentile(before, 0.95),
		"after_p95_ms": _percentile(after, 0.95)
	}
	print("HUD_AB_REPORT ", JSON.stringify(report))
	quit(0)

func _activate(mode: String) -> void:
	if is_instance_valid(rejected):
		rejected.queue_free()
		await process_frame
	if mode == "before":
		classic.visible = false
		classic.process_mode = Node.PROCESS_MODE_DISABLED
		rejected = REJECTED.new()
		rejected.world = world
		world.add_child(rejected)
	else:
		classic.process_mode = Node.PROCESS_MODE_ALWAYS
		classic.visible = true
	for frame in 4: await process_frame

func _sample(mode: String, seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	var previous := Time.get_ticks_usec()
	while Time.get_ticks_usec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		(samples[mode] as Array).append(float(now - previous) / 1000.0)
		previous = now

func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	return snappedf(float(values[clampi(roundi((values.size() - 1) * fraction), 0, values.size() - 1)]), 0.001)
