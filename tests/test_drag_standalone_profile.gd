extends SceneTree
const PROFILE := preload("res://runtime/desert/DragStandaloneProfile.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var failures: Array[String]=[]
var checks:=0
class Launch extends Node:
	var selected_path: String="campaign-sentinel"
func check(ok: bool, label: String) -> void:
	checks+=1
	print("DRAG_PROFILE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var data:=PROFILE.initial_snapshot()
	check(not data.is_empty() and STATE.new().restore_snapshot(data),"standalone checkpoint uses productive save schema")
	if data.is_empty():
		quit(1)
		return
	check(STATE.new().restore_snapshot(JSON.parse_string(JSON.stringify(data))),"dedicated marker and checkpoint survive JSON numeric types")
	var campaign_only:=data.duplicate(true)
	campaign_only.world.erase("drag_standalone")
	check(not STATE.new().restore_snapshot(campaign_only),"normal campaign still rejects desert before its final mission")
	var malformed:=data.duplicate(true)
	malformed.world.drag_standalone={"version":2}
	check(not STATE.new().restore_snapshot(malformed),"unknown dedicated mode version is rejected")
	check(not preload("res://world/north_gateway/NorthGatewayPolicy.gd").campaign_completed(data.campaign),"dedicated mode never opens the construction bridge")
	check(data.region_id=="desert" and data.place_id.is_empty(),"starts outdoors at the meet")
	check(data.campaign.completed.is_empty(),"campaign missions and bridge unlock are untouched")
	check(data.world.vehicles.size()==1 and data.world.vehicles[0].was_driven,"starter is ready to drive")
	check(data.economy.balance==2000,"one fixed starting allowance")
	var launch:=Launch.new()
	root.add_child(launch)
	var folder: String="user://test-fixtures/drag-profile-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var path:=folder.path_join("profile.json")
	var main_before:=FileAccess.get_sha256(STORE.PATH) if FileAccess.file_exists(STORE.PATH) else "absent"
	check(PROFILE.prepare(launch,path)==OK,"creates only the requested isolated profile")
	check(launch.selected_path==path,"launch selects the standalone path")
	var state:=STATE.new()
	var store:=STORE.new()
	store.path=path
	check(store.load_into(state).ok,"profile reloads through SaveStore")
	state.economy.grant_reward("drag_profile_test",123)
	check(store.save(state)==OK,"progress persists to the isolated profile")
	check(PROFILE.prepare(launch,path)==OK,"reopening resumes the existing profile")
	check(STORE.read_valid(path).economy.balance==2123,"reopening neither resets nor duplicates allowance")
	var corrupt:=folder.path_join("corrupt.json")
	var file:=FileAccess.open(corrupt,FileAccess.WRITE)
	file.store_string("preserve this incomplete file")
	file.close()
	var fingerprint:=FileAccess.get_sha256(corrupt)
	launch.selected_path="campaign-sentinel"
	check(PROFILE.prepare(launch,corrupt)==ERR_FILE_CORRUPT,"invalid profile is not overwritten")
	check(FileAccess.get_sha256(corrupt)==fingerprint and launch.selected_path=="campaign-sentinel","failed opening preserves bytes and selected campaign")
	check(PROFILE.prepare(launch,STORE.PATH)==ERR_INVALID_PARAMETER,"primary campaign path cannot become racing profile")
	var main_after:=FileAccess.get_sha256(STORE.PATH) if FileAccess.file_exists(STORE.PATH) else "absent"
	check(main_before==main_after,"personal campaign save was not written")
	print("DRAG_PROFILE_DONE checks=",checks," failures=",failures," fixture=",folder)
	launch.queue_free()
	quit(0 if failures.is_empty() else 1)
