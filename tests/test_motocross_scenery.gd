extends SceneTree
## Physical and scene-contract checks. These do not certify rendered FPS.
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("MOTOCROSS_SCENERY ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)

func ray(course: Node3D, point: Vector3, rise := 5.0, depth := 5.0) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * rise, point - Vector3.UP * depth, 1)
	query.hit_back_faces = false
	return course.get_world_3d().direct_space_state.intersect_ray(query)

func occupancy(course: Node3D, point: Vector3) -> Array[Dictionary]:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.85)
	query.collision_mask = 5
	return course.get_world_3d().direct_space_state.intersect_shape(query)

func connected_yard_checks(course: Node3D, paddock: Node3D) -> void:
	var bike_support := true
	for bike in paddock.parked_bikes:
		# Both tire patches, not just the midpoint of the parked motorcycle.
		for wheel_z in [-.88, .83]:
			var contact: Vector3 = bike.to_global(Vector3(0, 0, wheel_z))
			var hit := ray(course, contact, .06, .3)
			bike_support = bike_support and not hit.is_empty() and absf(float(hit.position.y) - contact.y) < .025 and hit.normal.y > .95
	check(bike_support, "both tires of every parked bike rest on the connected earth at their authored height")
	var feet_supported := true
	for person in paddock.drinkers:
		# Standard seated IK plants feet 40 cm ahead of the pelvis, clear of bench.
		for side in [-1.0, 1.0]:
			var foot: Vector3 = person.model.to_global(Vector3(side * .13, 0, .4))
			var hit := ray(course, foot, .045, .3)
			feet_supported = feet_supported and not hit.is_empty() and absf(float(hit.position.y) - foot.y) < .025
	var keeper: Node3D = paddock.get_node("RentalKeeper")
	var keeper_floor := ray(course, keeper.global_position, .045, .3)
	feet_supported = feet_supported and not keeper_floor.is_empty() and absf(float(keeper_floor.position.y) - keeper.global_position.y) < .025
	check(feet_supported, "seated riders' planted feet and rental keeper share supported ground height")
	# A usable corridor beside the furniture, through service and parked bikes,
	# then down the earth taper into the park access. No model-derived heights.
	var route := PackedVector3Array([Vector3(-230,.13,-28), Vector3(-226,.13,-30), Vector3(-225.8,.13,-35), Vector3(-216,.13,-35), Vector3(-216,.13,-39), Vector3(-225,.13,-39), Vector3(-225,.004,-43)])
	var continuous := true
	var samples := 0
	var max_step := 0.0
	var previous_height := NAN
	for segment in route.size() - 1:
		var count := ceili(route[segment].distance_to(route[segment + 1]) / .25)
		for index in count + 1:
			var point := route[segment].lerp(route[segment + 1], float(index) / count)
			var hit := ray(course, point, .2, .5)
			samples += 1
			if hit.is_empty():
				continuous = false
				continue
			var height: float = hit.position.y
			if is_finite(previous_height): max_step = maxf(max_step, absf(height - previous_height))
			continuous = continuous and hit.normal.y > .9 and height >= -.01 and height <= .155
			previous_height = height
	check(continuous and samples > 100 and max_step < .035, "table, rental counter, bike parking and access connect without gaps or abrupt steps")
	var walker := CharacterBody3D.new()
	walker.collision_layer = 0
	walker.collision_mask = 7
	walker.floor_snap_length = .25
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .28
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .85
	walker.add_child(shape)
	course.add_child(walker)
	walker.global_position = route[0] + Vector3.UP * .025
	var traversed := true
	for target in route:
		var arrived := false
		for frame in 210:
			await physics_frame
			var offset: Vector3 = target - walker.global_position
			offset.y = 0
			if offset.length() < .12:
				arrived = true
				break
			var velocity := offset.normalized() * minf(4.0, offset.length() * 60.0)
			walker.velocity = Vector3(velocity.x, -1.0 if walker.is_on_floor() else walker.velocity.y - 20.0 / 60.0, velocity.z)
			walker.move_and_slide()
			if walker.global_position.y < -.08 or walker.global_position.y > .2: traversed = false
		if not arrived:
			print("MOTOCROSS_YARD_BLOCKED target=", target, " actual=", walker.global_position)
			traversed = false
			break
	check(traversed, "human capsule physically walks all connected yard corridors and tapered access")
	print("MOTOCROSS_YARD_SAMPLES count=", samples, " largest_height_step=", max_step)
	walker.free()

