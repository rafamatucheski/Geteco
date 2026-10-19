extends RefCounted
## The meet has its own durable save. Campaign slots are never selected or copied.
const STORE := preload("res://runtime/SaveStore.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PATH := "user://GetecoV2/rachas/profile.json"

static func initial_snapshot() -> Dictionary:
	var state = load("res://runtime/GameState.gd").new()
	var intro: Dictionary = state.intro.snapshot()
	intro.phase="complete"
	intro.location_id="harbor_street"
	intro.inventory={}
	intro.completed_missions=[preload("res://data/GarageSequence.gd").ID]
	if not state.intro.restore_snapshot(intro): return {}
	state.region_id="desert"
	state.place_id=""
	state.checkpoint_id="desert_drag"
	var point := LAYOUT.drag_staging_point()+Vector3(0,.1,-6)
	state.world_state.time=.9
	state.world_state.weather=0
	state.world_state.drag_standalone={"version":1}
	state.world_state.pedestrian={"region":"desert","position":[point.x,point.y,point.z]}
	state.world_state.vehicles=[{"archetype":"desert_mirage","vehicle_id":"drag_profile_starter",
		"was_driven":true,"paint":"738997ff","position":[point.x,point.y,point.z],"yaw":-PI*.5,
		"health":float(FLEET.spec("desert_mirage").get("durability",180)),"region":"desert","equipment":{}}]
	# A fixed starting allowance lives only in this profile; reopening never pays it again.
	state.economy.grant_reward("drag_profile_start",2000)
	var snapshot: Dictionary=state.snapshot()
	return snapshot if load("res://runtime/GameState.gd").new().restore_snapshot(snapshot) else {}

static func prepare(launch: Node, path: String = PATH) -> Error:
	if path.is_empty() or path==STORE.PATH: return ERR_INVALID_PARAMETER
	var store := STORE.new()
	store.path=path
	var state = load("res://runtime/GameState.gd").new()
	var loaded: Dictionary=store.load_into(state)
	if loaded.ok:
		var marker: Variant=state.world_state.get("drag_standalone",{})
		if not marker is Dictionary or marker.get("version",0)!=1: return ERR_INVALID_DATA
	elif loaded.get("invalid",false):
		return ERR_FILE_CORRUPT
	else:
		var initial := initial_snapshot()
		if initial.is_empty(): return ERR_INVALID_DATA
		var error := store.publish_import_snapshot(initial)
		if error!=OK: return error
	launch.selected_path=path
	return OK
