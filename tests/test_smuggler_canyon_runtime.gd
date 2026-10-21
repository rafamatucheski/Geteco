extends SceneTree
## Main production combat. Diagnostic placements are not access-route evidence.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const CANYON := preload("res://runtime/desert/canyon/CanyonState.gd")
const ENCOUNTER := preload("res://runtime/desert/canyon/CanyonEncounter.gd")
const L := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var world: Node3D
var encounter: Node3D
var output := ""
var checks := 0
var failures: Array[String]=[]
var shots := 0
var damage_observed := 0.0
var log: Array[Dictionary]=[]
var resident_ids: Array[int]=[]

func _initialize() -> void:
	create_timer(210).timeout.connect(func(): failures.append("210s fixture watchdog"); finish(3))
	run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks+=1
	print("CANYON_RUNTIME ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"isolated no-save native .NET required"): finish(2); return
	output=FIXTURE.output_dir("smuggler-canyon-runtime")
	var start := L.CENTER+Vector3(0,.18,-65)
	var data := FIXTURE.full_snapshot(start,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[start.x,start.y,start.z]}
	data.world[CANYON.KEY]=CANYON.defaults()
	if "--death-only" in OS.get_cmdline_user_args():
		await verify_lethal_round_recovery(data)
		finish(0 if failures.is_empty() else 1)
		return
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	if not check(not path.is_empty(),"isolated fresh camp checkpoint validates"): finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.get("session")!=null and world.session.ready_for_play and world.production.store.path==path and world.session.controller.no_save,"Main loads fixture only"): finish(1); return
	if world.session.modal: world.session.close_menu()
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"C# routing is active")
	encounter=world.session.desert.canyon
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.player.speed=3.5
	world.gameplay.npc_gunfire.connect(func(_o: Vector3,_d: Vector3,shooter: Node3D):
		if shooter.is_in_group("desert_smugglers"): shots+=1)
	deadline=Time.get_ticks_msec()+12000
	while encounter.live_count()<8 and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(encounter.live_count()==8 and get_nodes_in_group("desert_smugglers").size()==8,"eight finite defenders admitted"): finish(1); return
	await wait_seconds(.5)
	for actor in encounter.actors.values():
		resident_ids.append(actor.get_instance_id())
		check(actor.is_on_floor() and absf(actor.global_position.y)<.2,"guard capsule supported by real mesa floor "+str(actor.slot))
		check(actor.health>=150 and actor.weapon_id in ["ak47","m4a1","smg"],"resistant defender carries real long gun "+str(actor.slot))
	check(shots==0,"defenders do not shoot distant bridge approach")
	# Establish close approach diagnostically, then let actual LOS and moving
	# projectiles cause damage. Travel/bridge/chicane are covered separately.
	if not place_near(encounter.actors[0],6.0): finish(1); return
	world.camera.initialized=false
	world.camera._process(1)
	await photo("base-eight-guards")
	var health_before: float=world.gameplay.health
	deadline=Time.get_ticks_msec()+6000
	while world.gameplay.health>=health_before and Time.get_ticks_msec()<deadline: await physics_frame
	damage_observed=health_before-float(world.gameplay.health)
	check(shots>0 and damage_observed>0 and world.gameplay.health>0,"natural detection fires moving rounds and causes real damage")
	check(not encounter.save_block_reason().is_empty() and not world.session.save_block_reason().is_empty(),"active confrontation blocks save")
	world.gameplay.toggle_god_mode()
	await wait_seconds(.4)
	await photo("base-active-combat")
	health_before=world.gameplay.health
	var shot_before := shots
	await wait_seconds(1.5)
	check(shots>shot_before and is_equal_approx(float(world.gameplay.health),health_before),"production damage honors invulnerability")
	world.session._menu("Teste de pausa")
	await wait_seconds(.4)
	shot_before=shots
	await wait_seconds(.7)
	check(shots==shot_before and encounter.snapshot().paused,"modal pauses all defenders")
	world.session.close_menu()
	if "--contact-only" in OS.get_cmdline_user_args():
		finish(0 if failures.is_empty() else 1)
		return
	var bag_before: String=str(world.session.state.economy.snapshot().grid_inventory.bag)
	if bag_before.is_empty():
		check(world.session.state.economy.grid_equip_bag("backpack"),"combat fixture equips absent backpack through inventory API")
	check(world.session.state.economy.snapshot().grid_inventory.bag=="backpack","combat fixture has equipped backpack")
	check(world.session.state.grant_weapon("m4a1"),"prepared combat fixture grants M4 with catalog reserve")
	check(world.session.state.equip_weapon("m4a1"),"prepared combat fixture equips carried M4")
	for index in 7:
		var actor: CharacterBody3D=encounter.actors[index]
		if not place_near(actor,4.0) or not await defeat_with_player_weapon(actor): finish(1); return
		check((int(world.session.state.world_state[CANYON.KEY].defeated_mask)&(1<<index))!=0,"real weapon persists specific defender death "+str(index))
	var last: CharacterBody3D=encounter.actors[7]
	var cover := L.CENTER+Vector3(-12,0,-14)
	last.position=cover+Vector3(0,.06,-4)
	last.home=last.position
	world.player.teleport(cover+Vector3(0,.08,4))
	await wait_seconds(1.2)
	var ray := PhysicsRayQueryParameters3D.create(last.global_position+Vector3.UP*1.4,world.player.global_position+Vector3.UP,7,[last.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider!=world.player,"authored defensive wall blocks physical line of sight")
	world.gameplay.toggle_god_mode()
	health_before=world.gameplay.health
	shot_before=shots
	await wait_seconds(1.5)
	check(shots==shot_before and is_equal_approx(float(world.gameplay.health),health_before),"cover prevents shots and damage with protection disabled")
	# A new long gun requires a free carried long-gun slot, even with spare
	# backpack cells. Store the test M4 through the normal inventory operation.
	check(world.session.state.economy.grid_store_weapon("m4a1","storage"),"store M4 in backpack to free the long-gun slot before AK loot")
	# Last kill uses direct production damage solely to choose a deterministic
	# ordinary drop. Seven prior kills already exercised real player firearms.
	last.position=L.CENTER+Vector3(0,.06,5)
	last.home=last.position
	var rng := RandomNumberGenerator.new()
	for candidate in range(1,65):
		rng.seed=candidate
		if rng.randf()<=float(world.gameplay.LOOT_WEAPON_CHANCE): world.gameplay._rng.seed=candidate; break
	var loot_before: int=world.gameplay._loot.size()
	world.gameplay._damage(last,1000.0,world.player)
	check(last.dead and last.collision_layer==0 and not last.is_physics_processing(),"final corpse cannot move or block")
	check(world.gameplay._loot.size()>loot_before,"production death spawns physical weapon loot")
	check(int(world.session.state.world_state[CANYON.KEY].defeated_mask)==255 and encounter.live_count()==0 and encounter.save_block_reason().is_empty(),"all defeated slots persist and confrontation ends")
	if world.gameplay._loot.size()>loot_before: await collect_loot(world.gameplay._loot[loot_before])
	world.player.teleport(L.ARMORY_POS+Vector3(0,.08,0))
	await wait_seconds(.4)
	var action: Dictionary=encounter.nearest_action()
	log.append({"phase":"armory_before","action":action,"inventory":world.session.state.economy.snapshot()})
	check(not action.is_empty() and world.session.desert.perform(action),"physical armory interaction grants AK or ammo")
	check((int(world.session.state.world_state[CANYON.KEY].cache_mask)&1)!=0,"armory receipt and marker publish together")
	log.append({"phase":"armory_after","state":world.session.state.world_state[CANYON.KEY],"inventory":world.session.state.economy.snapshot()})
	var stored := STORE.new(); stored.path=output.path_join("cleared.json")
	check(stored.save(world.session.state)==OK,"cleared state writes valid isolated disk save")
	var restored := STATE.new()
	check(stored.load_into(restored).get("ok",false) and int(restored.world_state[CANYON.KEY].defeated_mask)==255,"cold disk restore retains cleared camp")
	# Compact approach is now inside the encounter retention radius. Leave it
	# explicitly before checking that every resident and corpse is released.
	var unload_point := L.CENTER+(L.APPROACH-L.CENTER).normalized()*(ENCOUNTER.DESPAWN_DISTANCE+20.0)
	unload_point.y=.1
	check(unload_point.distance_to(L.CENTER)>ENCOUNTER.DESPAWN_DISTANCE,"unload probe lies beyond encounter retention radius")
	world.player.teleport(unload_point)
	await wait_seconds(1)
	var freed := get_nodes_in_group("desert_smugglers").is_empty()
	for id in resident_ids: freed=freed and not is_instance_id_valid(id)
	check(freed and encounter.actors.is_empty(),"distance unload releases living/corpse ownership")
	world.session.state.world_state[CANYON.KEY]=restored.world_state[CANYON.KEY].duplicate(true)
	world.player.teleport(L.CENTER+Vector3(0,.08,-18))
	await wait_seconds(2.5)
	check(encounter.live_count()==0 and get_nodes_in_group("desert_smugglers").is_empty(),"return after restore never farms defenders")
	await verify_lethal_round_recovery(data)
	finish(0 if failures.is_empty() else 1)

func verify_lethal_round_recovery(original: Dictionary) -> void:
	# Load through a fresh production Main so inventory migration and runtime
	# bindings run exactly as they do when the player loads a saved session.
	# Mutating an already-bound GameState here would bypass that lifecycle.
	var partial := original.duplicate(true)
	partial.world[CANYON.KEY].defeated_mask=1
	var partial_path := FIXTURE.write_fixture(output,"partial-recovery-checkpoint.json",partial)
	if not check(not partial_path.is_empty(),"valid partial disk checkpoint establishes death/recovery case"): return
	if is_instance_valid(world):
		if is_instance_valid(encounter): encounter.cancel_attempt()
		current_scene=null
		world.queue_free()
		world=null; encounter=null
		for frame in 2: await process_frame
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",partial_path)
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.get("session")!=null and world.session.ready_for_play and world.production.store.path==partial_path and world.session.controller.no_save,"fresh Main loads partial checkpoint through production startup"): return
	if world.session.modal: world.session.close_menu()
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"recovery Main runs native C# routing")
	check(world.session.state.economy.grid_enabled() and world.session.state.economy.snapshot().has("grid_inventory"),"production inventory initialization and migration completed")
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.player.speed=3.5
	encounter=world.session.desert.canyon
	deadline=Time.get_ticks_msec()+10000
	while encounter.live_count()<7 and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(encounter.live_count()==7 and not encounter.actors.has(0),"partial restore admits only seven surviving defenders"): return
	var owned_rids: Array[RID]=[]
	for actor in encounter.actors.values():
		if is_instance_valid(actor): owned_rids.append(actor.get_rid())
	if not place_near(encounter.actors[1],6.0): return
	world.gameplay.health=1
	world.gameplay.armor=0
	deadline=Time.get_ticks_msec()+6000
	while world.gameplay.health>0 and Time.get_ticks_msec()<deadline: await physics_frame
	if not check(world.gameplay.health<=0 and world.session.rescue_pending,"actual enemy round triggers player death and rescue"): return
	await wait_seconds(.25)
	check(encounter.actors.is_empty() and get_nodes_in_group("desert_smugglers").is_empty(),"lethal round cancellation frees defenders without mutating producer loop")
	var own_rounds := 0
	for round_data in world.gameplay._police_rounds:
		if round_data.rid in owned_rids: own_rounds+=1
	check(own_rounds==0,"death leaves no canyon projectiles in next frame")
	deadline=Time.get_ticks_msec()+20000
	while (world.session.rescue_pending or world.gameplay.health<=0) and Time.get_ticks_msec()<deadline: await physics_frame
	check(world.gameplay.health>0 and not world.session.rescue_pending and not world.player.input_locked,"production rescue restores health and player control")
	check(int(world.session.state.world_state[CANYON.KEY].defeated_mask)==1,"rescue preserves previously defeated slot without replenishment")
	await wait_seconds(1.5)
	check(world.player.is_on_floor() and world.player.global_position.distance_to(world.session.controller.region.spawn_position)<3.0,"rescued actor remains physically supported at the desert return point")
	check(world.session.state.economy.grid_enabled() and world.session.state.economy.snapshot().has("grid_inventory"),"inventory runtime remains initialized after rescue")
	var stored := STORE.new(); stored.path=output.path_join("after-recovery.json")
	check(stored.save(world.session.state)==OK,"rescued partial progress writes valid isolated save")
	var restored := STATE.new()
	check(stored.load_into(restored).get("ok",false) and int(restored.world_state[CANYON.KEY].defeated_mask)==1,"cold disk restore preserves partial defeats after rescue")

