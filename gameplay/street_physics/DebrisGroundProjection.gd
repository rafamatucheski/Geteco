extends RefCounted
## Projeção no chão de uma vez só; sem nós por fragmento nem física por quadro.
const FLOOR_MASK := 1 # Só o mundo estático; veículos nativos ficam na camada 4.
# As vias colidem em y=0 mas renderizam em +.026; os recuos renderizam em +.030.
# Passa 6 mm acima dessas camadas visuais de calçamento, ficando a menos de 4 cm do
# plano de apoio real (incluindo pontes/rampas), nunca na altura de janela.
const LIFT := .036
const RAY_DEPTH := 48.0

static func triangle(space: PhysicsDirectSpaceState3D, center: Vector3, offsets: Array[Vector3], baseline := false) -> PackedVector3Array:
	var result := PackedVector3Array()
	# Explicit measurement fixture reproduces the former airborne plane without
	# reverting shared source files. Normal gameplay always projects the ground.
	if baseline:
		for offset: Vector3 in offsets: result.append(center+offset+Vector3.UP*.045)
		return result
	var support := _support(space,center)
	if support.is_empty(): return result
	var normal: Vector3 = support.normal
	for offset: Vector3 in offsets:
		var hit := _support(space,center+offset)
		if hit.is_empty(): return PackedVector3Array()
		# Um único caco não consegue atravessar meio-fio, penhasco ou buraco. Compara cada canto
		# com o plano de apoio real do centro, permitindo um piso inclinado.
		if (hit.normal as Vector3).dot(normal)<.94: return PackedVector3Array()
		if absf(((hit.position as Vector3)-(support.position as Vector3)).dot(normal))>.035:
			return PackedVector3Array()
		result.append((hit.position as Vector3)+(hit.normal as Vector3)*LIFT)
	return result

static func _support(space: PhysicsDirectSpaceState3D, point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.15,point+Vector3.DOWN*RAY_DEPTH,FLOOR_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).y<.55: return {}
	return hit