func run() -> void:
	var course := COURSE.new()
	root.add_child(course)
	for _i in 5: await physics_frame
	var scenery: Node3D = course.get_node("MotocrossScenery")
	var paddock: Node3D = course.get_node("MotocrossPaddock")
	var gate: Node3D = course.get_node("AlignedStart")
	var direction := (course.sample(1.0) - course.sample(0.0))
	direction.y = 0
	direction = direction.normalized()
	check((-gate.global_basis.z).dot(direction) > 0.999, "start gantry follows the actual track heading")
	check(gate.global_position.distance_to(course.sample(0)) < 0.01, "start stripe sits at the first route checkpoint")
	var posts := 0
	var post_clearance := true
	for child in gate.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and child.mesh.size.is_equal_approx(Vector3(0.35, 4.8, 0.35)):
			posts += 1
			post_clearance = post_clearance and float(course.nearest(child.global_position).lateral) > COURSE.HALF_WIDTH + 0.3
	check(posts == 2 and post_clearance, "both solid gantry posts stay outside the riding width")
	var banks: MeshInstance3D = course.get_node("SculptedBanks")
	var bank_arrays := banks.mesh.surface_get_arrays(0)
	var bank_vertices: PackedVector3Array = bank_arrays[Mesh.ARRAY_VERTEX]
	var bank_normals: PackedVector3Array = bank_arrays[Mesh.ARRAY_NORMAL]
	var underside := 0
	for normal in bank_normals:
		if normal.y < -0.001: underside += 1
	if underside > 0:
		print("MOTOCROSS_SCENERY_BANK_NORMALS down_vertices=", underside, " total_vertices=", bank_normals.size())
		var reported := 0
		for index in range(0, bank_vertices.size(), 3):
			var face := (bank_vertices[index + 2] - bank_vertices[index]).cross(bank_vertices[index + 1] - bank_vertices[index])
			if face.y >= -0.0001: continue
			print("MOTOCROSS_SCENERY_BANK_INVERTED at=", (bank_vertices[index] + bank_vertices[index + 1] + bank_vertices[index + 2]) / 3.0, " face=", face.normalized(), " area=", face.length() * 0.5, " vertices=", [bank_vertices[index], bank_vertices[index + 1], bank_vertices[index + 2]])
			reported += 1
			if reported >= 4: break
		if reported == 0: print("MOTOCROSS_SCENERY_BANK_INVERTED none; downward vertex normals come from smoothing")
	check(underside == 0, "all sculpted shoulders face upward for visible and physical surface")
	var bank_misses := 0
	var bank_samples := 0
	for triangle in range(0, bank_vertices.size() / 3, 23):
		var base := triangle * 3
		var center := (bank_vertices[base] + bank_vertices[base + 1] + bank_vertices[base + 2]) / 3.0
		var hit := ray(course, center, 1.0, 2.0)
		bank_samples += 1
		if hit.is_empty() or float(hit.position.y) < center.y - 0.04: bank_misses += 1
	check(bank_samples > 20 and bank_misses == 0, "sampled shoulders have real support at their rendered height")
	var trees := 0
	var trees_clear := true
	for child in scenery.get_children():
		# Godot may auto-rename repeated ShadeTree names to @Node3D@... .
		if child.get_class() == "Node3D" and not str(child.name).begins_with("SpectatorBoat"):
			trees += 1
			trees_clear = trees_clear and float(course.nearest(child.global_position).lateral) - 0.48 > COURSE.HALF_WIDTH + 2.0
	check(trees >= 8 and trees_clear, "shade tree trunks remain clear of track and its shoulders")
	check(float(course.nearest(scenery.tower_position).lateral) > COURSE.HALF_WIDTH + 1.6, "central floodlight foundation stays outside the course")
	check(not occupancy(course, Vector3(-234, 0.2, -35)).is_empty(), "rental hut has a solid closed exterior")
	for point in [COURSE.ENTRY, COURSE.ENTRY + Vector3(2, 0, 2), COURSE.ENTRY + Vector3(4, 0.15, -3)]:
		check(occupancy(course, point).is_empty(), "service/return/owned-motorcycle point remains free: %s" % point)
	var parked: Array = paddock.parked_bikes
	check(parked.size() == 3, "three rental motorcycles are parked beside the hut")
	var parked_solid := true
	for bike in parked:
		parked_solid = parked_solid and bike.collision_layer == 4 and not bike.is_physics_processing() and not bike.rider.visible
	check(parked_solid, "parked motorcycles keep collision without drivers or runtime simulation")
	check(paddock.drinkers.size() == 3, "three seated motocross riders occupy the rest area")
	await connected_yard_checks(course, paddock)
	var boats := 0
	var passengers := 0
	var boat_support := true
	var spectator_grounding := true
	for child in scenery.get_children():
		if not str(child.name).begins_with("SpectatorBoat"): continue
		boats += 1
		var deck: Vector3 = child.to_global(Vector3(0, 0.57, 0.1))
		var hit := ray(course, deck, 0.12, 0.4)
		boat_support = boat_support and not hit.is_empty() and absf(float(hit.position.y) - deck.y) < 0.03
		for person in child.get_children():
			if not person.is_in_group("motocross_spectator"): continue
			passengers += 1
			var feet: Vector3 = person.global_position
			var support := ray(course, feet, 0.04, 0.4)
			spectator_grounding = spectator_grounding and not support.is_empty() and absf(float(support.position.y) - feet.y) < 0.04
	check(boats == 3 and passengers == 6, "three moored boats hold six spectators")
	check(boat_support, "each boat deck has collision matching its visible top")
	check(spectator_grounding, "spectator feet rest on actual boat decks")
	scenery.set_lighting(0.0, scenery.tower_position)
	var day_off := true
	for light in scenery._lights: day_off = day_off and not light.visible and light.light_energy == 0.0
	check(day_off and scenery._lights.size() == 4, "tower's four floodlights stay off in daylight")
	scenery.set_lighting(1.0, scenery.tower_position)
	var night_on := true
	for light in scenery._lights: night_on = night_on and light.visible and light.light_energy > 0 and light.shadow_enabled
	check(night_on, "nearby night tower enables four shadow-casting floodlights")
	scenery.set_lighting(1.0, scenery.tower_position + Vector3(250, 0, 0))
	var distant_off := true
	for light in scenery._lights: distant_off = distant_off and not light.visible
	check(distant_off, "floodlights disable outside viewer range")
	print("MOTOCROSS_SCENERY_RESULT checks=", checks, " failures=", failures, " banks=", bank_samples, " trees=", trees)
	course.free()
	quit(0 if failures.is_empty() else 1)
