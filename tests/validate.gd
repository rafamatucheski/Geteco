extends SceneTree

var failures: Array[String] = []
var checks := 0
var world

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	await frames(10)
	check(world.people.size() == 24,"Slice fixture starts with its authored population")
	check(world.find_children("*","SubViewport",true,false).is_empty(),"World must not contain per-actor viewports")
	check(world.find_children("*","CollisionObject2D",true,false).is_empty(),"World physics must be 3D")
	check(world.player.animation.has_animation("Running") and world.player.animation.has_animation("Walking"),"Original Dante locomotion must be present")
	check(world.player.is_on_floor(),"Dante must spawn on the floor")
	check(not world.player.test_move(world.player.global_transform,Vector3(0.1,0,0)),"Dante spawn must be clear")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.7
	for actor in world.people:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY,actor.position+Vector3(0,0.87,0))
		query.collision_mask = 3
		query.exclude = [actor.get_rid()]
		check(world.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"Citizen spawn must be clear: "+actor.name)
		check(actor.is_on_floor(),"Citizen must stand on floor: "+actor.name)
	# Sweep actual player/NPC bodies across representative solids, including
	# a displacement large enough to cross the full object in one step.
	for actor in [world.player,world.people[0]]:
		for solid in world.street.solids:
			if solid.name == "Ground": continue
			var dimensions: Vector3 = solid.get_meta("footprint")
			for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
				var half := dimensions.x/2 if direction.x != 0 else dimensions.z/2
				var start: Vector3 = solid.position+direction*(half+1)
				start.y = 0.04
				var transform := Transform3D(Basis.IDENTITY,start)
				check(actor.test_move(transform,-direction*(half*2+2)),"Swept body must hit solid: "+solid.name)
	var player = world.player
	player.controlled_automatically = true
	player.teleport(Vector3(-10,0.04,5))
	player.automatic_direction = Vector3.FORWARD
	await frames(150)
	check(player.position.z >= 2.9,"Player must not walk through crate")
	check(absf(player.position.y) < 0.08,"Player must not climb onto crate")
	player.automatic_direction = Vector3.ZERO
	player.teleport(Vector3(0,0.04,0))
	player.controlled_automatically = false
	var input_event := InputEventKey.new()
	input_event.physical_keycode = KEY_W
	input_event.pressed = true
	Input.parse_input_event(input_event)
	await frames(60)
	input_event.pressed = false
	Input.parse_input_event(input_event)
	check(player.position.z < -2.5,"W input must move the real character")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var old_size: float = world.camera.target_size
	world.camera._unhandled_input(wheel)
	# V1 não tinha zoom manual; a roda é da troca de arma e da rádio.
	check(is_equal_approx(world.camera.target_size,old_size),"Mouse wheel must not zoom the camera")
	var rotation_event := InputEventKey.new()
	# `camera_left` é Z desde que Q virou `weapon_next` (GameInput).
	rotation_event.physical_keycode = KEY_Z
	rotation_event.pressed = true
	world.camera._unhandled_input(rotation_event)
	check(is_equal_approx(world.camera.heading,PI/4),"Z must rotate camera")
	world._toggle_pause()
	check(paused and world.pause_panel.visible,"Pause must stop simulation and show menu")
	world._toggle_pause()
	check(not paused and not world.pause_panel.visible,"Resume must restore simulation")
	player.teleport(Vector3(-8.3,0.04,3))
	# A full loop, using actual collision-aware NPC movement, must remain open.
	var distances: Array[float] = []
	for actor in world.people: distances.append(actor.travelled)
	await frames(3900)
	for i in world.people.size():
		var actor = world.people[i]
		print("ROUTE ",actor.name," distance=",actor.travelled-distances[i]," position=",actor.position)
		check(actor.travelled-distances[i] > 95,"Citizen must complete a city-block loop: "+actor.name)
		check(absf(actor.position.y) < 0.08,"Citizen must remain at floor level")
	world.set_population(100)
	await frames(5)
	check(world.people.size() == 100,"Population can increase to 100")
	for i in world.people.size():
		for j in range(i+1,world.people.size()):
			check(world.people[i].position.distance_to(world.people[j].position) >= 0.59,"Adding population must not spawn overlapping bodies")
	world.set_population(0)
	await frames(5)
	check(world.people.is_empty(),"Population removal must free actors")
	world.set_population(100)
	await frames(5)
	check(world.people.size() == 100,"Population can be restored")
	var report := {"checks":checks,"failures":failures,"physics_frames":Engine.get_physics_frames(),"engine":Engine.get_version_info().string}
	var output := FileAccess.open("res://evidence/functional.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("VALIDATION ",JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
