extends SceneTree
## Lista os componentes soltos (sem vértice em comum com a lata, solda de 1 mm) da metade
## traseira de cada carro, com caixa e topo, para medir a FACTORY_WING_BOX do tuning.
## Uso: --script res://tools/fleet_fixups/probe_factory_wings.gd -- --ids=raijin_gt,kite_type_s [--zmin=1.0] [--ymin=.7]
const FLEET := preload("res://runtime/FleetCatalog.gd")
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var ids: Array = []
	var zmin := 1.0
	var ymin := .7
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): ids = Array(arg.trim_prefix("--ids=").split(","))
		if arg.begins_with("--zmin="): zmin = float(arg.trim_prefix("--zmin="))
		if arg.begins_with("--ymin="): ymin = float(arg.trim_prefix("--ymin="))
	for id: String in ids:
		var model: Node3D = FLEET.create(id)
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if part.mesh == null or part.has_meta("wheel_center"): continue
			for surface in part.mesh.get_surface_count():
				var arrays := MESH_ARRAYS.arrays_of(part.mesh,surface)
				if arrays.is_empty(): continue
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if indices.is_empty():
					for i in vertices.size(): indices.append(i)
				var parent := {}
				var keys: Array[Vector3i] = []
				for v in vertices: keys.append(Vector3i(roundi(v.x*1000.0),roundi(v.y*1000.0),roundi(v.z*1000.0)))
				for i in range(0,indices.size(),3):
					var a := _root(parent,keys[indices[i]])
					for j in [1,2]:
						var b := _root(parent,keys[indices[i+j]])
						if a != b: parent[b] = a
				var boxes := {}
				for i in range(0,indices.size(),3):
					var r := _root(parent,keys[indices[i]])
					for j in 3:
						var p := vertices[indices[i+j]]
						boxes[r] = AABB(p,Vector3.ZERO) if not boxes.has(r) else (boxes[r] as AABB).expand(p)
				for r in boxes:
					var b: AABB = boxes[r]
					if b.position.z < zmin or b.end.y < ymin: continue
					print("WING_PROBE %s %s/%d min=(%.3f,%.3f,%.3f) max=(%.3f,%.3f,%.3f)" % [id,part.name,surface,b.position.x,b.position.y,b.position.z,b.end.x,b.end.y,b.end.z])
		model.free()
	quit(0)

static func _root(parent: Dictionary, key: Vector3i) -> Vector3i:
	var r := key
	while parent.has(r) and parent[r] != r: r = parent[r]
	return r
