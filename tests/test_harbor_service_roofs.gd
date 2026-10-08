extends SceneTree
## Full Main-scene owner -> physical roof -> owner, with authorized campaign and
## residential fixtures. The fixture is not evidence of playing prior missions.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const CATALOG = preload("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd")
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const STORE = preload("res://runtime/SaveStore.gd")
var world
var folder := ""
var save_path := ""
var rendered := false
var checks := 0
var failures: Array[String] = []
var visited: Array[String] = []
var selected: Array[Dictionary] = []
var previous_health := 100.0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("SERVICE_ROOF ","PASS " if value else "FAIL ",label)
	if not value: failures.append(label)
	return value

func boot() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 5.0
	previous_health = world.gameplay.health
	world.gameplay.changed.connect(_track_health)
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	for frame in 5: await physics_frame

func _track_health() -> void:
	if world.gameplay.health<previous_health:
		print("SERVICE_ROOF_DAMAGE before=",previous_health," after=",world.gameplay.health," at=",world.player.global_position," stack=",JSON.stringify(get_stack()))
	previous_health = world.gameplay.health

func photo(label: String) -> void:
	if not rendered: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))

func garage_protection(label: String) -> void:
	if world.session.state.place_id!="maciota": return
	check(not world.session.state.weapons_allowed() and not world.session.state.can_attack(),label+" Maciota attacks and weapons remain prohibited")
	check(world.session.state.equipped_weapon=="fists",label+" weapon stays holstered")
	for actor in [world.maciota_place.maciota,world.maciota_place.mechanic]:
		check(actor.get_meta("invulnerable",false) and not actor.has_method("take_damage") and not actor.has_method("damage"),label+" protected resident "+str(actor.name))

func walk(target: Vector3) -> bool:
	# The Vértice roof is 55.5m wide; a real 5m/s crossing needs over ten
	# seconds. Scale only the bounded travel allowance to the actual distance.
	var travel_ms := ceili(world.player.global_position.distance_to(target)/maxf(.1,world.player.speed)*1300.0)+2000
	var deadline := Time.get_ticks_msec()+maxi(10000,travel_ms)
	while world.player.global_position.distance_to(target)>.26 and Time.get_ticks_msec()<deadline:
		if world.player.global_position.y < -1.0 or world.player.global_position.distance_to(target)>80 or world.gameplay.health<=0:
			print("SERVICE_ROOF_WALK_INTERRUPTED point=",world.player.global_position," health=",world.gameplay.health," region=",world.session.state.region_id," place=",world.session.state.place_id," rescue=",world.session.rescue_pending," transition=",world.session.transition_kind," service_roof=",world.session.service_roofs.is_active())
			break
		var direction: Vector3 = target-world.player.global_position
		direction.y = 0
		world.player.automatic_direction = direction.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	if world.player.global_position.distance_to(target)>.43:
		print("SERVICE_ROOF_BLOCKED expected=",target," actual=",world.player.global_position)
		for index in world.player.get_slide_collision_count():
			var contact = world.player.get_slide_collision(index)
			var collider = contact.get_collider()
			print("SERVICE_ROOF_BODY ",collider.get_path() if collider is Node else collider," at=",contact.get_position()," normal=",contact.get_normal())
	return world.player.global_position.distance_to(target)<.43

