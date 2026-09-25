extends SceneTree
var world
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func go(local_point: Vector3) -> void:
	var target: Vector3 = world.maciota_place.interior_origin+local_point
	var arrived := false
	for frame in 600:
		var direction: Vector3 = target-world.player.position
		direction.y = 0
		if direction.length() < .18:
			arrived = true
			break
		world.player.automatic_direction = direction.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	if not arrived: failures.append("Cannot walk to %s; stopped at %s" % [local_point,world.player.position-world.maciota_place.interior_origin])
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	# A sessão integrada (FullSession) substituiu o V2Session da primeira base:
	# espera ficar jogável e entra na garagem pela transição real de lugar.
	for i in 600:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not await world.session.enter_place("maciota",false):
		push_error("V2_WALK cannot enter the Maciota garage")
		print("V2_WALK FAIL failures=1")
		world.free()
		quit(1)
		return
	world.player.controlled_automatically = true
	world.player.speed = 3.5
	for point in [Vector3(0,0,2.5),Vector3(1,0,1.5),Vector3(3.4,0,1.5),Vector3(3.4,0,-.55),Vector3(3.4,0,1.5),Vector3(1,0,1.5),Vector3(0,0,2.5),Vector3(-2.9,0,2.5),Vector3(-2.9,0,-.15),Vector3(-2.9,0,2.5),Vector3(0,0,2.5),Vector3(0,0,-2.65),Vector3(.75,0,-2.65),Vector3(0,0,-2.65),Vector3(0,0,3.2)]:
		await go(point)
	for failure in failures: push_error(failure)
	print("V2_WALK ","PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	world.free()
	quit(0 if failures.is_empty() else 1)
