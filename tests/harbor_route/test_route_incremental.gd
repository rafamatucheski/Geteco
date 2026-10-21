extends SceneTree
## Mesma hierarquia, geometria e colisão em etapas; índices de edição preservados.
const FACTORY := preload("res://world/harbor_route_detail/HarborRouteDetailFactory.gd")
const ROUTE := preload("res://world/harbor_route_detail/HarborRouteDetail3D.gd")
const EXPECTED_CHILDREN := {"rodoviaria": 18, "connecting_streets": 15, "delegacia": 18, "maciota": 7}
const EXPECTED_SOLIDS := {"rodoviaria": 9, "connecting_streets": 3, "delegacia": 9, "maciota": 4}
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	for zone_id: String in ROUTE.ALL_ZONES:
		var immediate := FACTORY.create_zone(zone_id)
		var job := FACTORY.begin_zone(zone_id)
		var partial: Node3D = job.root
		check(partial.get_child_count() == 0 and partial.get_parent() == null, zone_id + ": pedido começa vazio e fora da árvore")
		var iterations := 0
		while not bool(job.complete) and iterations < 64:
			var previous: int = job.index
			FACTORY.step_zone(job, 0.0)
			check(int(job.index) == previous + 1, zone_id + ": uma peça por chamada sem orçamento restante")
			iterations += 1
		check(bool(job.complete), zone_id + ": construção termina")
		check(partial.get_child_count() == EXPECTED_CHILDREN[zone_id], zone_id + ": todos os slots de edição preservados")
		check(partial.find_children("*", "CollisionShape3D", true, false).size() == EXPECTED_SOLIDS[zone_id], zone_id + ": nenhum sólido removido")
		check(_signature(immediate) == _signature(partial), zone_id + ": mesma geometria, transformações, materiais e colisões")
		var completed_index: int = job.index
		FACTORY.step_zone(job, 0.0)
		check(int(job.index) == completed_index, zone_id + ": repetir pedido pronto não duplica peças")
		immediate.free()
		partial.free()
		var interrupted := FACTORY.begin_zone(zone_id)
		FACTORY.step_zone(interrupted, 0.0)
		var cancelled_root: Node3D = interrupted.root
		FACTORY.cancel_zone(interrupted)
		check(interrupted.is_empty() and not is_instance_valid(cancelled_root), zone_id + ": cancelamento libera construção parcial")
	check(FACTORY.begin_zone("missing").is_empty(), "zona inválida não aloca construção")
	for failure in failures: print("FALHOU: ", failure)
	print("test_route_incremental checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _signature(node: Node) -> Array:
	var result: Array = [node.get_class()]
	var label := str(node.name)
	result.append("<generated>" if label.begins_with("@") else label)
	if node is Node3D: result.append(node.transform)
	if node is MeshInstance3D:
		result.append([node.mesh.get_aabb(), node.mesh.get_surface_count(), node.cast_shadow, node.material_override])
	if node is CollisionShape3D:
		var shape := node.shape as Shape3D
		var values: Array = [shape.get_class(), node.disabled]
		for field in ["size", "radius", "height", "points"]:
			if field in shape: values.append([field, shape.get(field)])
		result.append(values)
	if node is CollisionObject3D: result.append([node.collision_layer, node.collision_mask])
	for child in node.get_children(): result.append(_signature(child))
	return result

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
