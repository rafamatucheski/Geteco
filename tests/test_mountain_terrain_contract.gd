extends SceneTree
## Functional terrain/render agreement; not a frame-time benchmark.
const TERRAIN = preload("res://world/regions/MountainTerrain3D.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("TERRAIN PASS " if ok else "TERRAIN FAIL ") + label)
	if not ok: failures.append(label)

## A malha na GPU guarda posições comprimidas (quantizadas): a leitura de volta difere da CPU em ~0,05 mm.
## A colisão agora sai das arrays exatas da CPU (auditoria de 19/10), então a comparação usa tolerância.
const FACE_TOLERANCE := 0.001

## Triângulos na rotação canônica (preserva o sentido), ordenados por uma chave arredondada a 1 cm.
func canonical_faces(faces: PackedVector3Array) -> Array:
	var out: Array = []
	for offset in range(0, faces.size(), 3):
		var tri := [faces[offset], faces[offset + 1], faces[offset + 2]]
		var best := 0
		var best_key := ""
		for r in 3:
			var key := "%s|%s|%s" % [tri[r].snapped(Vector3.ONE * .01), tri[(r + 1) % 3].snapped(Vector3.ONE * .01), tri[(r + 2) % 3].snapped(Vector3.ONE * .01)]
			if r == 0 or key < best_key:
				best = r
				best_key = key
		out.append([best_key, tri[best], tri[(best + 1) % 3], tri[(best + 2) % 3]])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out

func same_faces(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size(): return false
	var ca := canonical_faces(a)
	var cb := canonical_faces(b)
	for i in ca.size():
		for k in range(1, 4):
			if (ca[i][k] as Vector3).distance_to(cb[i][k]) > FACE_TOLERANCE: return false
	return true

func inspect(mesh: MeshInstance3D, label: String) -> void:
	check(mesh.get_child_count() == 1, label + " one body")
	var body := mesh.get_child(0) as StaticBody3D
	check(body != null, label + " static body")
	if body == null: return
	check(body.collision_layer == 1 and body.collision_mask == 0, label + " ground layers preserved")
	check(body.get_meta("mountain_terrain", false), label + " terrain identity preserved")
	check(body.transform == Transform3D.IDENTITY, label + " no collision offset")
	var collider := body.get_child(0) as CollisionShape3D
	check(collider != null and collider.shape is ConcavePolygonShape3D, label + " concave shape")
	if collider == null or not collider.shape is ConcavePolygonShape3D: return
	var shape := collider.shape as ConcavePolygonShape3D
	check(not shape.backface_collision, label + " original backface policy")
	var actual := shape.get_faces()
	# Deliberate readback here only: compare to the original engine conversion.
	var reference := mesh.mesh.create_trimesh_shape()
	check(actual.size() == 1536, label + " full 512 triangles")
	check(same_faces(actual, reference.get_faces()), label + " rendering triangles and winding preserved")

func ground(point: Vector2, terrain: RefCounted, label: String) -> void:
	var expected: float = terrain.surface_height_at(point)
	var position := Vector3(point.x, expected, point.y)
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 2.0, position - Vector3.UP * 2.0, 1)
	var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
	check(not hit.is_empty(), label + " real physics support")
	if hit.is_empty(): return
	check(absf(float(hit.position.y) - expected) < .001, label + " interpolated visual height")
	check(hit.normal.y > 0.0, label + " upward support")

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var terrain := TERRAIN.new()
	terrain.configure([], [], [])
	var rect := Rect2(640, -384, 64, 64)
	var first := terrain.build_chunk(holder, rect)
	var second := terrain.build_chunk(holder, Rect2(rect.position + Vector2(64, 0), rect.size))
	inspect(first, "first")
	inspect(second, "adjacent")
	var left: Array = first.mesh.surface_get_arrays(0)
	var right: Array = second.mesh.surface_get_arrays(0)
	for row in 17:
		var a := row*17+16
		var b := row*17
		check(left[Mesh.ARRAY_VERTEX][a].is_equal_approx(right[Mesh.ARRAY_VERTEX][b]), "seam row %d continuous height"%row)
		check(left[Mesh.ARRAY_NORMAL][a].is_equal_approx(right[Mesh.ARRAY_NORMAL][b]), "seam row %d continuous normal"%row)
	await physics_frame
	await physics_frame
	for offset in [Vector2(8.7, 12.3), Vector2(27.1, 42.8), Vector2(63.99, 11.4), Vector2(64.01, 11.4), Vector2(100.5, 31.2)]:
		ground(rect.position + offset, terrain, str(offset))
	var body_ref: WeakRef = weakref(first.get_child(0))
	first.free()
	await physics_frame
	check(body_ref.get_ref() == null, "removed cell does not retain body")
	var restored := terrain.build_chunk(holder, rect)
	inspect(restored, "restored")
	await physics_frame
	await physics_frame
	ground(rect.position + Vector2(8.7, 12.3), terrain, "return")
	ground(rect.position + Vector2(63.99, 11.4), terrain, "return seam")
	# User-reported mountain priority: shore after the tunnel, summit and the
	# northern ski perimeter. Build the exact tile under each physical sample.
	var visited: Dictionary = {}
	for point in [Vector2(636.3,-337.7),Vector2(698.75,-498.4375),Vector2(700,-553.75),Vector2(763.75,-572.5),Vector2(712.5,-615.625),Vector2(778.2,-625.7),Vector2(777.9,-639.99),Vector2(777.9,-640.01)]:
		var cell := Vector2i(floori(point.x/64.0),floori(point.y/64.0))
		if not visited.has(cell):
			terrain.build_chunk(holder,Rect2(Vector2(cell)*64.0,Vector2.ONE*64.0))
			visited[cell] = true
	await physics_frame
	await physics_frame
	for point in [Vector2(636.3,-337.7),Vector2(698.75,-498.4375),Vector2(700,-553.75),Vector2(763.75,-572.5),Vector2(712.5,-615.625),Vector2(778.2,-625.7),Vector2(777.9,-639.99),Vector2(777.9,-640.01)]:
		ground(point,terrain,"mountain priority "+str(point))
	holder.free()
	await physics_frame
	print("TERRAIN RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

