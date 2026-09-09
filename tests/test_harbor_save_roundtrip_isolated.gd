extends SceneTree

## Explicit, opt-in REAL-DISK test. Never uses autosave or the user's slots.
## Run rendered with -- --authorize-isolated-save after reviewing permission.
## Headless/fallback are refused: they cannot prove the real user save folder.
const GAME := preload("res://world/harbor/HarborGame.tscn")
var failures: Array[String] = []
var world: Node2D
var slot_id := ""
var absolute_slot := ""
var absolute_directory := ""
var write_attempted := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("ISOLATED_SAVE: " + message)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--authorize-isolated-save"):
		push_error("ISOLATED_SAVE refuses headless or missing explicit --authorize-isolated-save opt-in")
		quit(2)
		return
	var saves := root.get_node("SaveManager")
	check(str(saves.get("_save_dir")) == "user://saves/", "No temporary/fallback save directory is allowed")
	check(bool(saves.get("_save_directory_ready")), "Real save directory passed production write probe")
	if not failures.is_empty():
		await finish()
		return
	absolute_directory = ProjectSettings.globalize_path("user://saves/").simplify_path().trim_suffix("/")
	slot_id = "qa_harbor_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	absolute_slot = ProjectSettings.globalize_path(saves.get_slot_path(slot_id)).simplify_path()
	check(valid_owned_path(absolute_slot), "Generated path is exactly our new basename under the real save directory")
	check(not FileAccess.file_exists(absolute_slot) and not FileAccess.file_exists(absolute_slot+".tmp"), "Unique target and temporary file do not already exist")
	if not failures.is_empty():
		await finish()
		return
	print("ISOLATED_SAVE sole_target=", absolute_slot)
	saves.clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	world = GAME.instantiate()
	root.add_child(world)
	current_scene = world
	await frames(12)
	check(world.gameplay_ready and not paused, "Explicit production checkpoint is playable")
	var ledger: RefCounted = world.get_node("CobraCampaign").ledger
	ledger.data.aftermath = {"call_complete":true,"works_complete":true}
	# Segmented post-boss fixture, not a claim of full human campaign completion.
	for id in ledger.MISSION_IDS:
		ledger.rest_until_next_day(false)
		check(ledger.start_mission(id) and ledger.complete_mission(id), "Prepare completed fixture " + id)
	var reward := world.get_node("CobraBossReward")
	reward.sync_reward()
	await frames(4)
	check(is_instance_valid(reward.reward_car), "Victory reward exists before saving")
	if not failures.is_empty():
		await finish()
		return
	var car: CharacterBody2D = reward.reward_car
	car.repaint_vehicle(Color("4c6d89"))
	car.health = 61
	var player: CharacterBody2D = world.get_node("Player")
	var expected_position := car.global_position + Vector2(0,65)
	player.global_position = expected_position
	player.health = 73
	player.armor = 11
	await frames(4)
	reward.capture_snapshot()
	check(not FileAccess.file_exists(absolute_slot) and not FileAccess.file_exists(absolute_slot+".tmp"), "Own target remains absent immediately before writing")
	if not failures.is_empty():
		await finish()
		return
	write_attempted = true
	var result: Dictionary = saves.save_game(slot_id, "Isolated Harbor QA; safe to remove this generated slot")
	check(bool(result.get("success",false)), "Production save_game writes atomically: " + str(result.get("error","")))
	check(FileAccess.file_exists(absolute_slot), "Actual slot exists on disk")
	if not failures.is_empty():
		await finish()
		return
	var file := FileAccess.open(absolute_slot,FileAccess.READ)
	check(file != null, "Real disk slot can be reopened")
	if file == null:
		await finish()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	check(parsed is Dictionary and str(parsed.get("slot_id","")) == slot_id, "Disk JSON identifies only the generated QA slot")
	check(not FileAccess.file_exists(absolute_slot+".tmp"), "Atomic write left no temporary file")
	player.health = 29
	player.global_position += Vector2(100,0)
	car.repaint_vehicle(Color.RED)
	car.health = 12
	ledger.data.aftermath.works_complete = false
	var loaded: Dictionary = saves.load_game(slot_id)
	check(bool(loaded.get("success",false)) and saves.has_pending_save(), "Production load_game reads disk and stages pending restore")
	if not failures.is_empty():
		await finish()
		return
	world.queue_free()
	await frames(4)
	world = GAME.instantiate()
	root.add_child(world)
	current_scene = world
	await frames(16)
	check(world.loaded_from_save and world.gameplay_ready and not saves.has_pending_save(), "Fresh world consumed pending restore through Player's existing deferred flow")
	player = world.get_node("Player")
	check(player.health == 73 and player.armor == 11, "Player health and armor survive actual disk roundtrip")
	check(player.global_position.distance_to(expected_position) < 1.0, "Player position survives inside the real garage")
	reward = world.get_node("CobraBossReward")
	check(is_instance_valid(reward.reward_car), "Saved reward is reconstructed")
	if is_instance_valid(reward.reward_car):
		check(reward.reward_car.health == 61 and reward.reward_car.paint_color.is_equal_approx(Color("4c6d89")), "Reward damage and paint survive real disk roundtrip")
	var count := 0
	for vehicle in get_nodes_in_group("vehicle"):
		if str(vehicle.get_meta("campaign_reward_id","")) == "cobra_boss_ironback":
			count += 1
	check(count == 1, "Exactly one boss reward exists after scene recreation")
	check(world.get_node("CobraAftermath").get_status().phase == "done", "Completed epilogue does not replay after loading disk")
	await finish()

func valid_owned_path(path: String) -> bool:
	return not slot_id.is_empty() and slot_id.begins_with("qa_harbor_") and path.is_absolute_path() and path.get_base_dir().simplify_path() == absolute_directory and path.get_file() == slot_id+".json"

func cleanup_owned_file(path: String) -> void:
	if not write_attempted or not FileAccess.file_exists(path):
		return
	var target := path.trim_suffix(".tmp")
	if not valid_owned_path(target) or path not in [absolute_slot,absolute_slot+".tmp"]:
		print("ISOLATED_SAVE retained unsafe cleanup target: ", path)
		return
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		print("ISOLATED_SAVE retained unreadable QA file: ", path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or str(parsed.get("slot_id","")) != slot_id:
		print("ISOLATED_SAVE retained unverified QA file: ", path)
		return
	var error := DirAccess.remove_absolute(path)
	check(error == OK, "Only our verified generated file is removed: " + path)
	print("ISOLATED_SAVE cleanup=", error, " path=", path)

func finish() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(4)
	cleanup_owned_file(absolute_slot)
	cleanup_owned_file(absolute_slot+".tmp")
	print("ISOLATED_SAVE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
