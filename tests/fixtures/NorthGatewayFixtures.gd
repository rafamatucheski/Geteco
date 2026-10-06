extends RefCounted
## Isolated, valid checkpoints for the gateway tests. These are fixtures, not
## evidence that a test played the preceding missions or drove the final race.
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const CAMPAIGN := preload("res://systems/campaign/CampaignRuntime.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")

static func prefix(count: int, legacy := false) -> Dictionary:
	var data: Dictionary = CAMPAIGN.new().snapshot()
	var order: Array = MISSIONS.LEGACY_ORDER if legacy else MISSIONS.ORDER
	data.version = 1 if legacy else 2
	for index in mini(count,order.size()):
		var id: String = order[index]
		data.completed.append(id)
		data.pending_rewards[id] = int(MISSIONS.MISSIONS[id].reward)
		for flag in MISSIONS.MISSIONS[id].sets_flags: data.flags[flag] = true
	return data

static func before_document(legacy_migrated := false) -> Dictionary:
	var runtime = CAMPAIGN.new()
	var order: Array = MISSIONS.LEGACY_ORDER if legacy_migrated else MISSIONS.ORDER
	var restored: bool = runtime.restore_snapshot(prefix(order.size()-1,legacy_migrated))
	assert(restored)
	if not restored: return {}
	var data: Dictionary = runtime.snapshot()
	data.active_id = str(MISSIONS.ORDER.back())
	data.step = 7
	assert(CAMPAIGN.validate_snapshot(data))
	return data

static func final_event(runtime) -> Dictionary:
	return runtime.apply_event("transfer_document_collected",{
		"target_id":"transfer_document","on_foot":true,"place_id":"cobra_leader_house"})

static func full_snapshot(point: Vector3, completed := false, old_save := false) -> Dictionary:
	var state = STATE.new()
	var intro: Dictionary = state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	var intro_restored: bool = state.intro.restore_snapshot(intro)
	assert(intro_restored)
	if not intro_restored: return {}
	state.world_state.time = .45
	state.world_state.weather = 0
	state.world_state.pedestrian = {"region":"harbor","position":[point.x,point.y,point.z]}
	var campaign_restored: bool = state.campaign.restore_snapshot(before_document(true))
	assert(campaign_restored)
	if not campaign_restored: return {}
	if completed:
		var result := final_event(state.campaign)
		assert(result.ok)
		if not result.ok: return {}
	var data: Dictionary = state.snapshot()
	# Retain genuine version-1 bytes so the real SaveStore must migrate them.
	if old_save and completed: data.campaign = prefix(MISSIONS.LEGACY_ORDER.size(),true)
	assert(STATE.new().restore_snapshot(data))
	return data

static func output_dir(label: String) -> String:
	var path := "res://evidence/%s-%d-%d" % [label,OS.get_process_id(),Time.get_ticks_usec()]
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)): return ""
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path)) != OK: return ""
	return path

static func write_fixture(folder: String, filename: String, data: Dictionary) -> String:
	if folder.is_empty() or not STATE.new().restore_snapshot(data): return ""
	var path := folder.path_join(filename)
	if FileAccess.file_exists(path) or path == STORE.PATH: return ""
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return ""
	file.store_string(JSON.stringify(data,"\t"))
	file.close()
	return path if not STORE.read_valid(path).is_empty() else ""

static func graph_snapshot(routes) -> Array:
	var result := []
	for segment in routes.segments:
		result.append({"id":str(segment.id),"a":segment.a,"b":segment.b,"width":segment.width})
	return result

static func route_keeps_outside(routes, forbidden: Rect2) -> bool:
	# Check segments continuously enough to include narrow barriers, rather than
	# checking graph vertices alone (a long edge could jump across the works).
	for segment in routes.segments:
		var a: Vector3 = segment.a
		var b: Vector3 = segment.b
		var steps := maxi(1,ceili(a.distance_to(b)/.5))
		for index in steps+1:
			var point: Vector3 = a.lerp(b,float(index)/float(steps))
			if forbidden.has_point(Vector2(point.x,point.z)): return false
	return true

static func source_fingerprint() -> Dictionary:
	var files: Array[String] = [
		"res://world/regions/WorldConnection3D.gd","res://world/regions/CoastalProtection.gd",
		"res://world/regions/NativeRegion.gd","res://world/regions/OriginalWorldData.json",
		"res://world/editing/EditableRegion.gd","res://world/editing/world_edits.json",
		"res://data/campaign/HarborMissions.gd","res://systems/campaign/CampaignRuntime.gd",
		"res://runtime/GameState.gd","res://runtime/SaveStore.gd","res://runtime/ProductionWorld.gd","res://runtime/FullSession.gd",
		"res://gameplay/NativeTrafficRoutes.gd","res://gameplay/dispatch/DispatchRoadRouter.gd","res://gameplay/dispatch/RoadGraphSearch.cs",
		"res://tests/fixtures/NorthGatewayFixtures.gd","res://tests/test_north_gateway_progress.gd",
		"res://tests/test_north_gateway_integration.gd","res://tests/measure/measure_north_gateway.gd","res://project.godot","res://Harbor.csproj",
		"res://.godot/mono/temp/bin/Debug/Harbor.dll"]
	for filename in DirAccess.get_files_at("res://world/north_gateway"):
		if filename.ends_with(".gd"): files.append("res://world/north_gateway/"+filename)
	files.sort()
	var result := {}
	for path in files: result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return result
