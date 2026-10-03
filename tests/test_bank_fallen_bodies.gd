extends SceneTree
const ACTOR := preload("res://runtime/RobberyActor.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	Engine.max_fps = 60
	create_timer(20).timeout.connect(func(): push_error("Bank corpse test timeout"); quit(3))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func bounds(actor: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in actor.visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func run() -> void:
	var bank := PLACES.create_place("harbor_bank")
	root.add_child(bank)
	var actors: Array = []
	for index in 3:
		var actor := ACTOR.new()
		actor.guard = index == 0
		actor.female = index == 1
		actor.health = 160.0 if actor.guard else 100.0
		actor.position = Vector3(-5,0,.5) if index == 0 else Vector3(-2.65 if index == 1 else 2.65,0,-1.9)
		bank.add_child(actor)
		actors.append(actor)
	var fuel_room := Node3D.new()
	fuel_room.position = Vector3(30,2.5,0)
	root.add_child(fuel_room)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(12,.2,12)
	floor_shape.shape = floor_box
	floor_shape.position.y = -.1
	floor_body.add_child(floor_shape)
	fuel_room.add_child(floor_body)
	var cashier := ACTOR.new()
	cashier.fuel = true
	fuel_room.add_child(cashier)
	actors.append(cashier)
	for frame in 5: await process_frame
	await physics_frame
	var floor_levels: Array[float] = []
	for actor in actors:
		var ground: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * .2, actor.global_position + Vector3.DOWN, 1))
		floor_levels.append(float(ground.position.y))
		check(bounds(actor).size.y > 1.4, "live actor has complete visible standing rig")
		actor.receive_damage(10)
		check(not actor.dead and actor.collision_layer == 2, "nonlethal damage keeps actor standing and physical")
		actor.receive_damage(200)
		check(actor.dead and actor.collision_layer == 0, "lethal damage disables standing capsule")
	var lowest: Array[float] = [INF,INF,INF,INF]
	var settling := create_timer(1.3)
	while settling.time_left > 0.0:
		await process_frame
		for index in actors.size():
			var actor = actors[index]
			var height := floor_levels[index]
			lowest[index] = minf(lowest[index], bounds(actor).position.y - height)
	for index in actors.size():
		var actor = actors[index]
		var floor_y := floor_levels[index]
		var body := bounds(actor)
		print("CORPSE index=", index, " floor=", actor._floor_y, " bounds=", body, " lowest=", lowest[index], " rotation=", actor.visual.rotation, " pending=", actor._fall_meshes.size())
		check(lowest[index] >= -.015, "fall never sinks any visible body part through the supporting floor")
		check(absf(body.position.y - floor_y - .012) < .012, "corpse rests on its actual floor, including elevated fuel floor")
		check(body.size.y < .95 and maxf(body.size.x, body.size.z) > 1.1, "dead rig lies flat with its full body visible")
		check(not actor.has_meta("destroyed_cleanup"), "interior corpse is not removed and respawned by street cleanup")
	var bank_blood = bank.get_node_or_null("RobberyBlood")
	var fuel_blood = fuel_room.get_node_or_null("RobberyBlood")
	print("BLOOD bank=", bank_blood, " fuel=", fuel_blood, " elapsed=", Time.get_ticks_msec())
	check(bank_blood != null and bank_blood.stains.size() == 3, "one real blood pool per bank corpse")
	check(fuel_blood != null and fuel_blood.stains.size() == 1, "fuel cashier receives the same death blood")
	if bank_blood != null and fuel_blood != null:
		for blood in [bank_blood, fuel_blood]:
			for stain in blood.stains:
				check(stain.lethal and stain.node.visible and stain.node.mesh.get_surface_count() > 0, "blood pool uses rendered organic geometry")
				check(absf(stain.point.y - (floor_levels[3] if blood == fuel_blood else floor_levels[0]) - .05) < .01, "blood pool lies above the supporting floor")
	# Restoring a saved dead guard produces a supported corpse without replaying
	# a standing frame or requiring a fresh hit to create blood.
	var restored := ACTOR.new()
	restored.guard = true
	restored.health = 0
	restored.position = Vector3(5,0,.5)
	bank.add_child(restored)
	for frame in 4: await process_frame
	check(restored.dead and bounds(restored).size.y < .95 and bounds(restored).position.y >= -.01, "restored corpse is immediately supported and prone")
	check(bank_blood != null and bank_blood.stains.size() == 4, "restored dead guard also has a single pool")
	var bank_pool: WeakRef = weakref(bank_blood)
	var fuel_pool: WeakRef = weakref(fuel_blood)
	bank.queue_free()
	fuel_room.queue_free()
	await process_frame
	check(bank_pool.get_ref() == null and fuel_pool.get_ref() == null, "leaving rooms removes their bodies and blood together")
	for failure in failures: push_error(failure)
	print("%s bank fallen bodies: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
