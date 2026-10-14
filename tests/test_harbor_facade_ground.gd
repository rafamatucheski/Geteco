extends SceneTree
## Access floors retain real support while their underlying city finish is cut.
const REGION = preload("res://world/regions/NativeRegion.gd")
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("FACADE_GROUND ", "PASS " if value else "FAIL ", label)

func base_visible_at(region: Node3D, point: Vector3) -> bool:
	for node in region.find_children("*", "MeshInstance3D", true, false):
		if not node.is_visible_in_tree() or node.mesh == null: continue
		if not (str(node.name).begins_with("HarborSurface_") or str(node.name).begins_with("Land")): continue
		var faces: PackedVector3Array = node.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var a: Vector3 = node.global_transform * faces[index]
			var b: Vector3 = node.global_transform * faces[index+1]
			var c: Vector3 = node.global_transform * faces[index+2]
			if (b-a).cross(c-a).y >= 0: continue
			if Geometry2D.point_is_inside_triangle(Vector2(point.x,point.z),Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)): return true
	return false

func run() -> void:
	var samples: Array[Dictionary] = []
	for definition in CATALOG.definitions():
		if definition.id in ["westgate_garden","quayside_house","canal_north"]:
			var parking := preload("res://world/places/ResidenceParking.gd").placement(int(definition.variant))
			samples.append({"name":str(definition.id)+" parking", "point":definition.exterior_position+parking+Vector3(7.5,0,.5), "y":.01})
			samples.append({"name":str(definition.id)+" access strip", "point":definition.exterior_position+Vector3(0,0,2.5), "y":.005})
		elif definition.id == "harbor_hospital":
			for row in [[Vector2(80,40),.09],[Vector2(121,-6.5),.07],[Vector2(121,95.5),.07],[Vector2(134,40),.07]]:
				var at: Vector2 = row[0]/Vector2(18,18*.76822128)
				samples.append({"name":"hospital apron "+str(row[0]), "point":definition.exterior_position+Vector3(at.x,0,at.y), "y":row[1]})
	var region = REGION.build_region("harbor",Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	for sample in samples:
		var at: Vector3 = sample.point
		region._ensure_chunk(Vector2i(floori(at.x/REGION.CELL),floori(at.z/REGION.CELL)))
	await physics_frame
	await physics_frame
	for sample in samples:
		var point: Vector3 = sample.point
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.7,point-Vector3.UP,1)
		var hit := region.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y-float(sample.y)) < .012, sample.name+" physical floor preserved")
		check(not base_visible_at(region,point),sample.name+" has no city finish below it")
	var hospital: Dictionary = CATALOG.get_definition("harbor_hospital")
	for route in [{"offset":Vector3(8.35,.15,2.9),"direction":Vector3.LEFT,"height":.09}, {"offset":Vector3(6.7,.15,9.7),"direction":Vector3.FORWARD,"height":.07}]:
		var actor = preload("res://scripts/Actor.gd").new()
		actor.controlled_automatically = true
		actor.position = hospital.exterior_position + route.offset
		actor.speed = 1.5
		root.add_child(actor)
		for frame in 20: await physics_frame
		var start: Vector3 = actor.position
		actor.automatic_direction = route.direction
		for frame in 100: await physics_frame
		check(actor.position.distance_to(start)>1.8,"real pedestrian traverses hospital apron edge "+str(route.direction))
		check(absf(actor.position.y-float(route.height))<.02,"real pedestrian feet meet apron "+str(route.height))
		actor.free()
	print("FACADE_GROUND_RESULT checks=",checks," failures=",failures)
	region.free()
	quit(1 if failures else 0)
