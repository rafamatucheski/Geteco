extends SceneTree
## Objetos do editor de mundo vindos do Blender (assets/city_props/editor_props.glb,
## tools/blender/build_editor_props.py). Para cada modelo, compara com a montagem antiga:
## envelope, mesma colisão, cor da linha do editor na parte principal, formato de vértice
## das primitivas (sem shader novo) e GETECO_BLENDER_PROPS=0 devolvendo as caixas.
## Não mede desempenho nem aparência.
const FACTORY := preload("res://world/editing/WorldPropFactory.gd")
const FORMAT_MASK := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
var failures: Array[String] = []

func _initialize() -> void:
	var primitive := ArrayMesh.new()
	primitive.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	var reference: int = primitive.surface_get_format(0) & FORMAT_MASK
	var color := Color("2c5a8a")
	for model: String in FACTORY.MODELED_HEIGHTS:
		var row := {"model": model, "id": "teste_" + model, "color": color.to_html(false), "scale": 1.0, "rotation": 0.0}
		FACTORY.blender_props_enabled = true
		var modeled := FACTORY.create(row)
		FACTORY.blender_props_enabled = false
		var old := FACTORY.create(row)
		var visuals: Array = modeled.find_children("*", "MeshInstance3D", true, false)
		check(not visuals.is_empty() and visuals.all(func(v: Node) -> bool: return String(v.name).begins_with("Modeled_")), "%s: só malhas do Blender" % model)
		check(not old.find_children("Modeled_*", "MeshInstance3D", true, false).size(), "%s: interruptor 0 volta à montagem antiga" % model)
		var main := modeled.find_child("Modeled_main", true, false) as MeshInstance3D
		if model in ["crate", "barrel", "bin", "barrier", "dumpster"]:
			check(main != null and main.material_override == FACTORY.material(color), "%s: parte principal com a cor do editor" % model)
		for visual: MeshInstance3D in visuals:
			check(visual.mesh.surface_get_format(0) & FORMAT_MASK == reference, "%s/%s: formato de vértice das primitivas" % [model, visual.name])
		var a := _bounds(modeled)
		var b := _bounds(old)
		# As caixas antigas às vezes flutuavam 3 cm ou afundavam 5 cm; os modelos encostam no chão.
		check(absf(a.position.y) < .01 and absf(a.position.y - b.position.y) < .06, "%s: apoiado no chão (%.3f x %.3f)" % [model, a.position.y, b.position.y])
		check(absf(a.size.x - b.size.x) <= maxf(b.size.x * .15, .06) and absf(a.size.z - b.size.z) <= maxf(b.size.z * .2, .06), "%s: pegada %.2f x %.2f (antes %.2f x %.2f)" % [model, a.size.x, a.size.z, b.size.x, b.size.z])
		check(absf(a.end.y - b.end.y) <= maxf(b.end.y * .15, .05), "%s: altura %.2f (antes %.2f)" % [model, a.end.y, b.end.y])
		var shape_a := (modeled.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D)
		var shape_b := (old.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D)
		check((shape_a.shape as BoxShape3D).size.is_equal_approx((shape_b.shape as BoxShape3D).size) and shape_a.position.is_equal_approx(shape_b.position), "%s: mesma colisão" % model)
		modeled.free()
		old.free()
	for failure in failures: print("FALHOU: ", failure)
	print("test_blender_editor_props: ", "OK" if failures.is_empty() else "%d falha(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for visual: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = visual.transform * visual.get_aabb()
		var parent := visual.get_parent()
		while parent != root and parent is Node3D:
			box = (parent as Node3D).transform * box
			parent = parent.get_parent()
		result = box if first else result.merge(box)
		first = false
	return result

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	else: print("ok: ", label)
