extends RefCounted
## O encontro tem save durável próprio. Os slots da campanha nunca são escolhidos nem copiados.
const STORE := preload("res://runtime/SaveStore.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PATH := "user://GetecoV2/rachas/profile.json"
const GAME_STATE := preload("res://runtime/GameState.gd")

static func initial_snapshot() -> Dictionary:
	var state = GAME_STATE.new()
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
	# Uma verba inicial fixa vive só neste perfil; reabrir nunca a paga de novo.
	state.economy.grant_reward("drag_profile_start",2000,"Verba inicial")
	var snapshot: Dictionary=state.snapshot()
	return snapshot if GAME_STATE.new().restore_snapshot(snapshot) else {}

static func prepare(launch: Node, path: String = PATH) -> Error:
	if path.is_empty() or path==STORE.PATH: return ERR_INVALID_PARAMETER
	var store := STORE.new()
	store.path=path
	var state = GAME_STATE.new()
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