func place_fixture(point: Vector3) -> bool:
	# A distant fixture teleport can outrun streamed terrain. Admission and
	# walking are live after real floor/capsule support becomes available.
	world.player.set_physics_process(false)
	world.player.teleport(point)
	world.production.region.set_focus(point)
	var deadline := Time.get_ticks_msec()+20000
	while not world.session.position_clear(point) and Time.get_ticks_msec()<deadline:
		# Resolve the feet against actual pavement/slab support, never against
		# furniture. The same full capsule/support admission remains required.
		var floor_query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*.5,1)
		var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(floor_query)
		if not floor_hit.is_empty() and floor_hit.normal.y>.95:
			var body_name := str(floor_hit.collider.name).to_lower()
			var transit_platform: bool = body_name=="stationcollision" and absf(float(floor_hit.position.y)-.20)<.01
			if transit_platform or ["floor","ground","slab","platform","pavement","sidewalk"].any(func(term): return term in body_name):
				point.y = maxf(point.y,float(floor_hit.position.y)+.06)
				world.player.teleport(point)
		await physics_frame
	var supported: bool = world.session.position_clear(point)
	if not supported:
		var query := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .32
		capsule.height = 1.7
		query.shape = capsule
		query.collision_mask = 7
		query.exclude = [world.player.get_rid()]
		query.transform.origin = point+Vector3.UP*.9
		for hit in world.get_world_3d().direct_space_state.intersect_shape(query,8):
			print("SERVICE_ROOF_FIXTURE_BODY point=",point," collider=",hit.collider.get_path())
		var support := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.5,1)
		print("SERVICE_ROOF_FIXTURE_SUPPORT point=",point," hit=",world.get_world_3d().direct_space_state.intersect_ray(support))
	world.player.set_physics_process(true)
	return supported

func approach_owner(target: Dictionary) -> bool:
	var session = world.session
	if not session.state.place_id.is_empty():
		var leaving: String = session.state.place_id
		if not check(await session.leave_place(),leaving+" original exterior departure before next owner"):
			print("SERVICE_ROOF_DEPARTURE room=",session.room," return=",session.return_point," transition=",session.transition_kind," locked=",world.player.input_locked)
			return false
	var physical := str(target.owner)!="service"
	var start: Vector3 = target.exterior_position+Vector3(0,.06,target.size.y*.5+2)
	if not physical:
		start = world.maciota_place.entry_position if target.id=="maciota" else PLACES.get_definition(target.id).entry_position
	elif target.owner=="village_home": start=session.urban_operations.village.homes.homes[int(target.index)].root.to_global(Vector3(0,.06,7.2))
	elif target.owner=="tire_shop": start=target.exterior_position+Vector3(4.2,.06,6.1)
	elif target.owner=="vertice": start=session.urban_operations.cargo_handling.depot.to_global(Vector3(35,.06,32.1))
	elif target.owner=="northgate": start=target.exterior_position+Vector3(0,.06,target.size.y*.5+1.4)
	if target.id=="port_boss_garage":
		# This checkpoint includes an authorized port visit. Teleporting a
		# fixture into the security zone without that permission is a real crime.
		check(session.urban_operations.security.restore_snapshot({"version":1,"authorized_entry":false,"authorized_visit":true,"exiting_port":false}),"authorized port visit fixture")
	if target.owner=="village_home":
		# Each house is an independent rested/armored checkpoint after the last
		# conflict expired. Crossing this house still triggers its live guards;
		# no invulnerability, NPC deactivation or combat/save bypass is used.
		var quest = session.urban_operations.village_quest
		var commerce: Dictionary = quest.commerce.snapshot()
		commerce.hostility = 0.0
		if not check(quest.commerce.restore_snapshot(commerce),str(target.id)+" independent peaceful village checkpoint"): return false
		quest._sync_hostility(true)
		world.gameplay.heal(100)
		world.gameplay.armor = 100.0
		world.gameplay.changed.emit()
	if not check(await place_fixture(start+Vector3.UP*.05),str(target.id)+" supported street fixture"): return false
	for frame in 30: await physics_frame
	if not physical:
		# Existing doors and their authorization policy perform admission.
		if target.id in ["westgate_garden","quayside_house","canal_north"]:
			var owned: Dictionary = session.activities.residence.snapshot()
			owned.active_home = str(target.id)
			owned.purchases = maxi(1,int(owned.purchases))
			if not check(session.activities.residence.restore_snapshot(owned),str(target.id)+" authorized residential fixture"): return false
		if target.id=="port_boss_garage":
			session.state.world_state.time = 2.0/24.0
			session.weather.time_of_day = 2.0/24.0
		if not check(await session.enter_place(str(target.id)),str(target.id)+" original owner admission"): return false
	else:
		var destination: Vector3
		match str(target.owner):
			"village_home":
				var home: Node3D = session.urban_operations.village.homes.homes[int(target.index)].root
				# Stand beyond the 1.8m swinging leaf while proximity opens it.
				for frame in 40: await physics_frame
				destination = home.to_global(Vector3(0,.04,3.05))
			"tire_shop":
				destination = target.exterior_position+Vector3(4.2,.04,0)
			"vertice":
				session.state.world_state.time = .45
				session.weather.time_of_day = .45
				var depot: Node3D = session.urban_operations.cargo_handling.depot
				for frame in 50: await physics_frame
				destination = depot.to_global(Vector3(35,.04,27.5))
			"northgate":
				destination = target.exterior_position+Vector3(0,.04,target.size.y*.5-2)
		if not check(await walk(destination),str(target.id)+" crosses physical owner threshold"): return false
	var runtime = session.service_roofs
	var deadline := Time.get_ticks_msec()+6000
	while (not is_instance_valid(runtime.access_visual) or runtime.access_definition.get("id","")!=target.id) and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(is_instance_valid(runtime.access_visual) and runtime.access_definition.get("id","")==target.id,str(target.id)+" solid stair in owner"): return false
	if not check(await walk(runtime.access_point),str(target.id)+" walk to stair without crossing furniture"): return false
	await photo(str(target.id)+"-access")
	garage_protection("ground")
	return check(runtime.nearest_action().get("id","")=="service_roof_stairs",str(target.id)+" stair action discoverable")

