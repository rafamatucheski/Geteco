extends SceneTree

var world
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): print("FAIL timeout"); quit(2))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	check(session != null and session.ready_for_play,"session ready")
	if not failures.is_empty(): quit(1); return
	var gameplay = world.gameplay
	check(await session.enter_place("harbor_police",false),"enter precinct")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	await frames(20)
	check(gameplay.stars == 0,"unarmed visit creates no wanted level")
	check(session.room_npcs.size() == 5,"all original residents present")
	for actor in session.room_npcs:
		var hp: float = actor.health
		actor.receive_damage(10000,world.player)
		gameplay._damage(actor,10000,world.player)
		gameplay._damage(actor,10000,world.player,true)
		check(not actor.dead and actor.health == hp,"resident survives direct, combat and continuous damage: " + str(actor.get_meta("interior_npc_id")))
	session.state.grant_weapon("pistol")
	session.state.add_ammo("pistol",100)
	session.state.equip_weapon("pistol")
	await frames(20)
	check(gameplay.stars >= 1,"drawing weapon summons police without firing")
	var points: int = gameplay.crime_points
	await frames(60)
	check(gameplay.crime_points == points,"holding weapon does not accumulate crimes per frame")
	check(gameplay.hidden_time < 1.0,"visible weapon keeps police informed")
	check(gameplay.fire_at(world.player.global_position+Vector3(0,1,-8)),"actual shot accepted")
	check(gameplay.stars >= 2,"first shot immediately escalates police response")
	for i in 1200:
		if not world.dispatch.events_named("dispatched").is_empty(): break
		await physics_frame
	check(not world.dispatch.events_named("dispatched").is_empty(),"real dispatch sends a vehicle")
	check(world.dispatch.player_position_override.distance_to(session.return_point)<.01,"dispatch targets precinct exterior")
	var resident = session.room_npcs[0]
	gameplay.explode(resident.global_position+Vector3.UP,2.0,10000,world.player,false)
	gameplay._ignite_actor(resident,world.player)
	await frames(60)
	check(not resident.dead and resident.health == 100,"mission officer survives actual explosion and burning ticks")
	session.state.equip_weapon("fists")
	gameplay.clear_wanted()
	await frames(30)
	check(gameplay.stars == 0,"holstered weapon stops precinct reports")
	world.player.teleport(session.room.interaction_points.police + Vector3(0,.06,.9))
	await frames(3)
	check(session.services.perform("police"),"mission officer remains available for dialogue")
	while session.dialogue_open: session._advance_dialogue()
	check(session.leave_place(),"leave precinct")
	session.state.equip_weapon("pistol")
	await frames(30)
	check(gameplay.stars == 0,"precinct rule does not report drawing outside")
	check(await session.enter_place("harbor_police",false),"reenter precinct")
	await frames(20)
	check(gameplay.stars >= 1,"entering with weapon already drawn also summons police")
	for actor in session.room_npcs:
		actor.receive_damage(10000,world.player)
		check(not actor.dead,"protection persists after reentry: " + str(actor.get_meta("interior_npc_id")))
	print("PRECINCT_THREAT ","PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)
