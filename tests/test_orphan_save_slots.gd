extends SceneTree
## Real slot listing, menu buttons and disk persistence; every slot is isolated.
class IsolatedLaunch extends "res://runtime/SessionLaunch.gd":
	var folder := ""
	func slot_path(id: String) -> String:
		return folder.path_join(id+".json") if id in ["progress"]+SLOT_IDS else ""

class FailingArchiveLaunch extends IsolatedLaunch:
	func _archive_temporary(_source: String, _destination: String) -> Error:
		return ERR_FILE_CANT_WRITE

const STORE := preload("res://runtime/SaveStore.gd")
const STATE := preload("res://runtime/GameState.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): print("ORPHAN_SLOT timeout"); quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("ORPHAN_SLOT ","PASS " if ok else "FAIL ",label)
func write(path: String, bytes: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(bytes)
	file.close()
func row(launch, id: String) -> Dictionary:
	for item in launch.list_slots():
		if item.id == id: return item
	return {}
func run() -> void:
	var launch := IsolatedLaunch.new()
	launch.folder = "user://tests/orphan_slots_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(launch.folder))
	launch.name = "V2Launch"
	launch.direct_start_consumed = true
	var previous := root.get_node("V2Launch")
	root.remove_child(previous)
	previous.free()
	root.add_child(launch)
	var valid := JSON.stringify(STATE.new().snapshot())
	var broken := "{ interrupted save: preserve these exact bytes"
	write(launch.slot_path("slot_01")+".tmp",broken)
	write(launch.slot_path("slot_02")+".tmp",valid)
	write(launch.slot_path("slot_03"),valid)
	write(launch.slot_path("slot_03")+".tmp",broken)
	write(launch.slot_path("slot_04")+".bak",valid)
	write(launch.slot_path("slot_04")+".tmp",broken)
	write(launch.slot_path("slot_05"),broken)
	write(launch.slot_path("slot_05")+".tmp",broken)
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	menu._show_slots(true)
	var buttons: Array[Node] = menu.get_node("%SlotListContainer").get_children()
	check(buttons.size()==5,"new-game menu offers all five isolated slots")
	check(not buttons[0].disabled,"orphan invalid temporary permits selecting new game")
	for index in range(1,5): check(buttons[index].disabled,"existing primary backup or valid temporary remains protected: slot %d"%(index+1))
	check(not row(launch,"slot_01").valid,"invalid temporary is never offered as loadable progress")
	check(launch.prepare("slot_01",false)==ERR_FILE_CORRUPT,"loading invalid temporary is rejected")
	check(launch.prepare("slot_01",true)==OK,"new game can reuse orphan invalid temporary slot")
	var archived: Array[String] = []
	for name_value in DirAccess.get_files_at(launch.folder):
		if name_value.begins_with("slot_01.json.tmp.corrupt."): archived.append(name_value)
	check(archived.size()==1 and FileAccess.get_file_as_string(launch.folder.path_join(archived[0]))==broken,"original invalid bytes are preserved in a diagnostic file")
	check(not FileAccess.file_exists(launch.slot_path("slot_01")+".tmp"),"orphan temporary no longer occupies the slot")
	write(launch.slot_path("slot_01")+".tmp",broken+" second")
	check(launch.prepare("slot_01",true)==OK,"a second interrupted attempt can reuse the same slot")
	var preserved_bytes: Array[String] = []
	for name_value in DirAccess.get_files_at(launch.folder):
		if name_value.begins_with("slot_01.json.tmp.corrupt."): preserved_bytes.append(FileAccess.get_file_as_string(launch.folder.path_join(name_value)))
	check(preserved_bytes.size()==2 and broken in preserved_bytes and broken+" second" in preserved_bytes,"two failed attempts retain separate exact diagnostic contents")
	var store = STORE.new()
	store.path = launch.slot_path("slot_01")
	check(store.save(STATE.new())==OK and store.load_into(STATE.new()).get("ok",false),"reused slot accepts a real new save and cold reload")
	for id in ["slot_02","slot_03","slot_04","slot_05"]:
		var before := FileAccess.get_sha256(launch.slot_path(id)+".tmp")
		check(launch.prepare(id,true)==ERR_ALREADY_EXISTS and FileAccess.get_sha256(launch.slot_path(id)+".tmp")==before,"refused overwrite leaves recovery bytes intact: "+id)
	check(launch.prepare("slot_02",false)==OK and row(launch,"slot_02").temporary,"valid temporary remains recoverable")
	check(launch.prepare("slot_04",false)==OK and row(launch,"slot_04").backup,"valid backup still wins over invalid temporary")
	var failing := FailingArchiveLaunch.new()
	failing.folder = launch.folder.path_join("archive_failure")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(failing.folder))
	write(failing.slot_path("slot_01")+".tmp",broken)
	var previous_selection := failing.selected_path
	check(failing.prepare("slot_01",true)==ERR_FILE_CANT_WRITE,"archive failure refuses new game")
	check(failing.selected_path==previous_selection and FileAccess.get_file_as_string(failing.slot_path("slot_01")+".tmp")==broken,"archive failure preserves bytes and previous selection")
	failing.free()
	launch.folder = launch.folder.path_join("empty")
	check(launch.prepare("slot_01",true)==OK,"empty slot remains selectable")
	check(launch.prepare("progress",true)==ERR_ALREADY_EXISTS,"legacy progress never becomes a new-game destination")
	menu.free()
	await process_frame
	print("ORPHAN_SLOT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
