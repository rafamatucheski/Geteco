extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	var place = load("res://world/maciota/MaciotaPlace.gd").new()
	root.add_child(place)
	place.set_interior_active(true)
	await physics_frame
	await physics_frame
	var probe := CharacterBody3D.new()
	probe.collision_layer = 2
	probe.collision_mask = 3
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	collision.shape = capsule
	collision.position.y = .87
	probe.add_child(collision)
	root.add_child(probe)
	await physics_frame
	for key in ["spawn","exit","maciota","mechanic","workbench","part"]:
		var point: Vector3 = place.interior_spawn if key == "spawn" else (place.exit_position if key == "exit" else place.interaction_points[key])
		probe.global_position = point + Vector3(0,.04,0)
		check(probe.move_and_collide(Vector3(0,.001,0),true) == null,"Blocked approach: "+key)
	probe.collision_mask = 1
	for resident in [place.maciota,place.mechanic]:
		probe.global_position = resident.global_position + Vector3(0,.04,0)
		check(probe.move_and_collide(Vector3(0,.001,0),true) == null,"Resident inside furniture: " + resident.name)
		check(not resident.has_method("take_damage") and not resident.has_method("die"),"Resident exposed to damage")
	# Swept full player body: rear wall, desk and free office doorway.
	for sweep in [
		[Vector3(0,0,-2.5),Vector3(0,0,-5),true,"rear wall"],
		[Vector3(4.4,0,-.55),Vector3(0,0,-2.5),true,"desk footprint"],
		[Vector3(1.2,0,1.5),Vector3(2,0,0),false,"office doorway"]
	]:
		probe.global_position = place.interior_origin + sweep[0] + Vector3(0,.04,0)
		var hit := probe.move_and_collide(sweep[1],true)
		check((hit != null) == sweep[2],"Unexpected swept collision: "+sweep[3])
	check(place.solid_bodies.size() > 20,"Missing furniture solids")
	# Ampliação de 21/10/2026: parede esquerda nova bloqueia; a linha da antiga ficou aberta.
	for sweep in [
		[Vector3(-7.0,0,0),Vector3(-3,0,0),true,"new left wall"],
		[Vector3(-3.4,0,3.0),Vector3(-2.6,0,0),false,"workshop extension open past the old wall"]
	]:
		probe.global_position = place.interior_origin + sweep[0] + Vector3(0,.04,0)
		var extension_hit := probe.move_and_collide(sweep[1],true)
		check((extension_hit != null) == sweep[2],"Unexpected swept collision: "+sweep[3])
	# Escada da cobertura autorada na parede dos fundos da área de peças: ponto livre, rota do
	# spawn sem cruzar móvel e a escada (0,74 m atrás do ponto) sem invadir parede ou estante.
	var workshop: Node3D = place.room
	var stand: Vector3 = workshop.to_global(workshop.roof_access_point)
	probe.collision_mask = 3 # móveis e moradores (mecânico, Maciota)
	probe.global_position = stand + Vector3(0,.04,0)
	check(probe.move_and_collide(Vector3(0,.001,0),true) == null,"Blocked roof ladder stand")
	var previous: Vector3 = place.interior_spawn
	var route: Array = workshop.roof_access_route.duplicate()
	route.append(workshop.roof_access_point)
	for waypoint: Vector3 in route:
		var next: Vector3 = workshop.to_global(waypoint)
		probe.global_position = previous + Vector3(0,.04,0)
		check(probe.move_and_collide(next - previous,true) == null,"Roof ladder route blocked toward "+str(waypoint))
		previous = next
	var ladder := PhysicsShapeQueryParameters3D.new()
	var ladder_box := BoxShape3D.new()
	ladder_box.size = Vector3(.9,2.35,.18)
	ladder.shape = ladder_box
	ladder.collision_mask = 1
	var ladder_frame: Basis = workshop.global_basis*Basis(Vector3.UP,workshop.roof_access_yaw)
	ladder.transform = Transform3D(ladder_frame,stand+Vector3.UP*.04+ladder_frame*Vector3(0,1.22,.74))
	check(place.get_world_3d().direct_space_state.intersect_shape(ladder,1).is_empty(),"Roof ladder intersects wall or furniture")
	check((ladder_frame*Vector3.BACK).dot(Vector3.FORWARD) > .99,"Roof ladder does not face the rear wall")
	# Enquadramento: a sala inteira cabe e ocupa quase toda a altura ou a largura da tela.
	var back: Vector3 = place.camera_offset.normalized()
	var right := Vector3.UP.cross(back).normalized()
	var up := back.cross(right)
	var framed: AABB = place.room_bounds
	framed.position.y = -.4
	framed.size.y = 4.2
	for aspect in [4.0/3.0, 16.0/9.0, 3440.0/1440.0]:
		var size: float = place.camera_size_for_aspect(aspect)
		var low := Vector2(INF,INF)
		var high := -low
		for corner in 8:
			var relative: Vector3 = place.to_global(place.interior_origin+framed.get_endpoint(corner)) - place.camera_target
			low = low.min(Vector2(relative.dot(right),relative.dot(up)))
			high = high.max(Vector2(relative.dot(right),relative.dot(up)))
		var half := Vector2(size*aspect,size)*.5
		check(low.x >= -half.x and high.x <= half.x and low.y >= -half.y and high.y <= half.y,"Room cut by camera at aspect %.2f" % aspect)
		check((high.y-low.y)/size >= .9 or (high.x-low.x)/(size*aspect) >= .9,"Room too small on screen at aspect %.2f" % aspect)
	place.set_part_available(false)
	check(not place.part_visual.visible,"Collected part remains visible")
	place.set_interior_active(false)
	check(place.room.process_mode == Node.PROCESS_MODE_DISABLED and not place.room.visible,"Empty interior active")
	for failure in failures: push_error(failure)
	print("MACIOTA_WORLD ","PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	probe.free()
	place.free()
	quit(0 if failures.is_empty() else 1)
