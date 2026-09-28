extends SceneTree
const BASE := preload("res://world/urban_detail/HarborAreaDressing3D.gd")
const EDITABLE := preload("res://world/editing/EditableCobraDressing.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const ROUTE := preload("res://world/harbor_route_detail/HarborRouteDetailFactory.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func snapshot(node: Node, meshes: Array[String], shapes: Array[String]) -> void:
	if node is MeshInstance3D:
		var entry := str(node.global_transform)+"|"+str(node.mesh.get_aabb())
		if node.material_override is BaseMaterial3D: entry += "|"+str(node.material_override.albedo_color)
		meshes.append(entry)
	if node is CollisionShape3D: shapes.append(str(node.global_transform)+"|"+str(node.shape.size))
	for child in node.get_children(): snapshot(child, meshes, shapes)

func ids(node: Node) -> Array[String]:
	var result: Array[String] = []
	for piece in PIECES.collect(node): result.append(str(piece.get_meta("world_edit_piece_id")))
	result.sort()
	return result

func find_piece(node: Node, key: String) -> Node3D:
	for piece in PIECES.collect(node):
		if piece.get_meta("world_edit_piece_id") == key: return piece
	return null

func shapes_in(node: Node) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	if node is CollisionShape3D: result.append(node)
	for child in node.get_children(): result.append_array(shapes_in(child))
	return result

func hits(point: Vector3, body: Node) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = 1
	for hit in root.get_world_3d().direct_space_state.intersect_point(query):
		if hit.collider == body: return true
	return false

func run() -> void:
	var base := BASE.new()
	base.configure("cobra")
	base.position = Vector3(481.25,0,106.25)
	root.add_child(base)
	var edited := EDITABLE.new()
	edited.configure("cobra")
	edited.position = base.position
	root.add_child(edited)
	await process_frame
	var before_mesh: Array[String] = []
	var before_shape: Array[String] = []
	var after_mesh: Array[String] = []
	var after_shape: Array[String] = []
	snapshot(base, before_mesh, before_shape)
	snapshot(edited, after_mesh, after_shape)
	before_mesh.sort(); before_shape.sort(); after_mesh.sort(); after_shape.sort()
	check(before_mesh == after_mesh, "Cobra grouping preserves every mesh transform, bounds and color")
	check(before_shape == after_shape, "Cobra grouping preserves every collision shape and transform")
	check(ids(edited).size() > 100, "Paths, fences, benches and trees are individually editable")
	var unique := {}
	for id in ids(edited): unique[id] = true
	check(unique.size() == ids(edited).size(), "Cobra piece IDs are unique")
	var second := EDITABLE.new()
	second.configure("cobra")
	root.add_child(second)
	check(ids(second) == ids(edited), "Cobra piece IDs survive reconstruction")
	second.free()
	base.free()
	var bench := find_piece(edited,"cobra/banco/0")
	check(bench != null, "Bench is a coherent individually movable piece")
	var bench_shapes := shapes_in(bench)
	check(bench_shapes.size() == 2, "Bench seat and back solids share its transform")
	var shape := bench_shapes[0]
	var body := shape.get_parent()
	var old_point := shape.global_position
	var original := bench.global_transform
	await physics_frame
	await process_frame
	check(hits(old_point, body), "Original bench is physically solid")
	var local_point := original.affine_inverse()*old_point
	var row := {"type":"piece", "position":[original.origin.x+100,original.origin.z+100], "rotation":90}
	PIECES.apply(edited,{"piece/cobra/banco/0":row})
	var new_point := bench.global_transform*local_point
	check(shape.global_position.is_equal_approx(new_point), "Visual and collider move and rotate together")
	await physics_frame
	await process_frame
	check(not hits(old_point, body), "No stale collider remains at the old bench location")
	check(hits(new_point, body), "Moved bench collides at its new location")
	PIECES.apply(edited,{"piece/cobra/banco/0":row})
	check(shape.global_position.is_equal_approx(new_point), "Reapplying edit does not accumulate rotation")
	for zone_id in ["rodoviaria","connecting_streets","delegacia","maciota"]:
		var zone := ROUTE.create_zone(zone_id)
		EDITABLE.tag_route(zone, zone_id)
		check(PIECES.collect(zone).size() == zone.get_child_count(), "Every street furnishing piece is tagged: "+zone_id)
		zone.free()
	edited.free()
	print("WORLD_EDITOR_COBRA checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
