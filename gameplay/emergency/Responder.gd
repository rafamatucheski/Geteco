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
## Mangueira: jato d'água balístico (WaterJet3D) das mãos do bombeiro até o fogo.
## O caminhão estacionado perto também joga água pelo canhão do teto.
var stream: Node3D
var cannon: Node3D
var hose: Array[MeshInstance3D] = []
const HOSE_SEGMENTS := 8
const WATER_JET := preload("res://gameplay/fx/WaterJet3D.gd")
const CANNON_RANGE := 18.0

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
	if role == "fire":
		stream = WATER_JET.new()
		stream.flight_time = 0.45
		add_child(stream)
		cannon = WATER_JET.new()
		cannon.flight_time = 0.9
		cannon.drop_scale = 2.4
		add_child(cannon)
		# Mangueira deitada no chão, do caminhão até o bombeiro (o esguicho já é do modelo).
		for i in HOSE_SEGMENTS:
			var piece := _stick(0.05, 1.0, Color("7a1f1a"))
			piece.top_level = true
			piece.hide()
			hose.append(piece)

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
				_spray(fire, delta)
			else:
				_stop_water()
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
	if health > 0: return
	dead = true
	collision_layer = 0
	collision_mask = 0
	var impact_dir: Vector3 = (global_position - (_source as Node3D).global_position).normalized() if _source is Node3D else Vector3.ZERO
	preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self, visual, impact_dir)
	_stop_water()
	manager.report_injury(self, true)

func _spray(fire: Node3D, delta: float) -> void:
	var target: Vector3 = fire.global_position + Vector3.UP * 0.2
	var toward := target - global_position
	toward.y = 0.0
	if toward.length() > 0.1: visual.rotation.y = atan2(-toward.x, -toward.z)
	# Braços para frente segurando o esguicho do modelo; o jato sai da ponta dele.
	visual.right_upper_arm.rotation.x = 1.25
	visual.left_upper_arm.rotation.x = 1.1
	visual.left_upper_arm.rotation.z = -0.35
	var muzzle: Vector3 = visual.hose_muzzle.global_position if visual.get("hose_muzzle") != null else global_position + Vector3.UP * 1.1
	stream.aim(muzzle, target)
	stream.set_active(true)
	if is_instance_valid(vehicle): _lay_hose(vehicle.to_global(Vector3(vehicle.half_width, 0.0, 1.5)), global_position)
	# Canhão do teto: gira no pivô, mira no fogo e a água sai do bico.
	var monitor: Node3D = vehicle.get_meta("fire_monitor", null) if is_instance_valid(vehicle) else null
	var tip: Node3D = vehicle.get_meta("fire_monitor_tip", null) if is_instance_valid(vehicle) else null
	if is_instance_valid(monitor) and is_instance_valid(tip) and vehicle.global_position.distance_to(target) < CANNON_RANGE:
		var aim_point := target + Vector3.UP * 2.0
		if monitor.global_position.distance_to(aim_point) > 0.5:
			monitor.look_at(aim_point, Vector3.UP)
		cannon.aim(tip.global_position, target + Vector3(0.3, 0, -0.2))
		cannon.set_active(true)
		manager.extinguish(fire, delta * 0.3)
	elif is_instance_valid(cannon):
		cannon.set_active(false)

func _stop_water() -> void:
	if is_instance_valid(stream): stream.set_active(false)
	for piece in hose:
		if is_instance_valid(piece): piece.hide()
	if visual != null and visual.get("right_upper_arm") != null:
		visual.right_upper_arm.rotation = Vector3.ZERO
		visual.left_upper_arm.rotation = Vector3.ZERO
	if is_instance_valid(cannon): cannon.set_active(false)

func _stick(radius: float, length: float, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 8
	item.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
	return item

## Mangueira no chão em curva suave (Bézier) do caminhão ao pé do bombeiro, em
## segmentos colados ao chão; uma reta só parecia um cabo voando.
func _lay_hose(pump: Vector3, foot: Vector3) -> void:
	var ground := foot.y + 0.05
	var a := Vector3(pump.x, ground, pump.z)
	var b := Vector3(foot.x, ground, foot.z)
	var along := b - a
	if along.length() < 0.5: return
	var bend := Vector3(-along.z, 0, along.x).normalized() * along.length() * 0.18
	var control := (a + b) * 0.5 + bend
	var previous := a
	for i in HOSE_SEGMENTS:
		var t := float(i + 1) / HOSE_SEGMENTS
		var point := a.lerp(control, t).lerp(control.lerp(b, t), t)
		var piece := hose[i]
		var span := previous.distance_to(point)
		if span > 0.01:
			piece.show()
			piece.global_transform = Transform3D(Basis.looking_at((point - previous) / span, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(1, span * 1.04, 1)), (previous + point) * 0.5)
		previous = point
