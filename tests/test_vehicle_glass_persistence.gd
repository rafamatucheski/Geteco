extends SceneTree
## Ida e volta pelo SaveStore e validação de esquema, independentes do vidro renderizado.
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const FLEET := preload("res://runtime/FleetState.gd")
const GARAGE := preload("res://runtime/GarageRewards.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	var record := {"archetype":"union_sedan","vehicle_id":"glass_fixture","region":"harbor","paint":"ffffffff","position":[0,0,0],"yaw":0.0,"health":50.0}
	check(FLEET.validate(record),"legacy vehicle without glass field remains valid")
	var broken := [{"point":[.7,1.2,0.0],"direction":[-1.0,0.0,0.0]}]
	record.broken_glass=broken.duplicate(true)
	check(FLEET.validate(record),"vehicle accepts localized broken pane records")
	var state := STATE.new()
	state.world_state.vehicles=[record.duplicate(true)]
	var garage_record := record.duplicate(true)
	garage_record.erase("region")
	garage_record.region_id="harbor"; garage_record.place_id="maciota"; garage_record.was_driven=false
	var garage := {"version":1,"port_status":"parked","alarm_remaining":-1.0,"police_called":false,"vehicles":{"garage_guest_1":garage_record}}
	check(GARAGE.validate_snapshot(garage),"garage validates a stored vehicle with broken glass")
	state.world_state.garage_rewards=garage
	var store := STORE.new()
	store.path="user://glass-persistence-%d/progress.json" % OS.get_process_id()
	check(store.save(state)==OK,"SaveStore writes actual isolated progress")
	var restored := STATE.new()
	check(store.load_into(restored).get("ok",false),"SaveStore loads actual isolated progress")
	if restored.world_state.vehicles.is_empty():
		quit(1)
		return
	check(restored.world_state.vehicles[0].broken_glass==broken,"world vehicle preserves broken panes through JSON")
	check(restored.world_state.garage_rewards.vehicles.garage_guest_1.broken_glass==broken,"garage vehicle preserves broken panes through JSON")
	# Um reparo seguinte é representado pela lista vazia de registros.
	restored.world_state.vehicles[0].broken_glass=[]
	check(store.save(restored)==OK,"repaired glass state can be saved")
	var repaired := STATE.new()
	check(store.load_into(repaired).get("ok",false) and repaired.world_state.vehicles[0].broken_glass.is_empty(),"repair does not resurrect prior damage after reload")
	for invalid in [null,{},[{"point":[0,0],"direction":[1,0,0]}],[{"point":[0,0,0],"direction":[0,0,0]}],[{"point":[0,NAN,0],"direction":[1,0,0]}]]:
		var bad := record.duplicate(true)
		bad.broken_glass=invalid
		check(not FLEET.validate(bad),"malformed glass cannot enter a fleet save")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(store.path+suffix): DirAccess.remove_absolute(store.path+suffix)
	DirAccess.remove_absolute(store.path.get_base_dir())
	print("VEHICLE_GLASS_PERSISTENCE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