func visit(target: Dictionary) -> bool:
	if not await approach_owner(target): return false
	var runtime = world.session.service_roofs
	var original_room: Node3D = world.session.room
	var return_point: Vector3 = world.player.global_position
	if not check(await runtime.use_stairs(),str(target.id)+" functional ascent"): return false
	if not check(runtime.is_active() and runtime.definition.id==target.id,str(target.id)+" physical roof active"): return false
	check(world.session.room==original_room and world.session.state.place_id==target.place,str(target.id)+" original service identity retained")
	check(world.session.position_clear(world.player.global_position),str(target.id)+" supported clear landing")
	check(absf(world.player.global_position.y-target.exterior_position.y-target.roof_height)<.3,str(target.id)+" real roof height")
	check(not world.session.weather._inside_shelter(),str(target.id)+" exterior weather")
	check(not world.camera.locked and world.camera.target==world.player,str(target.id)+" exterior camera follows player")
	check(not world.player.input_locked and not runtime.busy,str(target.id)+" player controls returned")
	garage_protection("roof")
	var jump: Vector3 = runtime.roof.jump_point
	var corridor: Vector3 = Vector3(jump.x,.04,runtime.roof.stair_point().z)
	if not check(await walk(runtime.roof.to_global(corridor)),str(target.id)+" solid roof crossing toward jump bay"): return false
	if not check(await walk(runtime.roof.to_global(jump+Vector3.UP*.04)),str(target.id)+" walk to guarded jump bay"): return false
	check(runtime.nearest_action().get("id","")=="service_roof_jump",str(target.id)+" jump action discoverable")
	if not check(await walk(runtime.roof.to_global(corridor)),str(target.id)+" return through roof corridor"): return false
	await photo(str(target.id)+"-roof")
	var wrote: bool = world.session.save_game()
	if not wrote: print("SERVICE_ROOF_SAVE_BLOCK ",world.session.save_block_reason()," stars=",world.gameplay.stars," active=",world.session.state.campaign.active_id)
	check(wrote,str(target.id)+" roof save")
	var saved: Dictionary = STORE.read_valid(save_path)
	check(not saved.is_empty() and saved.get("world",{}).get("harbor_service_roof",{}).get("id","")==target.id,str(target.id)+" actual roof snapshot persisted")
	if visited.is_empty():
		world.free()
		await process_frame
		await boot()
		runtime = world.session.service_roofs
		if not check(runtime.is_active() and runtime.definition.id==target.id,str(target.id)+" cold roof restore"): return false
		check(world.session.position_clear(world.player.global_position),str(target.id)+" restored support and capsule")
		garage_protection("cold restore")
		original_room = world.session.room
	# Descending requires reaching the actual stair landing in the live scene.
	if not check(await walk(runtime.roof.to_global(runtime.roof.stair_point()+Vector3.UP*.04)),str(target.id)+" walk to roof stair"): return false
	if not check(await runtime.use_stairs(),str(target.id)+" functional descent"): return false
	check(not runtime.is_active() and world.session.room==original_room,str(target.id)+" original owner restored")
	check(world.player.global_position.distance_to(return_point)<.4,str(target.id)+" returns to original stair")
	check(world.session.position_clear(world.player.global_position),str(target.id)+" clear returned body")
	check(not world.player.input_locked and world.session.transition_kind.is_empty(),str(target.id)+" no transition lock leak")
	garage_protection("return")
	visited.append(str(target.id))
	return true

