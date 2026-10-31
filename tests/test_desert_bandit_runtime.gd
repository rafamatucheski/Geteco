extends SceneTree
## Actual Main combat and streamed encounter; use --no-save --no-traffic --population=20.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const ENCOUNTER := preload("res://runtime/desert/DesertBanditEncounter.gd")
const CAMP := preload("res://world/desert/DesertBanditCamp.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var world: Node3D
var encounter: Node3D
var output := ""
var failures: Array[String]=[]
var checks := 0
var shots := 0
var damage_observed := 0.0
var log: Array[Dictionary]=[]
var hashes: Dictionary={}
var lifecycle: Array[Dictionary]=[]

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): failures.append("180s bandit fixture watchdog"); finish(3))
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks+=1
	print("DESERT_BANDIT ","PASS " if value else "FAIL ",label)
	if not value: failures.append(label)
	return value

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args() and "--no-traffic" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"isolated no-save/no-traffic native .NET run required"): finish(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-bandit-runtime")
	hashes=fingerprint()
	var arrival := CAMP.CENTER+Vector3(0,.08,48)
	var data := FIXTURE.full_snapshot(arrival,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[arrival.x,arrival.y,arrival.z]}
	data.world[ENCOUNTER.STATE_KEY]=ENCOUNTER.default_state()
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	if not check(not path.is_empty(),"new isolated completed-campaign save validates"): finish(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	var startup_began := Time.get_ticks_msec()
	var diagnostic_due := 0
	var deadline := Time.get_ticks_msec()+65000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if Time.get_ticks_msec()>=diagnostic_due:
			diagnostic_due=Time.get_ticks_msec()+1000
			record_lifecycle("startup-wait",Time.get_ticks_msec()-startup_began)
		if world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	record_lifecycle("startup-wait-ended",Time.get_ticks_msec()-startup_began)
	if not check(world.get("session")!=null and world.session.ready_for_play and world.production.store.path==path and world.session.controller.no_save,"real Main loads only fixture save"): finish(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not check(world.dispatch.router._native!=null and world.production.requested_population==20,"native backend and population20 active"): finish(1); return
	if world.session.modal: world.session.close_menu()
	encounter=world.session.desert.frontier.bandits
	if not check(is_instance_valid(encounter),"production frontier installs encounter"): finish(1); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.player.speed=3.5
	world.gameplay._rng.seed=6102026
	world.gameplay.npc_gunfire.connect(_gunfire)
	var admission_began := Time.get_ticks_msec()
	deadline=admission_began+10000
	diagnostic_due=0
	while encounter.live_count()<3 and Time.get_ticks_msec()<deadline:
		if Time.get_ticks_msec()>=diagnostic_due:
			diagnostic_due=Time.get_ticks_msec()+1000
			record_lifecycle("bandit-admission-wait",Time.get_ticks_msec()-admission_began)
		await physics_frame
	record_lifecycle("bandit-admission-ended",Time.get_ticks_msec()-admission_began)
	if not check(encounter.live_count()==3 and get_nodes_in_group("desert_bandits").size()==3,"exactly three physical bandits admitted"): finish(1); return
	await wait_seconds(.8)
	check(shots==0 and not encounter.snapshot().engaged,"camp remains watchful outside approach range")
	for actor in encounter.actors.values():
		check(actor.is_on_floor() and absf(actor.global_position.y)<.2,"bandit capsule rests on real desert floor")
	await photo("camp-before-approach")
	var health_before: float=world.gameplay.health
	if not await walk_to(CAMP.CENTER+Vector3(0,0,17),12): finish(1); return
	deadline=Time.get_ticks_msec()+10000
	while (shots<2 or world.gameplay.health>=health_before) and Time.get_ticks_msec()<deadline: await physics_frame
	damage_observed=health_before-float(world.gameplay.health)
	check(shots>=2 and damage_observed>0 and world.gameplay.health>0,"natural approach triggers actual projectiles and player damage")
	check(not world.session.desert.busy() and not world.player.input_locked,"bandit combat leaves normal player controls available")
	check(not encounter.save_block_reason().is_empty() and not world.session.save_block_reason().is_empty(),"combat blocks saving without marking drag busy")
	await photo("camp-active-combat")
	world.gameplay.toggle_god_mode()
	await wait_seconds(.3)
	var protected_health: float=world.gameplay.health
	var shot_before := shots
	await wait_seconds(2.2)
	check(shots>shot_before and is_equal_approx(float(world.gameplay.health),protected_health),"real incoming projectiles respect player god-mode protection")
	world.session._menu("Teste de pausa")
	await wait_seconds(.4)
	shot_before=shots
	await wait_seconds(1)
	check(shots==shot_before and encounter.snapshot().paused,"modal pause stops NPC firing")
	world.session.close_menu()
	world.session.state.grant_weapon("m4a1")
	world.session.state.add_ammo("m4a1",120)
	world.session.state.equip_weapon("m4a1")
	for index in [0,1]:
		var actor: CharacterBody3D=encounter.actors[index]
		if not await defeat_with_player_weapon(actor): finish(1); return
		check((int(world.session.state.world_state[ENCOUNTER.STATE_KEY].defeated_mask)&(1<<index))!=0,"real weapon kill persists its specific bandit slot")
	# Isola a cobertura real autoral de caixas com o ator vivo restante. Este
	# posicionamento da fixture não é evidência de contornar a caixa nem de voltar.
	var last: CharacterBody3D=encounter.actors[2]
	var cover := CAMP.CENTER+Vector3(5,0,5)
	var behind := cover+(cover-last.global_position).normalized()*5
	behind.y=.08
	world.player.teleport(behind)
	await wait_seconds(.7)
	world.gameplay.toggle_god_mode()
	var origin: Vector3=last.global_position+Vector3.UP*1.4
	var cover_ray := PhysicsRayQueryParameters3D.create(origin,world.player.global_position+Vector3.UP,7,[last.get_rid()])
	var cover_hit := world.get_world_3d().direct_space_state.intersect_ray(cover_ray)
	check(not cover_hit.is_empty() and cover_hit.collider!=world.player,"authored supply crate physically blocks enemy line of sight")
	shot_before=shots
	health_before=world.gameplay.health
	await wait_seconds(2.2)
	check(shots==shot_before and is_equal_approx(float(world.gameplay.health),health_before),"physical cover prevents bandit shots and damage")
	await photo("camp-crate-cover")
	# Sonda o ramo de morte/drop da produção de forma síncrona com uma semente aleatória
	# determinística. As duas primeiras mortes acima já exercitam armas reais do jogador.
	var rng := RandomNumberGenerator.new()
	var loot_seed := 1
	for candidate in range(1,65):
		rng.seed=candidate
		if rng.randf()<=float(world.gameplay.LOOT_WEAPON_CHANCE): loot_seed=candidate; break
	world.gameplay._rng.seed=loot_seed
	var loot_before: int=world.gameplay._loot.size()
	world.gameplay._damage(last,1000.0,world.player)
	check(last.dead and last.collision_layer==0 and not last.is_physics_processing(),"production damage API produces final bandit death and disables body collision")
	check(world.gameplay._loot.size()>loot_before,"production death creates real loot using deterministic normal-chance seed")
	check(int(world.session.state.world_state[ENCOUNTER.STATE_KEY].defeated_mask)==7 and encounter.live_count()==0 and encounter.save_block_reason().is_empty(),"all defeated slots persist and combat lock clears")
	await photo("camp-cleared-loot")
	var pickup: Node3D=world.gameplay._loot[loot_before] if world.gameplay._loot.size()>loot_before else null
	if is_instance_valid(pickup):
		await collect_loot_by_walking(pickup,last)
	var stored := STORE.new(); stored.path=output.path_join("cleared-save.json")
	check(stored.save(world.session.state)==OK,"cleared encounter writes valid isolated save")
	var restored := STATE.new()
	var loaded: Dictionary=stored.load_into(restored)
	check(loaded.get("ok",false) and int(restored.world_state[ENCOUNTER.STATE_KEY].defeated_mask)==7,"production SaveStore restores defeated mask")
	var invalid: Dictionary=world.session.state.snapshot().duplicate(true)
	invalid.world[ENCOUNTER.STATE_KEY].defeated_mask=8
	check(not STATE.new().restore_snapshot(invalid),"save validator rejects unknown defeated bits")
	var old_ids: Array[int]=[]
	for actor in encounter.actors.values(): old_ids.append(actor.get_instance_id())
	var old_camp: int=encounter.camp.get_instance_id()
	# Os posicionamentos de streaming de propósito não afirmam a travessia do acesso.
	world.player.teleport(CAMP.CENTER+Vector3(0,.08,135))
	await wait_seconds(.8)
	var freed := not is_instance_id_valid(old_camp)
	for instance_id in old_ids: freed=freed and not is_instance_id_valid(instance_id)
	check(freed and get_nodes_in_group("desert_bandits").is_empty(),"distance unload frees bandits, corpses and camp solids")
	world.session.state.world_state[ENCOUNTER.STATE_KEY]=restored.world_state[ENCOUNTER.STATE_KEY].duplicate(true)
	world.player.teleport(CAMP.CENTER+Vector3(0,.08,45))
	deadline=Time.get_ticks_msec()+8000
	while not is_instance_valid(encounter.camp) and Time.get_ticks_msec()<deadline: await physics_frame
	await wait_seconds(1.7)
	check(is_instance_valid(encounter.camp) and encounter.live_count()==0 and get_nodes_in_group("desert_bandits").is_empty(),"return and restored cleared save do not respawn defeated bandits")
	finish(0 if failures.is_empty() else 1)

func defeat_with_player_weapon(actor: CharacterBody3D) -> bool:
	var deadline := Time.get_ticks_msec()+8000
	var accepted := 0
	while not actor.dead and Time.get_ticks_msec()<deadline:
		world.gameplay.aim_point=actor.global_position+Vector3.UP
		if world.gameplay.fire_at(actor.global_position+Vector3.UP): accepted+=1
		await physics_frame
	return check(actor.dead and accepted>0,"production player weapon physically defeats bandit "+str(actor.slot))

func walk_to(point: Vector3, bound: float) -> bool:
	var deadline := Time.get_ticks_msec()+int(bound*1000)
	var reached := false
	while Time.get_ticks_msec()<deadline:
		var direction: Vector3 = point-world.player.global_position; direction.y=0
		if direction.length()<.25: reached=true; break
		world.player.automatic_direction=direction.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	return check(reached and world.player.is_on_floor(),"real Actor walks to supported encounter point")

func collect_loot_by_walking(pickup: Node3D, source: CharacterBody3D) -> bool:
	var item_point: Vector3=pickup.global_position
	var row := {"id":"physical-loot-collection","item_position":str(item_point),"item_path":str(pickup.get_path()),"item_kind":str(pickup.kind),"item_weapon":str(pickup.weapon_id),"source_position":str(source.global_position),"source_slot":int(source.slot),"source_dead":bool(source.dead),"production_pickup_radius":float(pickup.PICKUP_RADIUS)}
	# A tiny ground-level probe distinguishes an item hidden inside a prop from
	# a legitimate radius pickup beside one. Never waive a solid-overlap defect.
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new(); sphere.radius=.04
	probe.shape=sphere
	probe.transform=Transform3D(Basis.IDENTITY,item_point+Vector3.UP*.15)
	probe.collision_mask=1
	var solids: Array[String]=[]
	for hit in world.get_world_3d().direct_space_state.intersect_shape(probe,8):
		solids.append(str(hit.collider.get_path()))
	row["item_solid_overlaps"]=solids
	if not check(solids.is_empty(),"dropped loot center is outside solid camp props"):
		log.append(row)
		return false
	var start := Vector3.INF
	for direction in [Vector3.BACK,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD]:
		var candidate: Vector3=item_point+direction*3.0+Vector3.UP*.08
		if world.session.position_clear(candidate): start=candidate; break
	if not check(start.is_finite(),"loot approach starts with a clear physical player capsule"):
		log.append(row)
		return false
	# Só estabelece o início do diagnóstico; daí em diante o Actor se move normalmente.
	world.player.teleport(start)
	await wait_seconds(.2)
	start=world.player.global_position
	row["start_position"]=str(start)
	row["start_horizontal_distance"]=Vector2(start.x,start.z).distance_to(Vector2(item_point.x,item_point.z))
	var previous := start
	var travelled := 0.0
	var all_supported := true
	var collected := false
	var trace: Array[Dictionary]=[]
	var frames := 0
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<3000:
		var at: Vector3=world.player.global_position
		travelled+=previous.distance_to(at); previous=at
		all_supported=all_supported and world.player.is_on_floor()
		if frames%6==0: trace.append({"ms":Time.get_ticks_msec()-began,"position":str(at),"on_floor":world.player.is_on_floor()})
		if is_instance_valid(pickup) and pickup.consumed:
			collected=true
			break
		if not is_instance_valid(pickup): break
		var direction := item_point-at; direction.y=0
		world.player.automatic_direction=direction.normalized()
		await physics_frame
		frames+=1
	world.player.automatic_direction=Vector3.ZERO
	var end: Vector3=world.player.global_position
	row.merge({"end_position":str(end),"end_horizontal_distance":Vector2(end.x,end.z).distance_to(Vector2(item_point.x,item_point.z)),"travelled_m":travelled,"all_supported":all_supported,"end_on_floor":world.player.is_on_floor(),"collection_observed":collected,"duration_ms":Time.get_ticks_msec()-began,"trace":trace})
	log.append(row)
	var summary := row.duplicate(); summary.erase("trace")
	print("DESERT_BANDIT_LOOT_WALK ",JSON.stringify(summary))
	await photo("camp-loot-collected")
	return check(collected and travelled>1.0 and all_supported and world.player.is_on_floor(),"supported real walking contact collects dropped loot")

func _gunfire(_origin: Vector3, _direction: Vector3, shooter: Node3D) -> void:
	if shooter.is_in_group("desert_bandits"): shots+=1

func record_lifecycle(phase: String, elapsed_ms: int) -> void:
	var row := {"phase":phase,"elapsed_ms":elapsed_ms,"ticks_usec":Time.get_ticks_usec(),"physics_frame":Engine.get_physics_frames(),"render_frame":Engine.get_frames_drawn(),"tree_paused":paused}
	if not is_instance_valid(world): lifecycle.append(row); return
	var session: Node=world.get("session")
	var production: Node=world.get("production")
	var player: CharacterBody3D=world.get("player")
	var gameplay: Node3D=world.get("gameplay")
	if is_instance_valid(session):
		row.merge({"session_ready":session.ready_for_play,"modal":session.modal,"position_transition":session.has_position_transition(),"rescue_pending":session.rescue_pending,"respawn_busy":session.respawn_busy,"arrest_pending":session.arrest_pending})
		if session.state!=null: row.merge({"state_region":session.state.region_id,"state_place":session.state.place_id})
	if is_instance_valid(production):
		row.merge({"production_ready":production.ready_for_play,"startup_streaming_settled":production.startup_streaming_settled,"travel_busy":production.travel_busy,"save_invalid":production.save_invalid,"save_path":production.store.path,"requested_population":production.requested_population})
		var active_region: Node3D=production.get("region")
		if is_instance_valid(active_region):
			row["region_path"]=str(active_region.get_path())
			var region_script: Script=active_region.get_script()
			row["region_script"]=region_script.resource_path if is_instance_valid(region_script) else ""
			if row.region_script=="res://world/desert/DesertRegion.gd":
				row.merge({"region_prepared":active_region.prepared,"region_focus":str(active_region.focus),"region_current_cell":str(active_region.current_cell),"region_chunks":active_region.chunks.size(),"region_pending_cells":active_region.pending.size(),"region_build_jobs":active_region.build_jobs.size(),"region_streaming_idle":active_region.is_streaming_idle()})
	if is_instance_valid(gameplay): row["player_health"]=gameplay.health
	if is_instance_valid(player):
		row.merge({"player_position":str(player.global_position),"player_velocity":str(player.velocity),"player_on_floor":player.is_on_floor(),"player_dead":player.dead,"player_input_locked":player.input_locked,"player_physics":player.is_physics_processing(),"player_collision_layer":player.collision_layer,"player_collision_mask":player.collision_mask,"player_distance_to_camp":player.global_position.distance_to(CAMP.CENTER)})
		var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*.25,player.global_position-Vector3.UP*3,1)
		var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
		row["support_ray"]={"hit":not hit.is_empty(),"position":str(hit.position) if not hit.is_empty() else "none","normal":str(hit.normal) if not hit.is_empty() else "none","collider":str(hit.collider.get_path()) if not hit.is_empty() else "none"}
	if is_instance_valid(encounter):
		row["encounter"]=encounter.snapshot()
		row["encounter_processing"]=encounter.is_processing()
		row["encounter_process_mode"]=encounter.process_mode
		row["encounter_operational"]=encounter.operational()
		row["global_bandit_nodes"]=get_nodes_in_group("desert_bandits").size()
	lifecycle.append(row)
	print("DESERT_BANDIT_LIFECYCLE ",JSON.stringify(row))

func wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline: await physics_frame

func photo(id: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))

func fingerprint(reference: Dictionary={}) -> Dictionary:
	var result: Dictionary={}
	if not reference.is_empty():
		for path in reference: result[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
		return result
	for folder in ["res://runtime/desert","res://world/desert"]:
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".gd") or file.ends_with(".gdshader"): result[folder.path_join(file)]=FileAccess.get_sha256(folder.path_join(file))
	for path in ["res://gameplay/Gameplay.gd","res://gameplay/CobraAgent.gd","res://scripts/Actor.gd","res://runtime/FullSession.gd","res://runtime/ProductionWorld.gd",get_script().resource_path]: result[path]=FileAccess.get_sha256(path)
	return result

func finish(code: int) -> void:
	if is_instance_valid(world) and is_instance_valid(world.get("player")): world.player.automatic_direction=Vector3.ZERO
	var end_hashes := fingerprint(hashes)
	if not hashes.is_empty() and hashes!=end_hashes: failures.append("Source changed during combat fixture")
	if code==0 and not failures.is_empty(): code=1
	if not output.is_empty():
		var report := {"checks":checks,"failures":failures,"shots":shots,"player_damage_observed":damage_observed,"encounter":encounter.snapshot() if is_instance_valid(encounter) else {},"source_stable":hashes==end_hashes,"source_sha256_start":hashes,"source_sha256_end":end_hashes,"scope":"Main .NET real approach, NPC projectiles, player-weapon kills, cover, god-mode and modal pause. Final deterministic loot death uses production damage API; cover/streaming placements are diagnostics, not access traversal. Separate FPS and temporal visual validation required."}
		report["physical_diagnostics"]=log
		report["lifecycle_diagnostics_1hz"]=lifecycle
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DESERT_BANDIT_DONE ",output," code=",code)
	quit(code)
