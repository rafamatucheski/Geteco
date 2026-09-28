extends "res://tests/test_harbor_life.gd"
const WORKER := preload("res://gameplay/urban_v1/PortWorker.gd")
func run() -> void:
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	world.player.controlled_automatically=true
	world.player.teleport(Vector3(253,.1,218))
	world.production.region.set_focus(world.player.position)
	world.session.urban_operations.security.authorized_visit=true
	for i in 30: await physics_frame
	var spec: Dictionary={"id":"south_port_worker_test","kind":"dock_worker","region":"harbor","place_id":"","position":Vector3(250,.05,217),"route":[Vector3(250,.05,217),Vector3(255,.05,217),Vector3(255,.05,215),Vector3(250,.05,215)],"worker_index":4}
	var director=world.session._routine_director()
	director.set_process(false)
	director._spawn(spec)
	check(director.actors.has(spec.id),"port worker admitted on clear floor")
	if not director.actors.has(spec.id): world.free(); quit(1); return
	var worker=director.actors[spec.id]
	for i in 100: await physics_frame
	var moving:=Vector3(worker.velocity.x,0,worker.velocity.z)
	check(moving.length()>.5,"worker walks cargo route")
	check(worker.model.global_basis.z.normalized().dot(moving.normalized())>.85,"worker faces movement rather than walking backwards")
	check(worker.carried_crate.get_parent()==worker.model,"crate follows worker facing")
	worker.receive_damage(NAN)
	check(worker.health==100,"invalid damage rejected")
	# The normal weapon ray hits the physical worker capsule.
	var from: Vector3=worker.global_position+Vector3(0,1,3)
	var query:=PhysicsRayQueryParameters3D.create(from,worker.global_position+Vector3.UP,2)
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
	check(hit.get("collider")==worker,"weapon ray reaches worker")
	worker.receive_damage(40,world.player)
	check(worker.health==60 and not worker.dead,"worker takes nonlethal damage")
	worker.receive_damage(1000,world.player)
	check(worker.dead and worker.collision_layer==0,"worker dies and releases physical obstruction")
	check(director.port_respawn.get(spec.id,0)==180,"dead worker waits three minutes")
	worker.queue_free()
	await physics_frame
	director._spawn(spec)
	check(not director.actors.has(spec.id),"streaming does not bypass death cooldown")
	director.port_respawn[spec.id]=0.0
	world.camera.set_process(false)
	world.camera.position=spec.position+Vector3(0,20,20)
	world.camera.look_at(spec.position)
	director._spawn(spec)
	check(not director.actors.has(spec.id),"respawn waits while original post is visible")
	world.camera.position+=Vector3(0,0,200)
	director._spawn(spec)
	check(director.actors.has(spec.id),"worker returns offscreen after cooldown")
	if director.actors.has(spec.id):
		worker=director.actors[spec.id]
		check(not worker.dead and worker.health==100,"replacement resumes alive")
		worker.queue_free()
		director.actors.erase(spec.id)
	await physics_frame
	# Full vehicle shape sweep -> flight -> lethal landing, using the production contact system.
	var victim:=WORKER.new()
	victim.configure({"id":"impact_port_worker","kind":"dock_worker","position":Vector3(250,.05,217),"stationary":true})
	world.add_child(victim)
	var car:=preload("res://scripts/Vehicle.gd").new()
	car.archetype="sedan"
	world.add_child(car)
	car.set_physics_process(false)
	car.global_position=victim.global_position+Vector3(0,0,car.half_length+.55)
	var street: Node
	for node in world.get_children():
		if node.get_script()==preload("res://gameplay/street_physics/StreetPhysics.gd"): street=node
	for i in 5: await physics_frame
	check(street!=null,"production vehicle contact system available")
	if street!=null:
		street._people_cache=street._collect_people()
		street._hit_people(car,Vector3(0,0,-18),Vector3(0,0,-1.5))
		check(victim.has_meta("street_flying"),"car sweep launches port worker")
		for i in 240:
			await physics_frame
			if victim.dead: break
		check(victim.dead,"fast runover kills worker through normal landing damage")
	var urban=world.session.urban_operations
	var guard=urban.security._staff[0]
	guard.receive_damage(1000)
	check(guard.dead and urban.security._staff_respawn[0]>179,"port gate staff die and enter respawn cooldown")
	var saved: Dictionary=urban.snapshot()
	check(urban.validate_snapshot(saved),"port lifecycle save validates")
	check(urban.restore_snapshot(saved),"port lifecycle restores with cooldowns")
	check(not world.maciota_place.maciota.has_method("receive_damage"),"Maciota keeps protected contract")
	world.free()
	await process_frame
	print("PORT_WORKER_COMBAT failures=",failures)
	quit(0 if failures.is_empty() else 1)
