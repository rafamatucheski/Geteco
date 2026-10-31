extends SceneTree
## Exteriores e terreno autorais reais: mantém a oficina e a casa realocada
## separadas, com aproximações apoiadas para pedestre e veículo.
const REGION := preload("res://world/editing/EditableRegion.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const MACIOTA := preload("res://world/maciota/MaciotaPlace.gd")
const RESIDENCE := preload("res://activities/Residence.gd")
const PARKING := preload("res://world/places/ResidenceParking.gd")
var checks := 0
var failures: Array[String] = []
var scene: Node3D

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func solid_meshes(node: Node3D) -> Array[AABB]:
	var result: Array[AABB] = []
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh is BoxMesh: continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		# Massas estruturais na altura de pedestre; calçamento, acabamento do telhado e frisos
		# não estabelecem se um prédio ocupa outro prédio.
		if bounds.position.y < 2.1 and bounds.end.y > .4 and bounds.size.y > .35 and bounds.size.x > .5 and bounds.size.z > .5:
			result.append(bounds)
	return result

func meshes_separate(a: Array[AABB], b: Array[AABB]) -> bool:
	for first in a:
		for second in b:
			if first.intersects(second): return false
	return true

func supported(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .25, point - Vector3.UP * .8, 1)
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit.normal as Vector3).y > .7

func shape_clear(point: Vector3, shape: Shape3D, lift: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * lift)
	return scene.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func clear_path(start: Vector3, finish: Vector3, shape: Shape3D, lift: float) -> bool:
	var samples := maxi(1, ceili(start.distance_to(finish) / .25))
	for index in samples + 1:
		var point := start.lerp(finish, float(index) / samples)
		if not supported(point) or not shape_clear(point, shape, lift): return false
	return true

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var workshop := MACIOTA.new()
	workshop.interior_origin = Vector3(0, 0, -2000)
	scene.add_child(workshop)
	var region := REGION.build_region("harbor")
	region.initial_prewarm_only = true
	scene.add_child(region)
	region.set_process(false)
	check(not region.buildings.any(func(row): return row.id == "FreightDepot"), "The pharmacy warehouse is absent from production building data")
	var depot_record := false
	for rows in region.records.values():
		for row in rows:
			if row.kind == "building" and row.data.id == "FreightDepot": depot_record = true
	check(not depot_record, "No streamed FreightDepot record can rebuild the obstruction")
	var definition := PLACES.get_definition("quayside_house")
	for point: Vector3 in [workshop.entry_position, definition.exterior_position, definition.return_position]:
		region._ensure_chunk(Vector2i(floori(point.x / 64.0), floori(point.z / 64.0)))
	for frame in 4: await physics_frame
	var house := region.find_child("quayside_house", true, false) as Node3D
	check(house != null, "The owned residence still has its real exterior")
	check(region.find_child("FreightDepot", true, false) == null, "No warehouse visual or collider is instantiated")
	if house == null:
		finish()
		return
	var workshop_solids := solid_meshes(workshop.facade)
	var house_solids := solid_meshes(house)
	check(not workshop_solids.is_empty() and not house_solids.is_empty(), "Both real structural meshes participate in overlap validation")
	check(meshes_separate(workshop_solids, house_solids), "Residence walls and parking structure do not intersect the workshop or its annex")
	check(house.global_position.z > workshop.exterior_return.z, "The residence is south of the garage, in the cleared pharmacy parcel")
	check(house.global_position.is_equal_approx(definition.exterior_position), "Residence exterior uses the live place definition")
	var residence := RESIDENCE.new()
	check(residence.entry("quayside_house").is_equal_approx(definition.entry_position), "Purchase and entry interaction follow the relocated house")
	var return_matches := false
	for entry in region.entries:
		if entry.id == "quayside_house": return_matches = entry.position.is_equal_approx(definition.entry_position) and entry.return_position.is_equal_approx(definition.return_position)
	check(return_matches, "Checkpoint and exterior return follow the same relocated entrance")
	var capsule := CapsuleShape3D.new()
	capsule.radius = .34
	capsule.height = 1.8
	for point: Vector3 in [workshop.entry_position, workshop.exterior_return, definition.entry_position, definition.return_position]:
		check(supported(point) and shape_clear(point, capsule, .98), "Full pedestrian capsule and floor are clear at %s" % point)
	check(clear_path(definition.entry_position, definition.return_position, capsule, .98), "The relocated entrance and return have a continuous pedestrian path")
	var parking := house.get_node("ResidentialGarage") as Node3D
	var car_hull := BoxShape3D.new()
	car_hull.size = Vector3(2.2, 1.5, 5.3)
	for slot in ["car", "motorcycle"]:
		var point: Vector3 = residence.parking("quayside_house", slot)
		var authored: Vector3 = parking.to_global(PARKING.MOTO if slot == "motorcycle" else PARKING.CAR)
		check(point.is_equal_approx(authored), "Persistent %s slot matches its visible residence bay" % slot)
		if slot == "car":
			check(clear_path(point, point + Vector3.BACK * 7.0, car_hull, 1.0), "The full car hull can use the southern driveway without crossing a building")
			for offset in [Vector3(-1, 0, -2.4), Vector3(1, 0, -2.4), Vector3(-1, 0, 2.4), Vector3(1, 0, 2.4)]:
				check(supported(point + offset), "The relocated car bay supports its corner %s" % offset)
		else:
			check(supported(point) and shape_clear(point, capsule, .98), "Motorcycle bay has supported free space")
	finish()

func finish() -> void:
	scene.free()
	print("%s Maciota frontage layout: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
