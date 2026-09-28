extends SceneTree
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const DRESSING := preload("res://world/editing/EditableCobraDressing.gd")
const YARD := preload("res://world/places/SalvageYardNative.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func find_piece(parent: Node, key: String) -> Node3D:
	for piece in PIECES.collect(parent):
		if piece.get_meta("world_edit_piece_id") == key: return piece
	return null
func bounds(parent: Node) -> AABB:
	var points: Array[Vector3] = []
	PIECES._points(parent, points)
	var result := AABB(points[0], Vector3.ZERO)
	for point in points: result = result.expand(point)
	return result
func ray(parent: Node3D, x: float, z: float) -> Dictionary:
	return parent.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 20, z), Vector3(x, -2, z), 1))

func run() -> void:
	var yard := YARD.new()
	root.add_child(yard)
	var office := find_piece(yard, "neco/Office")
	var initial := bounds(office)
	var body: StaticBody3D = office.find_children("*", "StaticBody3D", true, false)[0]
	var collider: CollisionShape3D = body.get_child(0)
	var original_shape := collider.shape
	var original_shape_bounds := original_shape.get_debug_mesh().get_aabb()
	var original_position := office.global_position
	var row := {"id":"piece/neco/Office", "type":"piece", "position":[120.0, 140.0], "rotation":0.0, "stretch":[.5, .25]}
	PIECES.apply(yard, {row.id:row})
	var resized := bounds(office)
	check(is_equal_approx(resized.size.x, initial.size.x*.5) and is_equal_approx(resized.size.z, initial.size.z*.25), "Office footprint shrinks independently on X and Z")
	check(is_equal_approx(resized.size.y, initial.size.y), "Footprint scaling preserves building height")
	check(body.global_basis.get_scale().is_equal_approx(Vector3.ONE) and collider.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Physics bodies and shapes have unit world scale")
	check(collider.shape != original_shape and original_shape.get_debug_mesh().get_aabb().is_equal_approx(original_shape_bounds), "Scaling uses a private collider and preserves source shape")
	await physics_frame
	await physics_frame
	check(not ray(office, 120, 140).is_empty(), "Shrunk and moved office blocks at its new center")
	check(ray(office, 120+initial.size.x*.4, 140).is_empty(), "Space released by shrinking has no ghost collision")
	PIECES.apply(yard, {row.id:row})
	check(bounds(office).is_equal_approx(resized), "Repeated stretch application does not accumulate")
	row.rotation = 90.0
	PIECES.apply(yard, {row.id:row})
	var rotated := bounds(office)
	check(is_equal_approx(rotated.size.x, resized.size.z) and is_equal_approx(rotated.size.z, resized.size.x), "Rotation is applied after original-axis stretch")
	row.stretch = [1.0, 1.0]
	row.rotation = 0.0
	row.position = [original_position.x, original_position.z]
	PIECES.apply(yard, {row.id:row})
	check(bounds(office).is_equal_approx(initial) and collider.shape == original_shape, "Reset restores exact original mesh footprint and collider")
	var press := find_piece(yard, "neco/press")
	var press_transform := press.global_transform
	PIECES.apply(yard, {"piece/neco/press":{"type":"piece", "position":[99,99], "rotation":45, "stretch":[.1,4]}})
	check(press.global_transform.is_equal_approx(press_transform), "Operational machinery remains protected from resize")
	yard.free()
	var dressing := DRESSING.new()
	dressing.configure("cobra")
	dressing.position = Vector3(30, 2, 40)
	root.add_child(dressing)
	var path := find_piece(dressing, "cobra/cobra_footpath/2")
	var info := PIECES.shape_info(path)
	check(info.has("outline") and info.outline.size() == 4, "Actual slanted Cobra path exposes source outline")
	check(not PIECES.is_shape_editable("piece/cobra/cobra_yard_fence/0"), "Fence does not accept ground outlines")
	var mesh: MeshInstance3D = info.mesh
	var original_mesh := mesh.mesh
	var material := mesh.material_override
	var source_path_bounds := bounds(path)
	var target_outline := [[-2.0,-1.0], [2.0,-1.0], [2.0,1.0], [0.0,1.0], [0.0,3.0], [-2.0,3.0]]
	row = {"id":"piece/cobra/cobra_footpath/2", "type":"piece", "position":[100.0, 100.0], "rotation":0.0, "stretch":[.5, 2.0], "outline":target_outline}
	PIECES.apply(dressing, {row.id:row})
	var shaped := bounds(path)
	check(mesh.mesh is ArrayMesh and mesh.mesh != original_mesh, "Edited path generates polygon mesh")
	check(is_equal_approx(shaped.size.x, 2.0) and is_equal_approx(shaped.size.z, 8.0), "Outline follows saved shape and stretch")
	check(is_equal_approx(shaped.position.y, source_path_bounds.position.y) and is_equal_approx(shaped.end.y, source_path_bounds.end.y), "Polygon preserves original ground elevation and thickness")
	check(mesh.material_override == material, "Polygon preserves material")
	check(path.find_children("*", "CollisionShape3D", true, false).is_empty(), "Decorative source path keeps existing ground collision policy")
	var faces := mesh.mesh.get_faces()
	var top_area := 0.0
	for i in range(0, faces.size(), 3):
		if is_equal_approx(faces[i].y, float(info.top)) and is_equal_approx(faces[i+1].y, float(info.top)) and is_equal_approx(faces[i+2].y, float(info.top)):
			top_area += (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length()*.5
	check(is_equal_approx(top_area, 12.0), "Concave outline triangulates without filling its missing corner")
	PIECES.apply(dressing, {row.id:row})
	check(bounds(path).is_equal_approx(shaped), "Outline reapplication preserves dimensions")
	row.erase("outline")
	row.stretch = [1,1]
	PIECES.apply(dressing, {row.id:row})
	check(mesh.mesh == original_mesh, "Removing outline restores authored box mesh")
	dressing.free()
	# A colliding flat source verifies polygon collision, not only its drawing.
	var floor_piece := Node3D.new()
	root.add_child(floor_piece)
	PIECES.mark(floor_piece, "cobra/cobra_home_gravel/0", "Piso")
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(4, .04, 4)
	floor_mesh.mesh = floor_box
	floor_piece.add_child(floor_mesh)
	var floor_body := StaticBody3D.new()
	floor_piece.add_child(floor_body)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = floor_box.size
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	row = {"id":"piece/cobra/cobra_home_gravel/0", "type":"piece", "position":[200,200], "rotation":0, "outline":target_outline}
	PIECES.apply(floor_piece, {row.id:row})
	await physics_frame
	await physics_frame
	check(not ray(floor_piece, 199, 202).is_empty(), "Polygon collider supports solid part of concave floor")
	check(ray(floor_piece, 201, 202).is_empty(), "Polygon collider leaves concave missing corner open")
	check(floor_body.global_basis.get_scale().is_equal_approx(Vector3.ONE) and floor_collision.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Polygon physics remains unscaled")
	floor_piece.free()
	print("WORLD_EDITOR_PIECE_SHAPES checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
