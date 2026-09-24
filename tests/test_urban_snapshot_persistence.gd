extends SceneTree
## Central port/cemetery persistence contract. Never opens user:// and requires
## an absolute unique directory below OS.get_temp_dir().

const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: _run()

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print(("URBAN_SAVE PASS " if ok else "URBAN_SAVE FAIL ") + label + ((" | " + detail) if not detail.is_empty() else ""))
	if not ok:
		failures.append(label)
		push_error(label + ((" | " + detail) if not detail.is_empty() else ""))

func isolated_root() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--isolated-save-root="): return arg.trim_prefix("--isolated-save-root=").replace("\\", "/").trim_suffix("/")
	return ""

func canonical(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().to_lower()

func urban_fixture() -> Dictionary:
	return {
		"version":1,
		"port":{"version":1,"boats":[
			{"id":"south_port_launch_00","load":0,"phase":"loading","clock":2.5,"position":[0.0,0.0,0.0],"worker":{}},
			{"id":"south_port_launch_01","load":0,"phase":"loading","clock":4.0,"position":[8.0,0.0,0.0],"worker":{}},
		]},
		"cemetery":{"version":1,"serial":2,"secret_known":true,"storyteller_stop":1,"cases":[
			{"identity":"synthetic:morgue","name":"Caso Morgue","phase":"morgue","plot":-1},
			{"identity":"synthetic:buried","name":"Caso Sepultado","phase":"buried","plot":0},
		]},
	}

func equivalent(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _run() -> void:
	var directory := isolated_root()
	var temp := canonical(OS.get_temp_dir()).trim_suffix("/") + "/"
	var resolved := canonical(directory).trim_suffix("/") + "/"
	if directory.is_empty() or not directory.is_absolute_path() or not resolved.begins_with(temp) or resolved == temp:
		push_error("URBAN_SAVE refuses storage outside a unique OS temp directory: " + directory)
		quit(2)
		return

	var previous_v2 = STATE.new()
	var previous_snapshot: Dictionary = JSON.parse_string(JSON.stringify(previous_v2.snapshot()))
	check(not previous_snapshot.world.has("urban_operations"), "fixture representa save V2 anterior")
	var previous_loaded = STATE.new()
	check(previous_loaded.restore_snapshot(previous_snapshot), "save V2 anterior sem estado urbano continua compatível")

	var fixture := urban_fixture()
	var live = STATE.new()
	live.economy.grant_reward("urban_snapshot_guard", 37)
	live.world_state.urban_operations = fixture.duplicate(true)
	var valid_snapshot: Dictionary = JSON.parse_string(JSON.stringify(live.snapshot()))
	var restored = STATE.new()
	check(restored.restore_snapshot(valid_snapshot), "snapshot completo de porto e cemitério é aceito")
	check(equivalent(restored.world_state.urban_operations, fixture), "restauração não perde dados urbanos")

	var stable_before: Dictionary = restored.snapshot()
	var partial: Dictionary = valid_snapshot.duplicate(true)
	partial.world.urban_operations.erase("cemetery")
	partial.economy.balance = 9999
	check(not restored.restore_snapshot(partial), "snapshot parcial é rejeitado")
	check(equivalent(restored.snapshot(), stable_before), "rejeição parcial não altera o estado vivo")

	var invalid_case: Dictionary = valid_snapshot.duplicate(true)
	invalid_case.world.urban_operations.cemetery.cases[1].plot = -1
	check(not restored.restore_snapshot(invalid_case), "cemitério inconsistente é rejeitado centralmente")
	check(equivalent(restored.snapshot(), stable_before), "cemitério inválido não produz restauração parcial")

	var previous_store = STORE.new()
	previous_store.path = directory.path_join("previous_v2.json")
	check(previous_store.path != STORE.PATH and previous_store.save(previous_v2) == OK, "save anterior usa somente armazenamento isolado")
	var previous_disk = STATE.new()
	check(previous_store.load_into(previous_disk).get("ok", false), "save anterior atravessa o armazenamento isolado")

	var store = STORE.new()
	store.path = directory.path_join("urban_v2.json")
	check(store.path != STORE.PATH and store.save(live) == OK, "snapshot urbano completo é publicado isoladamente")
	var disk = STATE.new()
	var result: Dictionary = store.load_into(disk)
	check(result.get("ok", false) and equivalent(disk.world_state.urban_operations, fixture), "porto e cemitério voltam completos do disco")
	var valid_on_disk: Dictionary = STORE.read_valid(store.path)
	live.world_state.urban_operations = {"version":1,"port":fixture.port.duplicate(true)}
	check(store.save(live) == ERR_INVALID_DATA, "SaveStore recusa publicar estado urbano parcial")
	check(equivalent(STORE.read_valid(store.path), valid_on_disk), "falha de publicação preserva o último snapshot completo")

	print("URBAN_SNAPSHOT_ROOT ", resolved)
	print("URBAN_SNAPSHOT_PERSISTENCE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