func recover_after_roof_death(label: String) -> bool:
	var deadline := Time.get_ticks_msec()+20000
	while (world.gameplay.health<=0 or world.session.rescue_pending or world.session.respawn_busy) and Time.get_ticks_msec()<deadline: await physics_frame
	var session = world.session
	var recovered: bool = world.gameplay.health>0 and not session.rescue_pending and not session.respawn_busy
	check(recovered,label+" normal death and rescue completes")
	check(session.transition_kind.is_empty() and not world.player.input_locked,label+" releases transition and player lock")
	check(not world.player.controlled_automatically,label+" restores human movement ownership")
	check(not session.service_roofs.is_active() and not is_instance_valid(session.room) and session.state.place_id.is_empty(),label+" destroys provisional roof and original room")
	check(not world.player.get_meta("harbor_service_rooftop",false),label+" clears rooftop actor flag")
	check(session.position_clear(world.player.global_position),label+" rescue has actual support and clear capsule")
	return recovered

func recovery_scenarios(target: Dictionary) -> void:
	for phase in ["ascent","descent","jump"]:
		world.player.controlled_automatically = true
		world.player.automatic_direction = Vector3.ZERO
		if not await approach_owner(target): return
		var runtime = world.session.service_roofs
		if phase!="ascent":
			if not check(await runtime.use_stairs(),phase+" recovery setup reaches roof"): return
			if phase=="descent":
				if not check(await walk(runtime.roof.to_global(runtime.roof.stair_point()+Vector3.UP*.04)),"recovery walks to descending stair"): return
			else:
				var jump: Vector3 = runtime.roof.jump_point
				if not await walk(runtime.roof.to_global(Vector3(jump.x,.04,runtime.roof.stair_point().z))): return
				if not await walk(runtime.roof.to_global(jump+Vector3.UP*.04)): return
		world.player.controlled_automatically = false
		world.player.automatic_direction = Vector3.ZERO
		create_timer(.06).timeout.connect(func(): world.gameplay.damage_environment(10000))
		var completed: bool = await runtime.jump_from_roof() if phase=="jump" else await runtime.use_stairs()
		check(not completed,phase+" aborts when real lethal damage interrupts it")
		if not await recover_after_roof_death(phase): return
	await normal_jump(target)

