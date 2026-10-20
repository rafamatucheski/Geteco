extends SceneTree
## Adereços das zonas do porto vindos do Blender (assets/city_props/harbor_route_props.glb,
## feito por tools/blender/build_harbor_route_props.py). Para cada chamada que as zonas
## usam, compara a versão modelada com a procedural: envelope, um material por malha (os
## de HarborRouteMaterials), formato de vértice igual ao das CylinderMesh/BoxMesh antigas
## (sem variante de shader nova), parte que acende com o mesmo nome e na mesma altura, e
## o interruptor GETECO_BLENDER_PROPS=0 devolvendo a procedural.
## Não mede desempenho nem aparência.
const FORMAT_MASK := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
const MAX_TRIANGLES := 2500
const LAMP_NAMES := ["Lens", "Bulb", "Globe_Pair", "Globe_Left", "Globe_Right"]
var failures: Array[String] = []

func _initialize() -> void:
	var calls := {
		"poste padrão": func() -> Node3D: return HarborRouteProps.create_streetlight(5.4, 1.35, "standard", 0.0),
		"poste polícia": func() -> Node3D: return HarborRouteProps.create_streetlight(4.8, 1.2, "police", 0.0),
		"poste industrial": func() -> Node3D: return HarborRouteProps.create_streetlight(5.2, 1.1, "industrial", 0.0),
		"balizador cívico": func() -> Node3D: return HarborRouteProps.create_bollard("civic"),
		"balizador polícia": func() -> Node3D: return HarborRouteProps.create_bollard("police"),
		"balizador faixa": func() -> Node3D: return HarborRouteProps.create_bollard("hazard"),
		"banco 2,0": func() -> Node3D: return HarborRouteProps.create_bench(2.0),
		"banco 2,2": func() -> Node3D: return HarborRouteProps.create_bench(2.2),
		"lixeira": func() -> Node3D: return HarborRouteProps.create_trash_bin(),
		"bicicletário": func() -> Node3D: return HarborRouteProps.create_bike_rack(4, 0.85),
		"hidrante": func() -> Node3D: return HarborRouteProps.create_fire_hydrant(),
		"floreira": func() -> Node3D: return HarborRouteProps.create_planter_box(Vector3(1.8, 0.45, 0.85)),
		"grelha": func() -> Node3D: return HarborRouteProps.create_drain_grate(),
		"grelha girada": func() -> Node3D: return HarborRouteProps.create_drain_grate(Vector2(0.45, 0.85)),
	}
	# A CylinderMesh entrega estes arrays ao servidor sem flags; o ArrayMesh igual dá o formato.
	var primitive := ArrayMesh.new()
	primitive.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CylinderMesh.new().get_mesh_arrays())
	var reference: int = primitive.surface_get_format(0) & FORMAT_MASK
	check(HarborRouteProps.blender_props_enabled, "interruptor ligado por padrão")
	for label: String in calls:
		HarborRouteProps.blender_props_enabled = true
		var modeled: Node3D = calls[label].call()
		HarborRouteProps.blender_props_enabled = false
		var old: Node3D = calls[label].call()
		var visuals := _visuals(modeled)
		check(not visuals.is_empty() and visuals.all(func(v: MeshInstance3D) -> bool: return String(v.name).begins_with("Modeled_") or String(v.name) in LAMP_NAMES), "%s: só malhas do Blender (%d)" % [label, visuals.size()])
		check(_visuals(old).any(func(v: MeshInstance3D) -> bool: return not String(v.name).begins_with("Modeled_")), "%s: interruptor 0 volta à procedural" % label)
		check(String(modeled.name) == String(old.name), "%s: mesmo nome de raiz (%s)" % [label, modeled.name])
		var triangles := 0
		for visual: MeshInstance3D in visuals:
			check(visual.mesh.get_surface_count() == 1, "%s/%s: uma superfície" % [label, visual.name])
			check(visual.mesh.surface_get_format(0) & FORMAT_MASK == reference, "%s/%s: formato de vértice das primitivas (%d x %d)" % [label, visual.name, visual.mesh.surface_get_format(0) & FORMAT_MASK, reference])
			check(visual.material_override != null and visual.mesh.surface_get_material(0) == null, "%s/%s: material do porto por cima, nenhum embutido" % [label, visual.name])
			triangles += visual.mesh.surface_get_array_index_len(0) / 3
		check(triangles < MAX_TRIANGLES, "%s: %d triângulos" % [label, triangles])
		var a := _bounds(modeled)
		var b := _bounds(old)
		check(absf(a.position.y - b.position.y) < .03, "%s: apoiado no chão (y %.3f x %.3f)" % [label, a.position.y, b.position.y])
		check(_near(a.size.x, b.size.x, .25) and _near(a.size.z, b.size.z, .3), "%s: pegada %.2f x %.2f (antes %.2f x %.2f)" % [label, a.size.x, a.size.z, b.size.x, b.size.z])
		check(_near(a.end.y, b.end.y, .25), "%s: altura %.2f (antes %.2f)" % [label, a.end.y, b.end.y])
		var collisions: Array = [modeled.find_children("*", "CollisionShape3D", true, false).size(), old.find_children("*", "CollisionShape3D", true, false).size()]
		check(collisions[0] == collisions[1], "%s: mesma colisão (%d x %d)" % [label, collisions[0], collisions[1]])
		if label.begins_with("poste"):
			var lamp_new := _lamp(modeled)
			var lamp_old := _lamp(old)
			check(lamp_new != null, "%s: parte que acende com nome que o CityChunkDressing reconhece" % label)
			if lamp_new != null and lamp_old != null:
				var drift := _local(modeled, lamp_new).origin.y - _local(old, lamp_old).origin.y
				check(absf(drift) < .3, "%s: luz na mesma altura (diferença %.2f m)" % [label, drift])
		modeled.free()
		old.free()
	for failure in failures: print("FALHOU: ", failure)
	print("test_blender_harbor_props: ", "OK" if failures.is_empty() else "%d falha(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _visuals(root: Node3D) -> Array:
	return root.find_children("*", "MeshInstance3D", true, false)

func _local(root: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != root and current is Node3D:
		result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func _bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for visual: MeshInstance3D in _visuals(root):
		var box := _local(root, visual) * visual.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _lamp(root: Node3D) -> MeshInstance3D:
	for visual: MeshInstance3D in _visuals(root):
		if String(visual.name) in LAMP_NAMES or String(visual.name).begins_with("Globe_"): return visual
	return null

## Proporcional, com 6 cm de folga para peça fina (tubo do bicicletário com sapata no chão).
func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= maxf(b * tolerance, .06)

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	else: print("ok: ", label)
