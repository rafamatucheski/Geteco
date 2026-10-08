extends SceneTree
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var folder := FIXTURE.output_dir("armored-save")
	var snapshot := FIXTURE.full_snapshot(Vector3(42,0,20),true)
	check(STATE.new().restore_snapshot(snapshot),"Existing saves without armored state still load")
	var event := SCHEDULE.initial(SCHEDULE.departure(3,14.0/24.0),3)
	event.hostile = true
	event.escalated = true
	event.phase = "finished"
	event.opened = [true,true]
	event.taken = [true,true]
	event.secured = [true,true]
	snapshot.world.armored_transport = {"version":1,"last_event":event.id,"security_level":4,"event":event}
	var state := STATE.new()
	check(state.restore_snapshot(snapshot),"Completed robbery restores separate current and future security levels")
	var store := STORE.new()
	store.path = folder.path_join("checkpoint.json")
	check(store.path != STORE.PATH and store.save(state) == OK,"Checkpoint written through real SaveStore to isolated evidence path")
	var restored := STATE.new()
	check(store.load_into(restored).get("ok",false),"Real JSON checkpoint loads")
	check(restored.world_state.armored_transport.security_level == 4,"Future convoy preparation persists")
	check(restored.world_state.armored_transport.event.secured == [true,true],"Secured cargo remains consumed")
	var before := restored.snapshot()
	var corrupt := snapshot.duplicate(true)
	corrupt.world.armored_transport.security_level = -1
	check(not restored.restore_snapshot(corrupt),"Invalid escalation rejected")
	check(restored.snapshot() == before,"Rejected convoy snapshot does not mutate live state")
	corrupt = snapshot.duplicate(true)
	corrupt.world.armored_transport.event.pending = 80000
	check(not restored.restore_snapshot(corrupt),"Finished event cannot resurrect carried cash")
	print("ARMORED_SAVE: %d checks; failures=%d; evidence=%s" % [checks,failures,folder])
	quit(1 if failures else 0)
