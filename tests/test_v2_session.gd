extends SceneTree

const GAME_STATE := preload("res://runtime/GameState.gd")
const SAVE_STORE := preload("res://runtime/SaveStore.gd")
var failures: Array[String] = []
var world

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for i in 3: await physics_frame

func use_target(key: String) -> void:
	world.player.teleport(world.maciota_place.interaction_points[key] + Vector3.UP * .05)
	await settle()
	check(world.session.interact(), "Interaction " + key)
	while world.session.dialogue_open: world.session._advance_dialogue()

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 600:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		check(false, "Integrated session becomes playable")
		quit(1)
		return
	var session = world.session
	var state = session.state
	check(world.production.no_save, "Test requires --no-save")
	check(state.grant_weapon("pistol") and state.equip_weapon("pistol"), "Outdoor pistol equipped")
	check(await session.enter_place("maciota", false), "Physical garage entrance")
	check(state.place_id == "maciota" and world.camera.locked, "Garage camera locked")
	check(not state.can_attack() and not state.equip_weapon("pistol") and state.equipped_weapon == "fists", "Garage weapon restriction")
	await use_target("mechanic")
	check(state.intro.stage == "meet_maciota", "Order protected")
	await use_target("maciota")
	check(state.intro.stage == "talk_mechanic", "Maciota advances")
	await use_target("mechanic")
	check(state.intro.stage == "collect_part", "Mechanic advances")
	check(world.maciota_place.part_visual.visible, "Part now visible")
	await use_target("part")
	check(state.intro.snapshot().inventory.get("garage_part", 0) == 1, "Collect exactly one")
	check(not world.maciota_place.part_visual.visible, "Part removed")
	await use_target("maciota")
	check(state.intro.stage == "complete", "Complete mission")
	await use_target("maciota")
	check(state.intro.snapshot().completed_missions.size() == 1, "No duplicate reward")
	var save_root := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--isolated-save-root="): save_root = arg.trim_prefix("--isolated-save-root=").replace("\\", "/").trim_suffix("/")
	check(not save_root.is_empty(), "Isolated save directory supplied")
	if save_root.is_empty(): quit(1); return
	var store = SAVE_STORE.new()
	store.path = save_root.path_join("v2_session.json")
	check(store.save(state) == OK, "Save garage checkpoint")
	var loaded = GAME_STATE.new()
	check(store.load_into(loaded).get("ok", false), "Load garage checkpoint")
	check(loaded.place_id == "maciota" and loaded.intro.stage == "complete", "Loaded room and mission")
	check(not loaded.can_attack() and loaded.equipped_weapon == "fists" and loaded.owns_weapon("pistol"), "Loaded garage preserves inventory and weapon lock")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path))
	check(session.leave_place(), "Physical garage exit")
	check(state.place_id.is_empty() and not world.camera.locked, "Outdoor camera restored")
	check(state.can_attack() and state.equip_weapon("pistol"), "Outdoor weapon policy restored")
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	shape.shape = box
	block.add_child(shape)
	block.position = world.maciota_place.interior_spawn + Vector3.UP
	world.add_child(block)
	await settle()
	check(not await session.enter_place("maciota", false), "Occupied checkpoint rejected")
	check(state.place_id.is_empty(), "Failed transition preserves zone")
	block.queue_free()
	await settle()
	print("V2_SESSION ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	world.free()
	quit(0 if failures.is_empty() else 1)