func place_near(actor: CharacterBody3D,distance: float) -> bool:
	for direction in [Vector3.BACK,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD]:
		var point: Vector3=actor.global_position+direction*distance
		point.y=.08
		if L.analytic_height(Vector2(point.x,point.z))<-.08 or not world.session.position_clear(point): continue
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP,actor.global_position+Vector3.UP,7,[world.player.get_rid()])
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider!=actor: continue
		world.player.teleport(point)
		return true
	return check(false,"clear supported firing position for guard "+str(actor.slot))

func defeat_with_player_weapon(actor: CharacterBody3D) -> bool:
	var deadline := Time.get_ticks_msec()+12000
	var accepted := 0
	while not actor.dead and Time.get_ticks_msec()<deadline:
		world.gameplay.aim_point=actor.global_position+Vector3.UP
		if int(world.session.state.get_ammo("m4a1").magazine)==0: world.gameplay.reload_weapon()
		if world.gameplay.fire_at(actor.global_position+Vector3.UP): accepted+=1
		await physics_frame
	return check(actor.dead and accepted>0,"player firearm defeats guard "+str(actor.slot))

func collect_loot(pickup: Node3D) -> void:
	var point := pickup.global_position
	var entry := {"phase":"walking_loot","kind":pickup.kind,"weapon":pickup.weapon_id,"point":str(point),"inventory_before":world.session.state.economy.snapshot()}
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new(); sphere.radius=.04
	query.shape=sphere; query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.15); query.collision_mask=1
	check(world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"loot center stays outside solid props")
	# The old fixed +Z start overlaps the ammunition cases at local z=8.05.
	# Find a full supported capsule corridor, then use normal walking only.
	var walk_start := Vector3.INF
	for direction in [Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3(-1,0,-1).normalized(),Vector3(1,0,-1).normalized()]:
		var clear := true
		for step in range(1,13):
			var sample: Vector3=point+direction*(3.0*float(step)/12.0)
			sample.y=.08
			if not world.session.position_clear(sample): clear=false; break
		if clear:
			walk_start=point+direction*3.0; walk_start.y=.08
			break
	if not check(walk_start.is_finite(),"loot walking fixture starts in a supported clear capsule corridor"):
		entry.merge({"controls":loot_controls(),"reason":"no clear walking corridor"})
		log.append(entry)
		return
	world.player.teleport(walk_start)
	await wait_seconds(.3)
	entry["start"]=str(walk_start)
	entry["controls_before"]=loot_controls()
	check(loot_walking_ready(),"loot walking starts alive with active physics and player control")
	var travelled := 0.0
	var previous: Vector3=world.player.global_position
	var deadline := Time.get_ticks_msec()+3000
	var collected := false
	var supported := true
	var controllable := true
	var minimum_distance := INF
	var trace: Array[Dictionary]=[]
	var frame := 0
	while Time.get_ticks_msec()<deadline:
		travelled+=world.player.global_position.distance_to(previous)
		previous=world.player.global_position
		supported=supported and world.player.is_on_floor()
		controllable=controllable and loot_walking_ready()
		minimum_distance=minf(minimum_distance,Vector2(previous.x,previous.z).distance_to(Vector2(point.x,point.z)))
		if frame%6==0: trace.append({"position":str(previous),"supported":world.player.is_on_floor(),"pickup_valid":is_instance_valid(pickup),"consumed":pickup.consumed if is_instance_valid(pickup) else false,"controls":loot_controls()})
		frame+=1
		if not controllable: break
		if is_instance_valid(pickup) and pickup.consumed: collected=true; break
		if not is_instance_valid(pickup): break
		var move: Vector3=point-world.player.global_position; move.y=0
		world.player.automatic_direction=move.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	check(controllable,"loot walking remains alive without rescue or control interruption")
	check(collected and travelled>1 and supported,"normal supported walking collects physical drop")
	entry.merge({"loot_walk_metres":travelled,"supported":supported,"controllable":controllable,"controls_after":loot_controls(),"collected":collected,"minimum_distance":minimum_distance,"inventory_after":world.session.state.economy.snapshot(),"trace":trace})
	log.append(entry)
	print("CANYON_LOOT_DIAGNOSTIC ",JSON.stringify(entry))

