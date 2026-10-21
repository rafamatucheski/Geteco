extends SceneTree
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var canvas := CANVAS.new()
	root.add_child(canvas)
	canvas.zoom = .05
	var thin := PackedVector2Array([Vector2(1200,500),Vector2(1202,500),Vector2(1202,500.01),Vector2(1200,500.01)])
	var mesh := canvas._polygon_mesh(thin)
	check(mesh != null and mesh.surface_get_array_index_len(0) == 6, "Thin road polygons triangulate in world coordinates at minimum overview zoom")
	if mesh != null:
		check(is_equal_approx(mesh.get_aabb().position.x,1200) and is_equal_approx(mesh.get_aabb().position.y,500), "Mesh vertices stay in world coordinates instead of tiny screen coordinates")
		var id := mesh.get_instance_id()
		canvas.zoom = 8
		canvas.center = Vector2(1200,500)
		check(canvas._polygon_mesh(thin).get_instance_id() == id, "Pan and zoom reuse stable world triangulation")
	var closed := thin.duplicate()
	closed.append(closed[0])
	check(canvas._polygon_mesh(closed) != null, "Duplicate closing vertices are normalized before triangulation")
	check(canvas._polygon_mesh(PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2(2,0)])) == null, "Zero-area polygons are rejected without drawing")
	check(canvas._polygon_mesh(PackedVector2Array([Vector2.ZERO,Vector2(2,2),Vector2(0,2),Vector2(2,0)])) == null, "Self-crossing zero-area contours cannot reach the renderer")
	check(canvas._polygon_mesh(PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2(INF,1)])) == null, "Non-finite polygons cannot reach triangulation")
	canvas.free()
	print("WORLD_EDITOR_POLYGON_PRECISION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
