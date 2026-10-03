extends SceneTree
## Pure persistence contract; no Main, rendering, timings or personal save path.
## Select baseline/candidate with --store-script=res://path/to/SaveStore.gd.
const STATE := preload("res://runtime/GameState.gd")
const BASE_STORE := preload("res://runtime/SaveStore.gd")
var StoreScript: Script
var checks := 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []
var root_path := ""

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ",label)

func _store(folder: String):
	var store = StoreScript.new()
	store.path = root_path+"/"+folder+"/progress.json"
	return store

func _files(folder: String) -> Dictionary:
	var result := {}
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)): return result
	for name_value in DirAccess.get_files_at(folder):
		var file_path := folder.path_join(name_value)
		var file := FileAccess.open(file_path,FileAccess.READ)
		result[name_value] = {"bytes":file.get_length(),"sha256":FileAccess.get_sha256(file_path)}
		file.close()
	return result

func _write_snapshot(path_value: String, data: Dictionary) -> void:
	var file := FileAccess.open(path_value,FileAccess.WRITE)
	check(file!=null,"fixture can prepare isolated recovery file")
	if file:
		file.store_buffer(JSON.stringify(data,"\t").to_utf8_buffer())
		file.close()

func _prepared_store(label: String):
	var store = _store(label)
	var state = STATE.new()
	check(state.economy.grant_reward("first_ação_界",20) and store.save(state)==OK,label+": first valid save")
	var first: Dictionary = state.snapshot()
	check(state.economy.grant_reward("second_ação_界",30) and store.save(state)==OK,label+": second valid save creates backup")
	_write_snapshot(store.path+".tmp",first)
	check(not BASE_STORE.read_valid(store.path).is_empty() and not BASE_STORE.read_valid(store.path+".bak").is_empty() and not BASE_STORE.read_valid(store.path+".tmp").is_empty(),label+": primary, backup and temporary are valid before rejection")
	return store

func _reject_unchanged(store, state, label: String) -> void:
	var folder: String = store.path.get_base_dir()
	var before := _files(folder)
	var state_before: Dictionary = state.snapshot()
	var backup_flag: bool = store.recovered_backup
	var temp_flag: bool = store.recovered_temp
	var result: int = store.save(state)
	var after := _files(folder)
	check(result!=OK,label+": oversized UTF-8 snapshot rejected")
	check(after==before,label+": filenames, primary, backup and temporary bytes unchanged")
	check(store.recovered_backup==backup_flag and store.recovered_temp==temp_flag,label+": recovery flags unchanged after rejection")
	check(state.snapshot()==state_before,label+": caller state unchanged")
	cases.append({"name":label,"error":result,"before_files":before,"after_files":after,
		"encoded_bytes":JSON.stringify(state_before,"\t").to_utf8_buffer().size(),"recovered_backup_before":backup_flag,"recovered_temp_before":temp_flag})

func _large_unicode_state():
	var state = STATE.new()
	var prepared := true
	for index in range(4000):
		prepared = state.economy.grant_reward("unicode_%04d_"%index+"界".repeat(90),0) and prepared
	check(prepared,"large Unicode history built via public APIs below receipt count limit")
	var data: Dictionary = state.snapshot()
	var encoded := JSON.stringify(data,"\t")
	check(STATE.new().restore_snapshot(data),"large Unicode history is structurally valid")
	check(encoded.length()<BASE_STORE.MAX_BYTES and encoded.to_utf8_buffer().size()>BASE_STORE.MAX_BYTES,"Unicode counterexample is below character limit but above byte limit")
	return state

