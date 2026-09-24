extends CharacterBody3D

var manager: Node3D
var role := "medic"
var incident_id := 0
var destination := Vector3.ZERO
var vehicle: CharacterBody3D
var visual: Node3D
var mode := "approach"
var action_time := 0.0
var age := 0.0
var gait := 0.0
var path := PackedVector3Array()
var waypoint := 0
var repath := 0.0
var health := 60.0
var dead := false
var stream: MeshInstance3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = 0.3
	set_meta("gameplay_role", "emergency")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = 0.3
	shape.shape = capsule
	shape.position.y = 0.86
	add_child(shape)
	match role:
		"fire": visual = preload("res://gameplay/emergency/FirefighterModel.gd").new()
		"mortician": visual = preload("res://gameplay/emergency/MorticianModel.gd").new()
		_: visual = preload("res://gameplay/emergency/ParamedicModel.gd").new()
	visual.is_stretcher_bearer = role != "fire"
	add_child(visual)
	if role != "fire": visual.stretcher_mesh.hide()
	stream = MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.025
	tube.bottom_radius = 0.07
	tube.height = 1
	tube.radial_segments = 6
	stream.mesh = tube
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b6d5e3")
	stream.material_override = material
	add_child(stream)
	stream.hide()

func _physics_process(delta: float) -> void:
	if dead: return
	age += delta
	if age > 120:
		manager.release(self)
		return
	var incident: Dictionary = manager.incidents.get(incident_id, {})
	if mode == "approach" and incident.is_empty(): mode = "return"
	if mode == "approach":
		if is_instance_valid(incident.get("actor")): destination = incident.actor.global_position
		if global_position.distance_to(destination) < (3.0 if role == "fire" else 1.3):
			var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, destination + Vector3.UP * 0.6, 1)
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				mode = "service"
				action_time = 0
	elif mode == "service":
		action_time += delta
		if role == "fire":
			var fire: Node3D = incident.get("actor")
			if is_instance_valid(fire):
				manager.extinguish(fire, delta * 0.3)
				var start := global_position + Vector3.UP
				var end := fire.global_position + Vector3.UP * 0.5
				stream.show()
				stream.global_position = (start + end) * 0.5
				stream.scale = Vector3(1, start.distance_to(end), 1)
				stream.global_basis = Basis(Quaternion(Vector3.UP, (end - start).normalized())).scaled(stream.scale)
			else:
				stream.hide()
				mode = "return"
		elif action_time > 4.0:
			visual.stretcher_mesh.show()
			if role == "mortician": visual.body_bag_mesh.show()
			manager.complete(incident_id)
			mode = "return"
	if mode == "return":
		if not is_instance_valid(vehicle):
			manager.release(self)
			return
		destination = vehicle.to_global(Vector3(vehicle.half_width + 0.8, 0, 0))
		if global_position.distance_to(destination) < 1.0:
			manager.release(self)
			return
	var direction := Vector3.ZERO
	if mode != "service":
		repath -= delta
		if repath <= 0:
			repath = 1.5
			path = manager.gameplay.find_path(global_position, destination)
			waypoint = 0
		var next := destination
		if waypoint < path.size():
			next = path[waypoint]
			if global_position.distance_to(next) < 0.7: waypoint += 1
		direction = next - global_position
		direction.y = 0
		direction = direction.normalized()
	if direction.length_squared() > 0.01: visual.rotation.y = atan2(-direction.x, -direction.z)
	velocity.x = direction.x * 3.0
	velocity.z = direction.z * 3.0
	velocity.y = -1 if is_on_floor() else velocity.y - 20 * delta
	move_and_slide()
	gait += Vector2(velocity.x, velocity.z).length() * delta * 3.4
	visual.left_upper_leg.rotation.x = sin(gait) * 0.5
	visual.right_upper_leg.rotation.x = -sin(gait) * 0.5

func receive_damage(amount: float, _source: Node = null) -> void:
	if dead: return
	health -= amount
	if health > 0:
		var impact_dir: Vector3 = (global_position - (_source as Node3D).global_position).normalized() if _source is Node3D else Vector3.ZERO
		preload("res://gameplay/CharacterFallPresentation3D.gd").apply_hit(self, visual, impact_dir, amount)
		return
	dead = true
	collision_layer = 0
	collision_mask = 0
	var impact_dir: Vector3 = (global_position - (_source as Node3D).global_position).normalized() if _source is Node3D else Vector3.ZERO
	preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self, visual, impact_dir)
	stream.hide()
	manager.report_injury(self, true)
