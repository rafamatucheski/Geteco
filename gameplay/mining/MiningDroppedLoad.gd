extends Node
## A otimização base de veículo estacionado supõe que o piso dele nunca se afasta.
## Mantém as cargas soltas acordadas até a área de apoio inteira descansar em chão estático.
## A velocidade no ar continua inteiramente nas mãos da gravidade/colisões de Vehicle.
var body: CharacterBody3D
var _ground_clock := 0.0
var _platform_layers := 0
var _platform_leave := 0

static func attach(car: CharacterBody3D) -> void:
	if not is_instance_valid(car) or not car.is_inside_tree() or car.is_queued_for_deletion(): return
	if car.get_parent() != null and car.get_parent().is_queued_for_deletion(): return
	var old := car.get_node_or_null("MiningDroppedLoad")
	if old != null:
		car.remove_child(old)
		old.queue_free()
	var monitor: Node = load("res://gameplay/mining/MiningDroppedLoad.gd").new()
	monitor.name = "MiningDroppedLoad"
	monitor.body = car
	car.add_child(monitor)
	car.set_meta("mining_released_load",true)

func _ready() -> void:
	process_physics_priority = -15
	_platform_layers = body.platform_floor_layers
	_platform_leave = body.platform_on_leave
	# Um carro solto não pode herdar o movimento da caçamba como plataforma móvel:
	# senão dar ré na carregadeira leva junto a carga supostamente solta.
	# A máscara de colisão fica intacta, então a caçamba ainda a apoia fisicamente.
	body.platform_floor_layers = _platform_layers & ~4
	body.platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING

func _physics_process(delta: float) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion(): queue_free(); return
	if body.has_meta("mining_carried_by"):
		queue_free()
		return
	var wreck := body.get_node_or_null("WreckBody") as RigidBody3D
	if is_instance_valid(wreck):
		_ground_clock -= delta
		if _ground_clock <= 0:
			_ground_clock = .15
			if wreck.linear_velocity.length_squared() < .04 and _wreck_grounded(wreck): queue_free()
		return
	if not body.is_physics_processing() or not body.is_on_floor(): return
	_ground_clock -= delta
	if _ground_clock <= 0:
		_ground_clock = .15
		if supported_by_ground(): queue_free(); return
	# is_on_floor fica em cache no CharacterBody até o próximo move_and_slide.
	# Um pequeno despertar para baixo impede que _is_resting pule esse próximo movimento.
	body.velocity.y = minf(body.velocity.y,-.10)

func _wreck_grounded(wreck: RigidBody3D) -> bool:
	# Um destroço pode terminar de cabeça para baixo. Usa a base do casco no espaço do mundo em vez
	# da origem original do veículo em pé ou dos contatos em cache do CharacterBody.
	var hull: CollisionShape3D
	for child in wreck.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D: hull = child; break
	if hull == null: return false
	var size: Vector3 = hull.shape.size
	var bounds: AABB = hull.global_transform*AABB(-size*.5,size)
	var points: Array[Vector3] = [Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)]
	for x in [.15,.85]:
		for z in [.15,.85]: points.append(bounds.position+Vector3(bounds.size.x*x,0,bounds.size.z*z))
	var space := body.get_world_3d().direct_space_state
	for point in points:
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.10,point-Vector3.UP*.30,7,[body.get_rid(),wreck.get_rid()])
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or not hit.collider is StaticBody3D or hit.collider is AnimatableBody3D or float(hit.normal.y) < .65: return false
	return true

func _exit_tree() -> void:
	if is_instance_valid(body):
		body.platform_floor_layers = _platform_layers
		body.platform_on_leave = _platform_leave
		body.remove_meta("mining_released_load")

func supported_by_ground() -> bool:
	var points: Array[Vector3] = [Vector3.ZERO]
	for x in [-.85,.85]:
		for z in [-.85,.85]: points.append(Vector3(float(body.half_width)*x,0,float(body.half_length)*z))
	var space := body.get_world_3d().direct_space_state
	# Caixas de veículo em pé tocam o canto mais alto numa estrada de transporte inclinada.
	# Checa os outros cantos descendo a inclinação permitida em vez de manter
	# acordado para sempre um veículo estacionado corretamente na rampa.
	var depth := .35+maxf(float(body.half_width),float(body.half_length))*sin(body.floor_max_angle)
	for point in points:
		var origin := body.to_global(point)
		var ray := PhysicsRayQueryParameters3D.create(origin+Vector3.UP*.10,origin-Vector3.UP*depth,7,[body.get_rid()])
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or not hit.collider is StaticBody3D or hit.collider is AnimatableBody3D or float(hit.normal.y) < cos(body.floor_max_angle): return false
	return true