func normal_jump(target: Dictionary) -> void:
	# The same entry also proves the uninterrupted physical jump and fall,
	# with normal gravity/damage and the service owner released to the street.
	# Each jump starts rested; fall damage remains enabled and measured.
	world.gameplay.heal(100)
	world.player.controlled_automatically = true
	if not await approach_owner(target): return
	var runtime = world.session.service_roofs
	if not check(await runtime.use_stairs(),"normal jump setup reaches roof"): return
	var jump: Vector3 = runtime.roof.jump_point
	if not check(await walk(runtime.roof.to_global(Vector3(jump.x,.04,runtime.roof.stair_point().z))),"normal jump crosses actual roof"): return
	if not check(await walk(runtime.roof.to_global(jump+Vector3.UP*.04)),"normal jump reaches actual gate"): return
	world.player.controlled_automatically = false
	world.player.automatic_direction = Vector3.ZERO
	var before: float = world.gameplay.health
	check(await runtime.jump_from_roof(),"normal physical jump crosses parapet to falling state")
	var deadline := Time.get_ticks_msec()+10000
	while runtime.is_active() and Time.get_ticks_msec()<deadline: await physics_frame
	print("SERVICE_ROOF_LANDING owner=",target.id," peak=",runtime.fall_peak," position=",world.player.global_position," drop=",runtime.fall_peak-world.player.global_position.y," health_before=",before," health_after=",world.gameplay.health)
	var support_query := PhysicsRayQueryParameters3D.create(world.player.global_position+Vector3.UP*.2,world.player.global_position-Vector3.UP*.5,1)
	var support: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(support_query)
	if not support.is_empty(): print("SERVICE_ROOF_LANDING_SUPPORT ",support.collider.get_path()," point=",support.position)
	check(not runtime.is_active() and world.player.is_on_floor(),"normal fall lands on real city floor")
	check(world.gameplay.health>0 and world.gameplay.health<before,"normal fall applies height damage")
	check(world.session.state.place_id.is_empty() and not is_instance_valid(world.session.room),"normal jump leaves original service owner")
	check(not world.player.input_locked and not world.player.controlled_automatically and world.session.transition_kind.is_empty(),"normal jump returns human control")

func run() -> void:
	create_timer(1200).timeout.connect(func(): check(false,"bounded Main walkthrough timeout"); finish(3))
	folder = FIXTURE.output_dir("harbor-service-roofs")
	rendered = DisplayServer.get_name()!="headless"
	seed(71026)
	selected = CATALOG.definitions()
	check(selected.size()==24,"24 distinct existing service and village roof owners")
	var only := ""
	var recovery := false
	var jump := false
	var start := 0
	var count := selected.size()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--roof="): only=arg.trim_prefix("--roof=")
		if arg.begins_with("--start="): start=arg.trim_prefix("--start=").to_int()
		if arg.begins_with("--count="): count=arg.trim_prefix("--count=").to_int()
		if arg=="--recovery": recovery=true
		if arg=="--jump": jump=true
	if not only.is_empty(): selected=selected.filter(func(row): return row.id in only.split(","))
	else: selected=selected.slice(start,mini(start+count,selected.size()))
	if not check(not selected.is_empty(),"selected inventory exists"): finish(); return
	var snapshot := FIXTURE.full_snapshot(selected[0].exterior_position+Vector3(0,.1,10),true)
	snapshot.campaign.aftermath = {"call_complete":true}
	save_path = FIXTURE.write_fixture(folder,"save.json",snapshot)
	if not check(not save_path.is_empty(),"isolated authorized campaign fixture"): finish(); return
	await boot()
	check(world.production.loaded_save and not world.production.save_invalid,"fixture restored through normal SaveStore")
	for target in selected:
		if not await visit(target): finish(); return
	check(visited.size()==selected.size(),"every selected owner reached final return assertions")
	if recovery: await recovery_scenarios(selected[0])
	elif jump:
		for target in selected: await normal_jump(target)
	finish()

func finish(code := -1) -> void:
	if visited.size()!=selected.size() and failures.is_empty(): check(false,"incomplete inventory: %d/%d owners"%[visited.size(),selected.size()])
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"visited":visited,"selected":selected.map(func(row): return row.id),"rendered":rendered},"\t"))
	print("HARBOR_SERVICE_ROOFS ",folder," checks=",checks," failures=",failures)
	quit((0 if failures.is_empty() else 1) if code<0 else code)