func loot_controls() -> Dictionary:
	return {"modal":world.session.modal,"tree_paused":paused,"input_locked":world.player.input_locked,"physics":world.player.is_physics_processing(),"health":world.gameplay.health,"dead":world.player.dead,"rescue":world.session.rescue_pending,"transition":world.session.has_position_transition(),"velocity":str(world.player.velocity)}

func loot_walking_ready() -> bool:
	return not paused and not world.session.modal and not world.player.input_locked and world.player.is_physics_processing() and world.gameplay.health>0 and not world.player.dead and not world.session.rescue_pending and not world.session.has_position_transition()

func wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline: await physics_frame

func photo(id: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))

func finish(code: int) -> void:
	if is_instance_valid(world) and is_instance_valid(world.get("player")): world.player.automatic_direction=Vector3.ZERO
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		if file: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"death_only":"--death-only" in OS.get_cmdline_user_args(),"contact_only":"--contact-only" in OS.get_cmdline_user_args(),"shots":shots,"damage_observed":damage_observed,"physical_diagnostics":log,"scope":"Real Main .NET firing, player weapon kills, cover, walking pickup, pause, persistence and unload. Contact-only stops after first contact, incoming damage and pause; later full-suite checks are not executed. Death-only mode exercises partial checkpoint startup, lethal enemy projectile, rescue and restored save. Combat positions and last damage roll are diagnostic; access traversal and performance require separate validation."},"\t"))
	print("CANYON_RUNTIME_DONE ",output," code=",code)
	quit(code)
