extends SceneTree
## Main/.NET real e checkpoint isolado. As checagens funcionais não certificam FPS.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var checks := 0
var failures: Array[String] = []
var output := ""
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("TRACK_THEFT timeout"); quit(3))
	run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	print("TRACK_THEFT ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok
func frames(count: int) -> void:
	for i in count: await physics_frame
func photo(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	var desert := "--desert" in OS.get_cmdline_user_args()
	var at := Vector3(-976,.08,-1264) if desert else Vector3(-220,.2,-30)
	output = FIXTURE.output_dir("track-theft-desert" if desert else "track-theft-motocross")
	var snapshot := FIXTURE.full_snapshot(at,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	if desert:
		snapshot.region_id = "desert"
		snapshot.world.pedestrian = {"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session != null and world.session.ready_for_play and world.production.store.path==path and not world.production.save_invalid,"real isolated Main is ready"): quit(1); return
	await frames(180)
	if desert: await desert_case()
	else: await motocross_case()
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"functional_only":true}))
	world.queue_free()
	await process_frame
	print("TRACK_THEFT_RESULT checks=",checks," failures=",failures," evidence=",output)
	quit(0 if failures.is_empty() else 1)

func motocross_case() -> void:
	var mx = world.session.motocross
	var venue = get_first_node_in_group("motocross_paddock")
	if not check(is_instance_valid(venue) and mx.ambient.rows.size()==3,"paddock and three riding NPCs streamed in"): return
	var balance: int = world.session.state.economy.balance
	var bike = venue.parked_bikes[0]
	world.player.teleport(bike.global_position+Vector3(-1.7,.05,0))
	if not check(world.driving.interact() and mx.player_bike==bike,"vehicle button steals the displayed bike in front of Digo"): return
	check(bike.get_parent()==world and bike.is_physics_processing() and mx.mounted,"stolen display is a live player bike independent of its chunk")
	await photo("stolen-paddock-bike")
	check(world.session.state.economy.balance==balance and not mx.active,"theft charges no rental and starts no paid race")
	await frames(20)
	bike.speed=0
	if not check(mx.dismount(),"player can dismount the stolen bike on the actual paddock floor"): return
	check(is_instance_valid(bike) and not bike.rider.visible,"stolen bike survives dismount for later use")
	var row: Dictionary = mx.ambient.rows[0]
	var moving = row.bike
	moving.set_physics_process(false)
	world.player.teleport(moving.global_position+Vector3(1.5,.05,0))
	if not check(mx.perform("steal") and mx.player_bike==moving,"player can steal a real practice rider's bike"): return
	check(mx.ambient.rows.size()==2 and mx.ambient.retired==1 and not moving.is_queued_for_deletion(),"AI relinquishes only the stolen rider, without deleting the bike")
	await frames(70)
	check(mx.ambient.rows.size()==2,"missing rider is not replaced in front of the thief")
	moving.reset_to(Transform3D(Basis.IDENTITY,Vector3(-500,.2,-30)))
	# Tira também o primeiro expositor roubado da baia dele, preservando os dois suportes.
	bike.reset_to(Transform3D(Basis.IDENTITY,Vector3(-500,.2,-34)))
	await frames(80)
	check(mx.ambient.rows.is_empty() and is_instance_valid(moving),"leaving the venue unloads AI while keeping the stolen mount")
	if is_instance_valid(venue): check(venue.parked_bikes[0]!=bike and venue.parked_bikes[0].get_parent()==venue,"leaving replenishes the stolen display even if its chunk is still loaded")
	# A volta da fixture exercita a posse do streaming; isto não é prova de rota dirigida.
	moving.reset_to(Transform3D(Basis.IDENTITY,Vector3(-220,.2,-32)))
	world.production.region.set_focus(moving.position)
	await frames(240)
	check(mx.ambient.rows.size()==3,"return to the venue replenishes the riding NPCs")
	await photo("motocross-return")

func desert_case() -> void:
	var story = world.session.desert.story
	var crew = world.session.desert.meet_life
	var progress: Dictionary = story.STATE.data(world.session.state.world_state).duplicate(true)
	if not check(story.actors.has("vicente") and crew.members.size()>0,"story participants and crew exist at the real meet"): return
	var vicente = story.actors.vicente
	world.gameplay._damage(vicente,200,world.player)
	check(vicente.dead and vicente.health==0 and vicente.collision_layer==0,"production damage can kill Vicente at the track")
	var member = crew.members.values()[0]
	world.gameplay._damage(member,200,world.player)
	check(member.dead,"production damage can kill the formerly protected entourage")
	var everyone_dead := true
	for actor in story.actors.values():
		world.gameplay._damage(actor,200,world.player)
		everyone_dead = everyone_dead and actor.dead
	for actor in crew.members.values():
		world.gameplay._damage(actor,200,world.player)
		everyone_dead = everyone_dead and actor.dead
	check(everyone_dead,"all present meet contacts, crew and guests can die")
	var takeshi = world.session.desert.drag.takeshi_meet
	if check(is_instance_valid(takeshi.actor),"optional Takeshi encounter exists"):
		world.gameplay._damage(takeshi.actor,200,world.player)
		check(takeshi.actor.dead,"Takeshi at the strip also accepts lethal damage")
	var spectators := get_nodes_in_group("desert_drag_strip_spectator")
	var spectator_slot: Node3D
	if not spectators.is_empty():
		var spectator = spectators[0]
		spectator_slot = spectator.get_parent()
		world.gameplay._damage(spectator,200,world.player)
		check(spectator.dead,"strip spectators accept production lethal damage")
	await frames(30)
	check(story.nearest_action().get("target","")!="vicente" and crew.retired.size()>0,"dead participants cannot converse and remain retired for this visit")
	var display
	for candidate in get_nodes_in_group("stealable_meet_cars"):
		if candidate.has_method("materialize_vehicle") and candidate.archetype=="desert_faisca_rally":
			display = candidate
			break
	if not check(is_instance_valid(display),"parked meet cars expose real vehicle interaction"): return
	check(world.gameplay.changed.is_connected(display._on_changed),"initially streamed display is bound to the production recovery signal")
	world.production.region.prepare_collision_at(display.global_position)
	world.player.teleport(display.driver_door_anchor(1)+Vector3(.25,.05,0))
	await physics_frame
	if not check(world.driving.interact(),"public vehicle button steals a parked meet car"):
		print("TRACK_THEFT_ENTRY_DIAGNOSTIC ",{"world_bound":is_instance_valid(display.world),"option":str(world.driving._entry_option()),"modal":world.session.modal,"blocked":world.session.is_transition_blocked(),"locked":world.player.input_locked,"health":world.gameplay.health,"display_point":str(display.global_position),"player_point":str(world.player.position)})
		return
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active(): break
	var car = world.driving.car
	check(world.driving.occupied and car==display.activated and car.controlled and not display.visible,"stolen display becomes a driveable vehicle with normal boarding")
	check(car.archetype==display.archetype and car.get_meta("track_visit_vehicle",false),"theft preserves the authored car model")
	var damaged_display
	for candidate in get_nodes_in_group("stealable_meet_cars"):
		if candidate!=display and candidate.is_visible_in_tree() and candidate.global_position.distance_to(car.global_position)<30:
			damaged_display = candidate
			break
	if check(is_instance_valid(damaged_display),"another parked car is available for weapon damage"):
		world.gameplay._damage(damaged_display,20,world.player)
		await frames(3)
		check(is_instance_valid(damaged_display.activated) and damaged_display.activated.health<damaged_display.activated.max_health,"production weapon damage activates and damages the parked car")
	await photo("stolen-meet-car")
	# Usa morte/resgate de produção, não um reinício direto dos dicionários do encontro.
	world.gameplay.damage_player(1000)
	for i in 1800:
		await physics_frame
		if world.gameplay.health>0 and not world.session.rescue_pending and not world.session.respawn_busy: break
	check(world.gameplay.health==100 and not world.driving.occupied and not world.session.rescue_pending,"production death restores Dante and driving controls")
	check(story.STATE.data(world.session.state.world_state)==progress,"killing story participants preserves campaign progress")
	world.production.region.set_focus(Vector3(-976,.08,-1264))
	world.production.region.prepare_collision_at(Vector3(-976,.08,-1264))
	world.player.teleport(Vector3(-976,.08,-1264))
	await frames(480)
	check(story.actors.has("vicente") and not story.actors.vicente.dead and crew.retired.is_empty(),"return after death restores story characters and crew")
	var replacements := 0
	for candidate in get_nodes_in_group("stealable_meet_cars"):
		if candidate.has_method("materialize_vehicle") and candidate.is_visible_in_tree(): replacements+=1
	check(replacements>0,"parked vehicles are replenished after recovery")
	check(is_instance_valid(takeshi.actor) and not takeshi.actor.dead,"optional encounter is restored after Dante's recovery")
	if is_instance_valid(spectator_slot): check(is_instance_valid(spectator_slot.actor) and not spectator_slot.actor.dead,"surviving strip slot restores its killed spectator after recovery")
	await photo("desert-return")