func _exact_limit() -> void:
	var state = STATE.new()
	state.world_state["save_boundary_payload"] = ""
	var overhead := JSON.stringify(state.snapshot(),"\t").to_utf8_buffer().size()
	# World extension values are retained by GameState; only fill this fixture's
	# field so the actual serialized UTF-8 size is exactly the reader boundary.
	state.world_state.save_boundary_payload = "x".repeat(BASE_STORE.MAX_BYTES-overhead)
	var encoded := JSON.stringify(state.snapshot(),"\t").to_utf8_buffer()
	check(encoded.size()==BASE_STORE.MAX_BYTES and STATE.new().restore_snapshot(state.snapshot()),"exact-limit control has a valid 2 MiB snapshot")
	var store = _store("exact_limit")
	check(store.save(state)==OK,"exactly 2 MiB remains accepted")
	check(FileAccess.get_file_as_bytes(store.path)==encoded,"valid save writes exactly the serialized UTF-8 bytes")
	var loaded = STATE.new()
	var load_ok: bool = bool(store.load_into(loaded).get("ok",false))
	# JSON parses numbers as floats; compare both snapshots in that same numeric
	# representation, retaining every key and value, including the full payload.
	var strict_equal: bool = loaded.snapshot()==state.snapshot()
	var json_equal: bool = JSON.parse_string(JSON.stringify(loaded.snapshot()))==JSON.parse_string(JSON.stringify(state.snapshot()))
	cases.append({"name":"exact_limit_roundtrip","load_ok":load_ok,"strict_variant_equal":strict_equal,"json_values_equal":json_equal})
	check(load_ok and json_equal,"exact-limit save roundtrips all JSON state")
	state.world_state.save_boundary_payload += "x"
	check(JSON.stringify(state.snapshot(),"\t").to_utf8_buffer().size()==BASE_STORE.MAX_BYTES+1,"one-byte overflow is exact")
	_reject_unchanged(store,state,"one_byte_overflow")

func _valid_recovery() -> void:
	var store = _prepared_store("valid_recovery")
	var state = STATE.new()
	check(bool(store.load_into(state).get("ok",false)) and state.economy.balance==50,"valid primary still wins over older temporary")
	check(state.economy.grant_reward("new_😀_recibo",5),"valid Unicode reward accepted")
	check(store.save(state)==OK,"valid save still preserves abandoned temporary and rotates backup")
	var loaded = STATE.new()
	check(bool(store.load_into(loaded).get("ok",false)) and loaded.economy.balance==55,"valid Unicode save roundtrips")
	var files := _files(store.path.get_base_dir())
	var preserved := 0
	for name_value in files:
		if str(name_value).begins_with("progress.json.tmp.preserved."): preserved += 1
	check(preserved==1 and FileAccess.file_exists(store.path+".bak") and not FileAccess.file_exists(store.path+".tmp"),"normal recovery evidence and backup semantics preserved")
	var bytes := FileAccess.get_file_as_bytes(store.path)
	check(bytes==JSON.stringify(state.snapshot(),"\t").to_utf8_buffer(),"normal Unicode encoding is unchanged")

func run() -> void:
	var script_path := "res://runtime/SaveStore.gd"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--store-script="): script_path=argument.trim_prefix("--store-script=")
	StoreScript = load(script_path)
	check(StoreScript!=null,"selected SaveStore implementation loads")
	if StoreScript==null:
		quit(1)
		return
	root_path="user://tests/save_store_byte_preflight_%d"%Time.get_ticks_usec()
	var large = _large_unicode_state()
	var normal = _prepared_store("oversized_normal")
	_reject_unchanged(normal,large,"oversized_normal")
	var recovering = _prepared_store("oversized_recovering")
	check(DirAccess.rename_absolute(ProjectSettings.globalize_path(recovering.path),ProjectSettings.globalize_path(recovering.path+".kept"))==OK,"temporary-recovery fixture preserves old primary under an evidence filename")
	recovering.recovered_temp=true
	_reject_unchanged(recovering,large,"oversized_recovering")
	var backup = _prepared_store("oversized_backup")
	backup.recovered_backup=true
	_reject_unchanged(backup,large,"oversized_backup")
	var fresh = _store("fresh_uncreated")
	_reject_unchanged(fresh,large,"oversized_fresh")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(fresh.path.get_base_dir())),"oversized fresh save does not create storage directory")
	_exact_limit()
	_valid_recovery()
	var file := FileAccess.open("user://save-store-byte-preflight.json",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"implementation":script_path,"checks":checks,"failures":failures,"cases":cases,
			"temporary_directory":ProjectSettings.globalize_path(root_path),"max_bytes":BASE_STORE.MAX_BYTES},"\t"))
		file.close()
	else: check(false,"evidence JSON written")
	print("SAVE_STORE_BYTE_PREFLIGHT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
