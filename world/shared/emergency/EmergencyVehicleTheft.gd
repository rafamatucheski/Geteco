extends RefCounted
## Dispatch owns AI responders; the normal traffic controller owns stolen vehicles.
static func enter(source: CharacterBody2D, actor: CharacterBody2D) -> void:
	if source.is_broken or not source.is_visible_in_tree() or source.is_queued_for_deletion(): return
	if not is_instance_valid(actor) or actor.get("is_control_disabled") == true: return
	source.ensure_presentation()
	var world := source.get_tree().current_scene
	if world == null: return
	var medics: Array = []
	var officers: Array = []
	var police_exits: Array[Vector2] = []
	var exits: Array[Vector2] = []
	if source.type == 0:
		for officer in source._police_crew:
			if is_instance_valid(officer) and not officer.is_queued_for_deletion() and not officer.is_dead and not officer.visible:
				officers.append(officer)
		var aboard: int = maxi(source.returned_officers, officers.size()) if source._police_crew_on_foot else mini(source._police_available_seats, 1 if source.police_variant == "motorcycle" else 2)
		police_exits = medical_exit_positions(source, aboard, actor)
		if police_exits.size() != aboard: return
	if source.type == 1:
		for medic in source._response_crew:
			if is_instance_valid(medic) and not medic.is_queued_for_deletion() and not medic.is_dead and not medic.visible:
				medics.append(medic)
		var aboard: int = 2 if source.deployed_paramedics == 0 else maxi(source.returned_paramedics, medics.size())
		exits = medical_exit_positions(source, aboard, actor)
		if exits.size() != aboard: return
	var vehicle := (load("res://world/shared/traffic/TrafficVehicle.tscn") as PackedScene).instantiate() as CharacterBody2D
	world.add_child(vehicle)
	var motorcycle: bool = source.type == 0 and source.police_variant == "motorcycle"
	var archetype: String = "bike_urban" if motorcycle else ["police_cruiser","medic_box","rescue_pumper","courier_van"][source.type]
	if source.type == 0 and not motorcycle: archetype = source.police_archetype
	var paint := Color.WHITE
	if is_instance_valid(source.body_model) and source.body_model.paint != null:
		paint = source.body_model.paint.albedo_color
	vehicle.apply_archetype(archetype,paint)
	if motorcycle:
		vehicle._setup_3d_model({"model_class":"res://world/shared/emergency/PoliceMotorcycleModel.gd","target_length":42.0,"target_width":22.0},paint)
		vehicle.is_police_vehicle = true
		vehicle.display_name = "Moto da PM"
	elif source.type == 3:
		vehicle.display_name = "Rabecão do IML"
		vehicle.body_model.add_lightbar(2.16,-1.05,Color("ffb329"),Color("a855f7"),1.3)
	vehicle.global_transform = source.global_transform
	var collision := source.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		vehicle.collision.shape = collision.shape.duplicate()
		vehicle.collision.transform = collision.transform
	vehicle.health = mini(source.health,vehicle.max_health)
	vehicle.set_headlights(source.get("is_night_or_storm") == true)
	# The responder owns its crew; the traffic wrapper must not invent a civilian.
	vehicle.set_meta("service_crew_owned", source.type in [0, 1])
	if source.type == 1: vehicle._detached_from_lane = true
	vehicle.enter_vehicle(actor)
	if not vehicle.is_driven_by_player:
		vehicle.queue_free()
		return
	vehicle._detached_from_lane = true
	for i in police_exits.size():
		var officer: Node2D = officers[i] if i < officers.size() else (load("res://PoliceOfficer.tscn") as PackedScene).instantiate()
		if not officer.is_inside_tree(): world.add_child(officer)
		officer.global_position = police_exits[i]
		officer.remove_collision_exception_with(source)
		officer.service_vehicle = null
		officer.service_disembark_active = false
		officer.returning_to_service_vehicle = false
		officer.boarding_service_vehicle = false
		officer.target = vehicle
		officer.show()
		officer.set_physics_process(true)
		officer.collision_shape.set_deferred("disabled", false)
		officer.reset_physics_interpolation()
	for i in exits.size():
		var medic: Node2D = medics[i] if i < medics.size() else (load("res://Paramedic.tscn") as PackedScene).instantiate()
		if not medic.is_inside_tree():
			medic.crew_side = -1.0 if i == 0 else 1.0
			world.add_child(medic)
		medic.global_position = exits[i]
		medic.show()
		medic.collision_layer = 4
		medic.collision_mask = 7
		medic.collision_shape.set_deferred("disabled", false)
		medic.remove_collision_exception_with(source)
		medic.ambulance = null
		medic.target = null
		medic.state = Paramedic.State.APPROACH
		medic.set_physics_process(true)
		medic.remove_meta("medical_managed")
		medic.reset_physics_interpolation()
	# Abort through the medical lifecycle so patients/crew are not left onboard.
	if source.has_meta("medical_sequence"):
		var sequence: Node = source.get_meta("medical_sequence")
		if is_instance_valid(sequence): sequence._abort("vehicle_stolen")
	source.velocity = Vector2.ZERO
	source.collision_layer = 0
	source.collision_mask = 0
	source.hide()
	source.process_mode = Node.PROCESS_MODE_DISABLED
	source.queue_free()

static func medical_exit_positions(source: CharacterBody2D, count: int, actor: CharacterBody2D) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	for side in [-1.0, 1.0]:
		for offset in [0.0, -20.0, 20.0]:
			if result.size() == count: return result
			var point: Vector2 = source.get_crew_exit_point(side, 8.0 + offset)
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape
			query.transform = Transform2D(0, point)
			query.collision_mask = 7
			query.exclude = [actor.get_rid()]
			if not source.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
			var overlaps := false
			for previous in result:
				if previous.distance_to(point) < 16.0: overlaps = true
			if not overlaps:
				result.append(point)
				break
	return result
