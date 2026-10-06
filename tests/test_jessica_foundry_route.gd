extends SceneTree
## Read-only Main/.NET preflight of the candidate Foundry->Quay itinerary.
## It proves directed searches, joins and existing ground; actual driving,
## traffic/controls and safe exit remain the Main integration's responsibility.
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const PREFIX := ["primeiro_giro","cobra_contact","cobra_race","cobra_collection"]
var world
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(100).timeout.connect(func(): push_error("Foundry route preflight bounded timeout"); quit(3))
	run.call_deferred()

func fixture(path: String) -> bool:
	var state := STATE.new()
	var intro: Dictionary = state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	if not state.intro.restore_snapshot(intro): return false
	var campaign: Dictionary = state.campaign.snapshot()
	campaign.completed = PREFIX.duplicate()
	campaign.claimed_rewards = PREFIX.duplicate()
	campaign.flags = {}
	for id: String in PREFIX:
		for flag: String in MISSIONS.MISSIONS[id].sets_flags: campaign.flags[flag] = true
		if not state.economy.grant_reward("campaign:"+id,int(MISSIONS.MISSIONS[id].reward)): return false
	if not state.campaign.restore_snapshot(campaign): return false
	var point: Vector3 = PLACES.get_definition("harbor_bank").exterior_position+Vector3(0,.08,22)
	state.world_state.pedestrian = {"region":"harbor","position":[point.x,point.y,point.z]}
	var store := STORE.new()
	store.path = path
	return store.save(state) == OK

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): push_error("Foundry preflight requires --no-save"); quit(2); return
	var folder: String = "res://evidence/jessica-foundry-route-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	var save_path: String = folder.path_join("fixture-save.json")
	check(fixture(save_path),"isolated checkpoint is consistent")
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	for i in 3600:
		await physics_frame
		if world.session != null and world.session.ready_for_play and is_instance_valid(world.session.jessica.car): break
	check(world.session != null and world.session.ready_for_play and is_instance_valid(world.session.jessica.car),"real Main/native world and personal Jetta are ready")
	if not failures.is_empty(): await finish(); return
	var runtime = world.session.jessica
	var initial: Vector3 = runtime.car.global_position
	var plan: Dictionary = runtime._plan_getaway(true)
	check(plan.get("ok",false),"Foundry candidate is a connected production route")
	if not plan.get("ok",false):
		FileAccess.open(folder.path_join("route.json"),FileAccess.WRITE).store_string(JSON.stringify({"plan":plan,"legs":runtime.route_legs,"failures":failures},"\t"))
		print("FOUNDRY_PLAN_FAIL ",JSON.stringify(plan))
		await finish()
		return
	var legs: Dictionary = runtime.route_legs.duplicate(true)
	check(plan.get("native",false) and legs.first_native and legs.second_native and legs.third_native,"all three directed searches execute compiled C#")
	check(float(legs.seam_distance) <= .75 and float(legs.seam_direction_dot) >= .95 and legs.seams.size() == 2,"both native joins are physically continuous and aligned")
	var only_expected := true
	for ids: Array in legs.road_ids:
		for id: String in ids:
			if not id.contains("foundry_avenue") and not id.contains("quay_boulevard"): only_expected = false
	check(only_expected,"itinerary follows actual Foundry and Quay roads without Market/Medical detours")
	var road: Curve3D = plan.curve
	var region = world.session.controller.regions.harbor
	# Admit actual production chunks. No player/car transform or fabricated
	# floor is used to approve the candidate's street/access support.
	var samples: Array[Vector3] = []
	var cursor: float = 0
	while cursor < road.get_baked_length():
		samples.append(road.sample_baked(cursor,true))
		cursor += 2.0
	samples.append(road.sample_baked(road.get_baked_length(),true))
	var cells: Dictionary = {}
	for point: Vector3 in samples:
		var key := Vector2i(floori(point.x/64.0),floori(point.z/64.0))
		cells[key] = true
	for key: Vector2i in cells: region._ensure_chunk(key)
	for i in 3: await physics_frame
	var support_failures: Array[Dictionary] = []
	var roof_hits: Array[Dictionary] = []
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for point: Vector3 in samples:
		var offset: float = road.get_closest_offset(point)
		var next: Vector3 = road.sample_baked(minf(offset+.1,road.get_baked_length()),true)
		var heading: Vector3 = point.direction_to(next)
		if heading.length_squared() < .1: heading = road.sample_baked(maxf(0,offset-.1),true).direction_to(point)
		var yaw: float = atan2(-heading.x,-heading.z)
		var basis: Basis = Basis(Vector3.UP,yaw)
		for x: float in [-1.105*.8,1.105*.8]:
			for z: float in [-2.42*.8,2.42*.8]:
				var corner: Vector3 = point+basis*Vector3(x,0,z)
				var query := PhysicsRayQueryParameters3D.create(corner+Vector3.UP*.4,corner-Vector3.UP*.3,1)
				var hit: Dictionary = space.intersect_ray(query)
				if hit.is_empty() or absf(float(hit.position.y)-point.y) > .25:
					support_failures.append({"point":str(point),"corner":str(corner)})
				elif point.x > 180 and point.x < 195 and point.z > 58 and point.z < 69:
					roof_hits.append({"point":str(corner),"ground":str(hit.position),"collider":str(hit.collider.get_path())})
	check(support_failures.is_empty(),"four real support corners cover all road and courtyard access samples")
	check(not roof_hits.is_empty(),"Quay crosses the existing covered canal roof at street level")
	check(runtime.car.global_position.distance_to(initial) < .05,"route preflight never moves the personal car")
	var report: Dictionary = {"legs":legs,"support_failures":support_failures,"roof_hits":roof_hits,"checks":checks,"failures":failures,
		"limit":"static ground and native plan; moving whole-hull control, traffic and exit need real Main integration"}
	FileAccess.open(folder.path_join("route.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("JESSICA_FOUNDRY_ROUTE ",JSON.stringify(report))
	await finish()

func finish() -> void:
	if is_instance_valid(world): world.queue_free()
	for i in 3: await physics_frame
	print("JESSICA_FOUNDRY_ROUTE_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
