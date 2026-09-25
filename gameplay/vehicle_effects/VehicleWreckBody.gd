extends RigidBody3D
## A carcaça usa gravidade e contatos reais. O veículo continua sendo o dono para
## save, socorro, remoção e reparo; top_level evita realimentar o movimento físico.

var vehicle: CharacterBody3D
var support_points := PackedVector3Array()
var _ground_query := PhysicsRayQueryParameters3D.new()

func configure_support(bounds: AABB) -> void:
	# Só quatro consultas por passo enquanto o corpo está acordado. Corrige a
	# pequena penetração tolerada pelo solver durante contatos rápidos da traseira.
	for x in [bounds.position.x, bounds.end.x]:
		for z in [bounds.position.z, bounds.end.z]:
			support_points.append(Vector3(x, bounds.position.y, z))
	_ground_query.collision_mask = 1
	_ground_query.exclude = [get_rid()]

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var pose := state.transform
	var correction := 0.0
	var ground_normal := Vector3.UP
	for local_point in support_points:
		var point := pose * local_point
		_ground_query.from = point + Vector3.UP * 0.25
		_ground_query.to = point - Vector3.UP * 0.25
		var hit := state.get_space_state().intersect_ray(_ground_query)
		if not hit.is_empty() and hit.normal.y > 0.5:
			# Mantém até 5 mm de contato para o solver sustentar o peso e o torque.
			var depth: float = hit.position.y - 0.005 - point.y
			if depth > correction:
				correction = depth
				ground_normal = hit.normal
	if correction > 0:
		pose.origin.y += correction
		state.transform = pose
		# A recuperação de posição também consome a velocidade contra o piso;
		# preservá-la acumularia gravidade e faria o solver expulsar a carcaça.
		var closing := state.linear_velocity.dot(ground_normal)
		if closing < 0:
			state.linear_velocity -= ground_normal * closing
		state.linear_velocity = state.linear_velocity.move_toward(Vector3.ZERO,
			physics_material_override.friction * state.total_gravity.length() * state.step)
		state.angular_velocity *= 0.65
	if is_instance_valid(vehicle):
		vehicle.global_transform = pose
