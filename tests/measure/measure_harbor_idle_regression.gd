extends "res://tests/measure/measure_performance_plan.gd"
## Production idle/foot diagnostic; inherits isolated saves, population settling,
## 10 s warm-up, >=30 s sampling and --out=, --label=, --seconds=, --profile.
## --market selects the facade viewpoint; --reveal-on opts into diagnostic
## exterior transparency. Normal play keeps it off; --reveal-off also forces off.
## --walk uses normal actor movement between nearby endpoints, never sample-time
## teleportation. Record concurrent rendered processes outside this runner:
## it cannot certify that other Codex chats/Godot sessions left the GPU idle.
const MARKET_POINT := Vector3(109.375, .12, 32.8875)
const WALK_HALF_LENGTH := 1.5
var _market := false
var _reveal_off := false
var _reveal_on := false
var _walk := false
var _preview := false
var _night := false
var _night_applied := false
var _walk_anchor := Vector3.ZERO
var _walk_side := 1.0
var _walk_turns := 0
var _walk_distance := 0.0
var _previous_walk_point := Vector3.INF

func _initialize() -> void:
	root.close_requested.connect(func(): print("HARBOR_IDLE_WINDOW_CLOSE_REQUEST ",Time.get_ticks_usec()))
	super._initialize()

func settle_load() -> bool:
	var args := OS.get_cmdline_user_args()
	_market = "--market" in args
	_reveal_off = "--reveal-off" in args
	_reveal_on = "--reveal-on" in args
	_walk = "--walk" in args
	_preview = "--camera-preview" in args
	_night = "--night" in args
	scenario = "walk" if _walk else "idle"
	world.camera.set_preview_view(_preview)
	world.camera.heading = 0.0
	if _reveal_on: world.camera._exterior_reveal.enabled = true
	if _reveal_off: world.camera._exterior_reveal.enabled = false
	if _market:
		# This relocation belongs to setup, before settling/warm-up/measurement.
		world.production.region.prepare_collision_at(MARKET_POINT)
		world.player.teleport(MARKET_POINT)
		world.production.region.set_focus(MARKET_POINT)
		world.session.railway_world.set_focus(MARKET_POINT)
		world.camera.initialized = false
	print("HARBOR_IDLE_CONTEXT ", JSON.stringify({
		"pid": OS.get_process_id(), "market": _market, "walk": _walk,
		"reveal_off": _reveal_off, "reveal_on": _reveal_on,
		"concurrency": "Unverified: other rendered sessions may contaminate frame times; capture process inventory separately."
	}))
	var settled: bool = await super.settle_load()
	# Loading can take long enough for the user to leave the window. Request
	# focus once before warm-up; never steal it back during the measured loop.
	if settled:
		# A hidden console launch can leave the engine reporting minimized even
		# after focus returns. Restore once before warm-up, never during sampling.
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_move_to_foreground()
	_walk_anchor = world.player.global_position
	_previous_walk_point = _walk_anchor
	return settled

func apply_load(_now: int) -> void:
	# The parent establishes daytime after settling. Apply night once at the
	# first warm-up callback, before the measured interval, without saving settings.
	if _night and not _night_applied:
		_night_applied = true
		world.session.weather.time_of_day = .78
		world.session.state.world_state.time = .78
		world.session.weather._update()
	if not _walk: return
	var point: Vector3 = world.player.global_position
	if _previous_walk_point.is_finite():
		_walk_distance += Vector2(point.x - _previous_walk_point.x, point.z - _previous_walk_point.z).length()
	_previous_walk_point = point
	var goal := _walk_anchor + Vector3.RIGHT * WALK_HALF_LENGTH * _walk_side
	var offset := goal - point
	offset.y = 0.0
	if offset.length_squared() < .04:
		_walk_side = -_walk_side
		_walk_turns += 1
		goal = _walk_anchor + Vector3.RIGHT * WALK_HALF_LENGTH * _walk_side
		offset = goal - point
		offset.y = 0.0
	# A real obstacle can prevent reaching a waypoint. Preserve it and report
	# actual movement/turns, rather than teleporting or claiming a completed route.
	world.player.automatic_direction = offset.normalized()

func state() -> Dictionary:
	var row := super.state()
	row["exterior_reveal"] = world.camera._exterior_reveal.debug_snapshot()
	row["idle_regression_fixture"] = {
		"market": _market, "reveal_off_diagnostic": _reveal_off,
		"requested_preview": _preview, "night": _night, "reveal_on_diagnostic": _reveal_on,
		"motion": "physical_walk" if _walk else "stationary",
		"walk_anchor": str(_walk_anchor), "walk_half_length": WALK_HALF_LENGTH,
		"walk_turns": _walk_turns, "walk_distance_since_warmup_m": _walk_distance,
		"player_velocity": str(world.player.velocity),
		"concurrency_verified": false, "pid": OS.get_process_id(),
		"scope": "Normal production callbacks and live population. Teleport only during setup. With --walk, actual movement starts in warm-up and continues during sampling; this overrides the parent's stationary-fixture description. Concurrent external work is not controlled, so these measurements alone cannot certify regression or absolute FPS."
	}
	return row
