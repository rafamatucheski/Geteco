extends SceneTree
## Triângulos por tipo da terceira onda do Blender × procedural, e quem projeta sombra.
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tests/measure/count_wave3_triangles.gd
## Grava evidence/blender-props/wave3-triangles.json.

const KIT := preload("res://world/city_look/CityPropKit.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")


func _initialize() -> void:
	var rows := {}
	for modeled in [true, false]:
		KIT.blender_wave3_enabled = modeled
		KIT._meshes.clear()
		for kind: String in KIT.WAVE3_KINDS:
			var row: Dictionary = rows.get_or_add(kind, {"shadow": kind in DRESSING.SHADOW_CASTERS, "tree": kind in KIT.TREE_KINDS})
			row["blender" if modeled else "procedural"] = _triangles(KIT.mesh(kind))
	var lines: Array[String] = []
	for kind: String in rows:
		var row: Dictionary = rows[kind]
		lines.append("%s\t%d\t%d\t%s" % [kind, row.procedural, row.blender, "sombra" if row.shadow else ""])
	print("tipo\tprocedural\tblender\tsombra\n" + "\n".join(lines))
	var path := ProjectSettings.globalize_path("res://evidence/blender-props/wave3-triangles.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))
	quit(0)


func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		total += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total
