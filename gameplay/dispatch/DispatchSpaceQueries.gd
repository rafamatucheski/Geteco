extends RefCounted
## Consultas de espaço do despacho: caixa livre para nascer (`_space_clear`), cápsula de pessoa, pegada
## do carro, tamanho do arquétipo e o ponto de saída ao lado da porta. Separado de DispatchController.gd
## em 01/11 só para o dono caber na leitura. O dono mantém cada função antiga como delegação de uma
## linha com a mesma assinatura, então DispatchUnit, os testes (`controller._space_clear`...) e quem
## chama por nome não mudam. `g` fica como Node3D, e não como o script do dono, para não criar preload
## cíclico; até as chamadas entre funções deste arquivo passam por `g.`. Sem estado próprio.

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _space_clear(size: Vector3, point: Vector3, yaw: float, exclude: Array[RID]) -> bool:
	var space: PhysicsDirectSpaceState3D = g.world.get_world_3d().direct_space_state
	var orientation := Basis(Vector3.UP, yaw)
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size
	query.shape = box
	query.transform = Transform3D(orientation, point + orientation * Vector3(0.0, size.y * 0.5 + 0.1, 0.0))
	query.collision_mask = 7
	query.exclude = exclude
	for x in [-size.x * 0.4, size.x * 0.4]:
		for z in [-size.z * 0.4, size.z * 0.4]:
			var support: Vector3 = point + orientation * Vector3(x, 0.0, z)
			var ray := PhysicsRayQueryParameters3D.create(support + Vector3.UP * 0.6, support - Vector3.UP * 0.8, 1)
			if space.intersect_ray(ray).is_empty(): return false
	var session: Variant = g.world.get("session")
	if session != null and session.cold != null and not session.cold.prepare_collision_at(point): return false
	return space.intersect_shape(query,1).is_empty()

func capsule_clear(point: Vector3, exclude: Array[RID]) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.72
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.9)
	query.collision_mask = 7
	query.exclude = exclude
	return g.world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func footprint_clear(car: CharacterBody3D, point: Vector3, yaw: float) -> bool:
	var size: Vector3 = (car.shape.shape as BoxShape3D).size
	var exclude: Array[RID] = [car.get_rid()]
	return g._space_clear(size, point, yaw, exclude)

func _archetype_size(archetype: String) -> Vector3:
	var spec: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(archetype)
	if spec.is_empty(): return Vector3(2.08, 1.4, 4.6)
	var bounds: Array = spec.bounds_size
	return Vector3(maxf(0.65, bounds[0]), clampf(bounds[1], 1.1, 3.6), bounds[2])

## Ponto ao lado da porta onde uma pessoa cabe: chão sólido, sem corpo dentro,
## sem parede entre o veículo e o ponto. Vazio quando não há saída segura.
## A equipe policial alterna os lados: o primeiro desce pela porta do motorista (-1), o
## segundo pela do carona (+1). Antes o lado +1 era sempre testado primeiro e, havendo
## espaço, a dupla inteira descia pelo mesmo lado, um atrás do outro.
func exit_point_at(car: CharacterBody3D, point: Vector3, yaw: float) -> Dictionary:
	var taken: Array[Vector3] = []
	return g.exit_point(car,taken,true,Transform3D(Basis(Vector3.UP,yaw),point))

func exit_point(car: CharacterBody3D, taken: Array[Vector3], right_only: bool, at := Transform3D.IDENTITY) -> Dictionary:
	var pose: Transform3D = car.global_transform if at==Transform3D.IDENTITY else at
	var space: PhysicsDirectSpaceState3D = g.world.get_world_3d().direct_space_state
	var sides: Array[float] = [1.0]
	var longitudinal: Array[float] = [0.0, 0.3, -0.3]
	if not right_only:
		sides.assign([-1.0, 1.0] if taken.size() % 2 == 0 else [1.0, -1.0])
		var door := -clampf(float(car.half_length) * .18, .30, .62)
		longitudinal.assign([door, 0.3, -1.0, 1.4])
		# Camburão: porta lateral, meio e as duas portas de trás; com os pontos já usados de fora,
		# os seis agentes saem espalhados.
		if car.archetype == "police_transport": longitudinal.assign([-1.1, 0.2, 1.5, 2.3, -0.4])
	var reach: float = car.half_width + (0.9 if right_only else 0.75)
	var excluded: Array[RID] = [car.get_rid()]
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.72
	for side in sides:
		for shift in longitudinal:
			var point: Vector3 = pose * Vector3(side * reach, 0.0, shift)
			var ground := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.8, point - Vector3.UP * 0.8, 1)
			var ground_hit := space.intersect_ray(ground)
			if ground_hit.is_empty(): continue
			point.y = ground_hit.position.y + 0.04
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.9)
			query.collision_mask = 7
			query.exclude = excluded
			# Meio-fio e parede do túnel do canal ficam a menos de 1 m da porta: sem
			# esta exceção a equipe nunca descia lá dentro ("no_exit" e a viatura ia embora).
			var blocked := false
			for hit in space.intersect_shape(query, 4):
				if is_instance_valid(hit.collider) and hit.collider.has_meta("vehicle_ramp_structure"): continue
				blocked = true
				break
			if blocked: continue
			var sight := PhysicsRayQueryParameters3D.create(pose.origin + Vector3.UP * 0.9, point + Vector3.UP * 0.9, 1, excluded)
			if not space.intersect_ray(sight).is_empty(): continue
			var crowded := false
			for other in taken:
				if point.distance_to(other) < 0.9: crowded = true
			if crowded: continue
			return {"point": point, "side": side}
	return {}
