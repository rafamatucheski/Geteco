extends SceneTree

const Progression := preload("res://systems/Progression.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_flow()
	_validation()
	_weapons()
	_persistence()
	if failures.is_empty():
		print("PASS progression: %d checks" % checks)
	else:
		for message in failures:
			push_error(message)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _flow() -> void:
	var state := Progression.new()
	_check(not state.interact("maciota").ok, "Cannot speak remotely from street")
	state.set_location("harbor_garage")
	_check(not state.interact("workbench").ok, "Cannot collect before request")
	state.interact("mechanic")
	_check(state.stage == "meet_maciota", "Mechanic cannot skip introduction")
	_check(state.interact("maciota").changed, "Introduction advances")
	_check(not state.interact("maciota").changed, "Repeated greeting is idempotent")
	state.interact("mechanic")
	_check(state.part_available, "Mechanic unlocks part")
	state.interact("workbench")
	_check(state.snapshot().inventory.get("garage_part") == 1, "Picking up adds one part")
	_check(not state.interact("workbench").changed, "Cannot duplicate collected part")
	state.set_location("harbor_street")
	_check(not state.interact("maciota").ok, "Return requires entering garage")
	state.set_location("harbor_garage")
	state.interact("maciota")
	_check(state.stage == "complete", "Sequence completes")
	_check(not state.snapshot().inventory.has("garage_part"), "Hand-in consumes part")
	state.interact("maciota")
	_check(state.snapshot().completed_missions.size() == 1, "Completion cannot duplicate")
	_check(not state.interact("unknown").ok, "Unknown interaction refused")
	_check(state.set_location("harbor_street"), "Exit always possible after completion")
	var detached := state.snapshot()
	detached.inventory["pistol"] = 2
	_check(state.snapshot().inventory.is_empty(), "Snapshot does not expose mutable state")

func _validation() -> void:
	var state := Progression.new()
	var original := state.snapshot()
	var changes := [
		{"schema_version": 2}, {"schema_version": "1"}, {"schema_version": 1.5},
		{"game": "geteco"}, {"mission_id": "harbor_arrival"}, {"phase": "unknown"},
		{"phase": []}, {"location_id": "unknown"}, {"inventory": []},
		{"inventory": {"pistol": -1}}, {"inventory": {"pistol": 0.5}},
		{"inventory": {"pistol": true}}, {"inventory": {"pistol": 1000}},
		{"inventory": {"unknown": 1}}, {"inventory": {"garage_part": 1}},
		{"equipped_weapon": "pistol"}, {"completed_missions": ["harbor_arrival_v2"]},
		{"phase": "complete"}, {"phase": "return_maciota"},
	]
	for change in changes:
		var invalid := original.duplicate(true)
		invalid.merge(change, true)
		_check(not state.restore_snapshot(invalid), "Invalid save rejected: " + str(change))
		_check(state.snapshot() == original, "Rejected restore leaves current session intact")
	_check(not state.restore_snapshot({}), "Missing schema rejected")
	_check(not state.set_location("invented"), "Unknown location rejected")
	_check(state.snapshot() == original, "Rejected location leaves state intact")

func _weapons() -> void:
	var state := Progression.new()
	var armed := state.snapshot()
	armed.inventory = {"pistol": 1, "knife": 1, "grenade": 2}
	armed.equipped_weapon = "pistol"
	_check(state.restore_snapshot(armed), "Armed street state supported")
	_check(state.can_attack(), "Street allows future attack consumers")
	state.set_location("harbor_garage")
	_check(state.snapshot().equipped_weapon == "", "Entry holsters automatically")
	_check(state.snapshot().inventory == armed.inventory, "Entry preserves inventory")
	for weapon in ["pistol", "knife", "grenade"]:
		_check(not state.equip_weapon(weapon), "Garage rejects weapon: " + weapon)
	_check(not state.can_attack(), "Garage blocks attack gate including unarmed melee")
	armed.location_id = "harbor_garage"
	_check(state.restore_snapshot(armed), "Garage restore accepted")
	_check(state.snapshot().equipped_weapon == "" and not state.can_attack(), "Restore reapplies safety from location")
	state.set_location("harbor_street")
	_check(state.equip_weapon("pistol") and state.can_attack(), "Exit releases equipment and attacks")
	_check(not state.equip_weapon("rifle"), "Cannot equip an unowned weapon")

func _persistence() -> void:
	# Unique directory: never read or alter the player's progress file.
	var directory := "user://GetecoV2/tests/progression_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var path := directory + "/progress.json"
	var state := Progression.new()
	_check(state.load_game(path).status == "missing", "Absent save handled")
	_check(state.save_game(path) == OK, "First atomic save")
	state.set_location("harbor_garage")
	state.interact("maciota")
	state.interact("mechanic")
	state.interact("workbench")
	_check(state.save_game(path) == OK, "Second save creates backup")
	var restored := Progression.new()
	_check(restored.load_game(path).status == "loaded", "Save loads")
	_check(restored.snapshot() == state.snapshot(), "Progress, location and inventory roundtrip")
	_check(not restored.can_attack(), "Disk restore enforces garage restriction")
	var backup_text := FileAccess.get_file_as_string(path + ".bak")
	_write(path, "{broken")
	_check(restored.load_game(path).status == "recovered_backup", "Corrupt primary recovers backup")
	_check(restored.stage == "meet_maciota", "Backup restores previous checkpoint")
	_check(FileAccess.get_file_as_string(path + ".bak") == backup_text, "Recovery preserves backup bytes")
	_check(restored.save_game(path) == OK, "Can save after recovery")
	_check(FileAccess.get_file_as_string(path + ".bak") == backup_text, "Corrupt primary never rotates into backup")
	# Crash between rotation and promotion: backup must remain recoverable.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(restored.load_game(path).status == "recovered_backup", "Missing primary recovers valid backup")
	_write(path, "[]")
	_write(path + ".bak", "bad backup")
	var before := restored.snapshot()
	_check(restored.load_game(path).status == "invalid", "Both corrupt saves reported without crash")
	_check(restored.snapshot() == before, "Both corrupt leave in-memory state intact")
	_check(FileAccess.get_file_as_string(path + ".bak") == "bad backup", "Load never destroys corrupt backup")
	var future := before.duplicate(true)
	future.schema_version = 999
	_write(path, JSON.stringify(future))
	_check(restored.load_game(path).status == "invalid", "Future schema not silently accepted")
	_write(path, "x".repeat(Progression.MAX_BYTES + 1))
	_check(restored.load_game(path).status == "invalid", "Oversized input rejected")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Test fixture can be written")
	if file != null:
		file.store_string(content)
		file.close()
