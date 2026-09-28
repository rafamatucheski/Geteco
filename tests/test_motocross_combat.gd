extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("MOTOCROSS_COMBAT_NOT_READY: production session did not become ready within 2400 physics frames; no gameplay assertions executed")
		world.queue_free()
		await process_frame
		quit(1)
		return
	world.player.teleport(Vector3(-224,.2,-30))
	world.production.region.set_focus(world.player.position)
	for i in 180: await physics_frame
	var actors := get_nodes_in_group("motocross_spectator")
	check(actors.size()==10,"actual park has keeper, three drinkers and six boat spectators")
	var venue = get_first_node_in_group("motocross_paddock")
	var npc = venue.drinkers[0]
	check(npc.model.get_script()==preload("res://assets/CivilianModel.gd"),"park resident uses the normal CivilianModel")
	var from: Vector3 = npc.global_position+Vector3(0,1.0,2.5)
	var toward: Vector3 = npc.global_position+Vector3(0,1.0,0)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,toward,7))
	check(not hit.is_empty() and hit.collider==npc,"real bullet mask hits the seated resident above the bench")
	world.gameplay._damage(npc,12,world.player)
	check(npc.health==88 and npc.frightened,"actual combat dispatcher damages and alarms resident")
	var parked = venue.parked_bikes[0]
	world.gameplay._damage(parked,10,world.player)
	check(parked.health<100 and parked.visual.rotation.z>-.12,"parked rental bike visibly reacts to weapon damage")
	check(world.gameplay._impact_material(parked)=="metal","bullet impacts use metal effects on motorcycle")
	var mx = world.session.motocross
	check(mx.ambient.rows.size()==3,"ambient riders still exist during the gunfire fixture")
	var rider = mx.ambient.rows[0].bike
	world.gameplay.weapon_fired.emit("pistol",rider.global_position+Vector3(2,0,0))
	check(rider._threat_time>0,"nearby shots trigger caution and flinch in a real riding opponent")
	world.gameplay._damage(rider,20,world.player)
	check(rider.crash_state=="fallen" and rider.health<100,"a shot can physically knock a riding opponent off the motorcycle")
	world.queue_free()
	await process_frame
	print("MOTOCROSS_COMBAT_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
