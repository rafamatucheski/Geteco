extends SceneTree

const DRESSING := preload("res://world/mountain_pass/transit/MountainWinterDressing.gd")
const MODEL := preload("res://world/mountain_pass/transit/MountainWinterDressing3D.gd")
const POCKET := preload("res://world/mountain_pass/MountainVillageLayout.gd")

class RoadFixture extends Node2D:
	var curve := Curve2D.new()
	var road_width := 96.0

	func _init() -> void:
		curve.bake_interval = 8.0
		curve.add_point(Vector2(6030, -1510))
		curve.add_point(Vector2(6260, -1840))
		curve.add_point(Vector2(6510, -2260))
		curve.add_point(Vector2(6460, -2580))
		curve.add_point(Vector2(7000, -2910))

	func is_point_on_road(point: Vector2, clearance: float) -> bool:
		return point.distance_to(curve.get_closest_point(point)) <= clearance

class WorldFixture extends Node2D:
	var road: Node2D

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error(message)

func count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += count_nodes(child)
	return total

func count_type(node: Node, type_name: StringName) -> int:
	var total := 1 if node.is_class(type_name) else 0
	for child in node.get_children():
		total += count_type(child,type_name)
	return total

func native_mesh_count(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += native_mesh_count(child)
	return total

func visual_instance_count(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D and node.visible:
		total += 1
	elif node is MultiMeshInstance3D and node.visible and node.multimesh != null:
		total += node.multimesh.visible_instance_count
	for child in node.get_children():
		total += visual_instance_count(child)
	return total

func run() -> void:
	var world := WorldFixture.new()
	var road := RoadFixture.new()
	world.road = road
	world.add_child(road)
	var settlement := Node2D.new()
	settlement.name = "WinterDressingFixture"
	world.add_child(settlement)
	root.add_child(world)

	var started := Time.get_ticks_usec()
	await DRESSING.install_pockets(settlement)
	var install_usec := Time.get_ticks_usec()-started
	for frame in 2:
		await process_frame

	var kinds := {}
	var polygon_vertices := 0
	var solid_count := 0
	var walkable_count := 0
	var proxy_count := 0
	for body in get_nodes_in_group("mountain_dressing"):
		var kind := String(body.get_meta("dressing_kind", ""))
		kinds[kind] = int(kinds.get(kind,0))+1
		var polygon: PackedVector2Array = body.get_meta("dressing_polygon",PackedVector2Array())
		polygon_vertices += polygon.size()
		check(polygon.size() >= 3, "Every installed dressing feature keeps a non-empty projected polygon")
		var model: Node = body.get_meta("dressing_model",null)
		check(is_instance_valid(model), "Every physical feature keeps its 3D model contract")
		if is_instance_valid(model):
			var model_meshes := native_mesh_count(model)
			proxy_count += model_meshes
			check(model_meshes == 1, "Each feature keeps exactly one MeshInstance3D footprint proxy")
			var proxy := model.get_node_or_null("FootprintProxy") as MeshInstance3D
			check(proxy != null and not proxy.visible, "Footprint proxy is present and excluded from visual rendering")
		if bool(body.get_meta("walkable",false)):
			walkable_count += 1
			check(body.collision_layer == 0, "Walkable branches remain non-blocking")
		else:
			solid_count += 1
			check((body.collision_layer&1) != 0, "Solid dressing remains on the world collision layer")
			var shape := body.get_child(0) as CollisionPolygon2D
			check(shape != null and shape.polygon.size() >= 3, "Solid dressing retains a CollisionPolygon2D")

	var props := get_nodes_in_group("mountain_dressing").size()
	var nodes := count_nodes(settlement)
	var multimeshes := count_type(settlement,&"MultiMeshInstance3D")
	var visible_primitives := visual_instance_count(settlement)
	var viewports := count_type(settlement,&"SubViewport")
	print("WINTER_DRESSING_MULTIMESH_METRICS ",{
		"install_usec":install_usec,
		"nodes":nodes,
		"physical_features":props,
		"footprint_proxies":proxy_count,
		"multimesh_nodes":multimeshes,
		"visible_primitives":visible_primitives,
		"viewports":viewports,
		"polygon_vertices":polygon_vertices,
		"solids":solid_count,
		"walkable":walkable_count,
		"kinds":kinds,
	})

	check(viewports == POCKET.POCKETS.size()+3, "Every pocket and roadside 3D view remains installed")
	check(props > 0 and solid_count > 0 and walkable_count > 0, "Physical winter dressing remains populated")
	for kind in ["pine","rock","branches"]:
		check(int(kinds.get(kind,0)) > 0, "Winter dressing retains %s"%kind)
	check(proxy_count == props, "Every accepted feature has one conservative hull source")
	check(multimeshes > 0 and multimeshes <= viewports*9, "Visual meshes are bounded by shape/material batches per view")
	check(visible_primitives > 500, "Dense native 3D detail remains present after compaction")
	check(nodes < visible_primitives/2, "Retained scene-tree nodes are substantially fewer than visual primitives")

	# Direct four-kind signature complements the route-filtered integration fixture:
	# no candidate is rejected, so visual primitive parity is deterministic.
	var direct_model := MODEL.new()
	root.add_child(direct_model)
	direct_model.build([
		{"kind":"pine","point":Vector2(0,0),"scale":1.0,"angle":0.0},
		{"kind":"rock","point":Vector2(80,0),"scale":1.0,"angle":0.0},
		{"kind":"log","point":Vector2(160,0),"scale":1.0,"angle":0.0},
		{"kind":"branches","point":Vector2(240,0),"scale":1.0,"angle":0.0},
	])
	for index in direct_model.features.size():
		direct_model.dress_base(direct_model.features[index],index)
	var direct_primitives := visual_instance_count(direct_model)
	var direct_multimeshes := count_type(direct_model,&"MultiMeshInstance3D")
	print("WINTER_DRESSING_FOUR_KIND_SIGNATURE ",{
		"visible_primitives":direct_primitives,
		"multimesh_nodes":direct_multimeshes,
		"feature_count":direct_model.features.size(),
	})
	check(direct_model.features.size() == 4, "Direct signature retains pine, rock, log and branches")
	check(direct_primitives == 138, "Four-kind visual signature retains every original primitive")
	check(direct_multimeshes == 9, "Four-kind visual signature uses one batch per shape/material pair")
	for feature in direct_model.features:
		check(native_mesh_count(feature.root) == 1, "Every direct feature retains one hull proxy")

	world.queue_free()
	direct_model.queue_free()
	for frame in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)
