extends SceneTree

## Shared harness for tests/claude_gameplay_audit/*.
## Boots the real production world (res://district/harbor_preview/HarborGame.tscn)
## with isolated save/settings paths so no test ever touches a player's real
## user://saves/ slot, and gives every concrete audit test the same small set
## of helpers (check/log/screenshot/finish) so results are easy to compare.
##
## Concrete tests extend this file (see tests/test_region_travel.gd for the
## same "extends another test's .gd" convention already used in this repo)
## and implement their own _initialize() -> call_deferred("run"). Exit codes
## follow the convention already established by test_vehicle_boarding_sides.gd
## and friends: 0 = all checks passed, 1 = at least one check failed,
## 2 = watchdog fired (the test hung and never reached its own quit()).

const HARBOR_SCENE := "res://district/harbor_preview/HarborGame.tscn"
const AUDIT_DIR := "res://tests/claude_gameplay_audit/"

var failures: Array[String] = []
var passed_count: int = 0
var _log_lines: Array[String] = []
var _isolated_save_dir: String = ""
var _tag: String = "audit"


func log_line(msg: String) -> void:
	print(msg)
	_log_lines.append(msg)


func check(ok: bool, message: String) -> bool:
	if ok:
		passed_count += 1
		log_line("  [PASS] %s" % message)
	else:
		failures.append(message)
		log_line("  [FAIL] %s" % message)
	return ok


## Every audit test must call this before anything else so a stuck await
## cannot hang the headless process forever (exit code 2 = "não executado").
func arm_watchdog(seconds: float = 90.0) -> void:
	create_timer(seconds).timeout.connect(func():
		log_line("  [WATCHDOG] %s did not finish within %.0fs — treating as NOT EXECUTED" % [_tag, seconds])
		quit(2)
	)


## Redirects SaveManager (and, if present, SettingsManager) to a throwaway
## per-run temp directory, exactly like tests/test_menu_flow_integration.gd
## does, so a save created by this audit can never overwrite a real player
## slot_01..slot_05/autosave. Returns the directory used.
func isolate_saves(tag: String) -> String:
	var sm := root.get_node_or_null("SaveManager")
	_isolated_save_dir = OS.get_temp_dir().path_join("geteco_claude_audit_%s_%d" % [tag, Time.get_ticks_usec()]) + "/"
	if sm:
		sm.set("_save_dir", _isolated_save_dir)
		sm.set("_save_directory_ready", false)
	var setm := root.get_node_or_null("SettingsManager")
	if setm:
		setm.set("_settings_path", OS.get_temp_dir().path_join("geteco_claude_audit_settings_%d.cfg" % Time.get_ticks_usec()))
	return _isolated_save_dir


func cleanup_isolated_saves() -> void:
	if _isolated_save_dir.is_empty():
		return
	var dir := DirAccess.open(_isolated_save_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while not f.is_empty():
		if not dir.current_is_dir():
			dir.remove(f)
		f = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(_isolated_save_dir.trim_suffix("/"))


func frames(count: int = 4) -> void:
	for _i in count:
		await process_frame


func physics_frames(count: int = 4) -> void:
	for _i in count:
		await physics_frame


## Presses+releases a real key exactly like the codebase's own recent tests
## (test_maciota_interrupted_conversation.gd, test_workshop_gameplay_integration.gd)
## instead of Input.action_press, since several interact/dialogue handlers only
## react to InputEventKey.
func press_key(code: Key, settle_frames: int = 3) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frames(settle_frames)


func release_movement() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(action)


## Walks `actor` toward `target` using real directional input (ui_left/right/
## up/down) — the same movement path the player uses in real gameplay, not a
## teleport — mirroring the walk helpers already established in
## tests/test_workshop_gameplay_integration.gd and
## tests/test_garage_real_circulation.gd. Returns true once within `tolerance`
## px of `target`; false if `max_frames` elapses first (a genuine "circulation
## failed" result — callers should treat that as a real failure, not paper
## over it with a teleport).
func walk_to(actor: CharacterBody2D, target: Vector2, max_frames: int = 240, tolerance: float = 10.0) -> bool:
	for _i in range(max_frames):
		var delta: Vector2 = target - actor.global_position
		if delta.length() <= tolerance:
			release_movement()
			return true
		var direction := delta.normalized()
		if direction.x > 0.15:
			Input.action_press("ui_right")
			Input.action_release("ui_left")
		elif direction.x < -0.15:
			Input.action_press("ui_left")
			Input.action_release("ui_right")
		else:
			Input.action_release("ui_left")
			Input.action_release("ui_right")
		if direction.y > 0.15:
			Input.action_press("ui_down")
			Input.action_release("ui_up")
		elif direction.y < -0.15:
			Input.action_press("ui_up")
			Input.action_release("ui_down")
		else:
			Input.action_release("ui_up")
			Input.action_release("ui_down")
		await physics_frame
	release_movement()
	return actor.global_position.distance_to(target) <= tolerance


## Polls `condition` (a Callable returning bool) until it's true or
## `timeout_seconds` of real time elapses. Returns true/false accordingly, and
## logs `timeout_message` on failure — used wherever a real-time streamed
## system (ContinuousWorld region prep, async door transitions) needs a bounded
## wait with a clear, specific timeout reason instead of a bare failed check.
func wait_until(condition: Callable, timeout_seconds: float, timeout_message: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			log_line("  [TIMEOUT] %s (após %.0fs)" % [timeout_message, timeout_seconds])
			return false
		await process_frame
	return true


## Boots the real production HarborGame.tscn. Campaign flags must be set
## BEFORE this call (HarborGame._start_gameplay calls start_or_resume() exactly
## once; setting flags after would require a second call and double-lock the
## player, per the comment in tests/test_maciota_interrupted_conversation.gd).
func boot_harbor(settle_frames: int = 30) -> Node2D:
	change_scene_to_file(HARBOR_SCENE)
	await frames(settle_frames)
	return current_scene


## Convenience: skips the whole onboarding (arrival CGI, phone call, meeting
## Maciota, accepting/delivering the first contract) so a test that targets an
## unrelated system boots straight into free-roam control.
func skip_onboarding_flags() -> void:
	var campaign := root.get_node("CampaignState")
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_started", &"harbor_delivery_picked_up", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)


## Screenshots require an actual rendering context: in --headless mode
## RenderingServer.frame_post_draw never fires (nothing is ever drawn), so
## this is a silent no-op there — exactly the guard tests/test_workshop_gameplay_integration.gd
## and tests/test_cobra_campaign_gameplay.gd use before their own capture calls.
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		log_line("  [CAPTURE SKIPPED] %s (rodando em --headless, sem contexto de renderização)" % name)
		return
	await frames(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out_path := AUDIT_DIR + "captures/%s.png" % name
	var err := img.save_png(out_path)
	log_line("  [CAPTURE] %s (err=%s)" % [out_path, error_string(err)])


func finish(tag: String, world: Node = null) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	log_line("=================================================================")
	var total := passed_count + failures.size()
	if failures.is_empty():
		log_line("=== %s: APROVADO (%d/%d verificações) ===" % [tag, passed_count, total])
	else:
		log_line("=== %s: FALHOU (%d/%d verificações falharam) ===" % [tag, failures.size(), total])
		for f in failures:
			log_line("  - %s" % f)
	var file := FileAccess.open(AUDIT_DIR + "logs/%s.log" % tag, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(_log_lines))
		file.close()
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)
