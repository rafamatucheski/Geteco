extends Node3D
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var controller: Node3D
var shooter: Node3D
var velocity := Vector3.ZERO
var damage := 80.0
var radius := 3.75
var fuse := 2.3
var grenade := true
## V1: o foguete não fere quem o disparou; a granada, sim.
var hurt_shooter := true
var age := 0.0
var detonated := false
var resting := false
var visual: Node3D
var spin := Vector3(7.0, 10.0, 5.0)

func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	if grenade:
		# O mesmo corpo ranhurado usado na mão e no arsenal.
		preload("res://gameplay/ArsenalWeapon3D.gd").build(visual, "grenade")
		visual.position.z = 0.10
	else:
		_build_rocket(visual)
	# Foguete deixa rastro de fumaça (V1 `RocketTrail`); granada não.
	if not grenade and is_instance_valid(controller) and controller.get("effects") != null: controller.effects.attach_rocket_trail(self)

func _build_rocket(root: Node3D) -> void:
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("4c5f32")
	body_material.metallic = 0.38
	body_material.roughness = 0.46
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.038
	body_mesh.bottom_radius = 0.038
	body_mesh.height = 0.22
	body_mesh.radial_segments = 10
	body.mesh = body_mesh
	body.rotation.x = PI * 0.5
	body.material_override = body_material
	root.add_child(body)
	var warhead := MeshInstance3D.new()
	var warhead_mesh := CylinderMesh.new()
	warhead_mesh.top_radius = 0.006
	warhead_mesh.bottom_radius = 0.058
	warhead_mesh.height = 0.16
	warhead_mesh.radial_segments = 10
	warhead.mesh = warhead_mesh
	warhead.rotation.x = -PI * 0.5
	warhead.position.z = -0.18
	warhead.material_override = body_material
	root.add_child(warhead)
	var motor := MeshInstance3D.new()
	var motor_mesh := CylinderMesh.new()
	motor_mesh.top_radius = 0.025
	motor_mesh.bottom_radius = 0.042
	motor_mesh.height = 0.10
	motor_mesh.radial_segments = 10
	motor.mesh = motor_mesh
	motor.rotation.x = PI * 0.5
	motor.position.z = 0.15
	motor.material_override = body_material
	root.add_child(motor)

func _physics_process(delta: float) -> void:
	var began := STALL_WORK.begin()
	_stall_physics_tick(delta)
	STALL_WORK.finish_slow("projectile.physics",began,10000,self)

func _stall_physics_tick(delta: float) -> void:
	if detonated: return
	var began := STALL_WORK.begin()
	age += delta
	if resting:
		# Parada no chão: nada de raio por quadro nem micro-quique flutuando 8 cm acima do piso.
		if age >= fuse: detonate()
		STALL_WORK.finish_slow("projectile.resting_fuse",began,5000,self)
		return
	if grenade: velocity.y -= 12.0 * delta
	if grenade and is_instance_valid(visual): visual.rotation += spin * delta
	elif not grenade and velocity.length_squared() > 0.001: look_at(global_position + velocity.normalized())
	var next := global_position + velocity * delta
	STALL_WORK.finish("projectile.movement", began)
	began = STALL_WORK.begin()
	var hit := _query_hit(global_position, next)
	STALL_WORK.finish("projectile.query_total", began)
	began = STALL_WORK.begin()
	if not hit.is_empty():
		global_position = hit.position + hit.normal * 0.05
		STALL_WORK.finish("projectile.position_hit", began)
		began = STALL_WORK.begin()
		if grenade:
			var normal: Vector3 = hit.normal
			var impact_speed := -velocity.dot(normal)
			if is_instance_valid(controller) and controller.has_method("projectile_bounce"): controller.projectile_bounce(global_position, impact_speed)
			velocity = velocity.bounce(normal) * 0.42
			spin *= 0.6
			if normal.y > 0.6:
				# Atrito do piso: sem ele a granada escorregava e quicava sem fim.
				velocity.x *= 0.6
				velocity.z *= 0.6
				if impact_speed < 1.4 and Vector2(velocity.x, velocity.z).length() < 0.6:
					resting = true
					velocity = Vector3.ZERO
		else:
			detonate()
		STALL_WORK.finish("projectile.impact", began)
	else:
		global_position = next
		STALL_WORK.finish("projectile.position_free", began)
	began = STALL_WORK.begin()
	if age >= fuse: detonate()
	STALL_WORK.finish("projectile.fuse", began)

func detonate() -> void:
	if detonated: return
	detonated = true
	controller.explode(global_position, radius, damage, shooter, hurt_shooter)
	queue_free()

func _query_hit(from: Vector3, to: Vector3) -> Dictionary:
	var began := STALL_WORK.begin()
	var query := PhysicsRayQueryParameters3D.create(from, to, 7)
	if shooter is CollisionObject3D: query.exclude = [shooter.get_rid()]
	STALL_WORK.finish("projectile.query_prepare", began)
	began = STALL_WORK.begin()
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	STALL_WORK.finish("projectile.intersect_ray", began)
	return hit
