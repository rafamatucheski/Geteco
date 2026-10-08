extends SceneTree
## Directed road/land/legacy-save support in the actual edited Harbor geography.
## Real driving, fishing input and rendered landscaping belong to the session fixture.
const REGION := preload("res://world/editing/EditableRegion.gd")
const LOCATION := preload("res://runtime/FishingLocation.gd")
const LAYOUT := preload("res://world/places/fishing/FishingRuralLayout.gd")
const WOODLAND := preload("res://world/places/fishing/FishingWoodland.gd")
const SITE := preload("res://world/places/fishing/FishingSite.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var scene: Node3D
var region: Node3D
var site: Node3D
var actor: CharacterBody3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("FISHING_RELOCATION ","PASS " if ok else "FAIL ",label)

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Fishing relocation test timeout"); quit(3))
	var document := FileAccess.get_sha256("res://world/editing/world_edits.json")
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	region = REGION.new()
	region.region_id = "harbor"
	region.initial_prewarm_only = true
	scene.add_child(region)
	region.set_process(false)
	check(LOCATION.ANCHOR.distance_to(LOCATION.LEGACY_ANCHOR)>300,"lake moved over 300 metres away from its former site")
	check(region.extra_land.has(LAYOUT.outline()),"rural outline contributes real streamed land")
	var access: Array = region.roads.filter(func(road): return road.id==LAYOUT.ROAD_ID)
	check(access.size()==1,"edited region retains exactly one dirt access road")
	if access.is_empty(): quit(1); return
	check(access[0].surface=="earth" and not access[0].get("traffic",true),"dirt access is excluded from generated bus and truck traffic")
	var trunk: Array = region.roads.filter(func(road): return road.id=="vertice_rural_access")
	check(trunk.size()==1 and trunk[0].points.has(access[0].points[0]),"road joins the existing rural network at one authored endpoint")
	check(access[0].points[-1].distance_to(LOCATION.ENTRY)<.01,"road ends at the parking entrance before the pond")
	var trees := WOODLAND.tree_inventory()
	check(trees.size()>=180 and trees.size()<=220,"dense woodland has 180–220 native trees (actual %d)"%trees.size())
	check(trees==WOODLAND.tree_inventory(),"tree distribution stays deterministic across visits")
	var all_clear := true
	for tree in trees:
		var point := Vector2(tree.point.x,tree.point.z)
		all_clear = all_clear and LAYOUT.tree_available(point)
	check(all_clear,"every crown reserve clears shore parking road and outer land edge")
	var probes: Array[Vector3] = []
	for index in LOCATION.ROAD_POINTS.size()-1:
		var a: Vector2 = LOCATION.ROAD_POINTS[index]
		var b: Vector2 = LOCATION.ROAD_POINTS[index+1]
		var side := (b-a).normalized().orthogonal()
		for step in range(ceili(a.distance_to(b)/2)+1):
			var center := a.lerp(b,minf(1,float(step)*2/a.distance_to(b)))
			for lane in [-2.3,0,2.3]:
				var p: Vector2 = center+side*lane
				probes.append(Vector3(p.x,.10,p.y))
	for point in probes: region.prepare_collision_at(point)
	region.prepare_collision_at(LOCATION.LEGACY_ANCHOR)
	region.prepare_collision_at(LOCATION.ENTRY)
	site = SITE.new()
	scene.add_child(site)
	site.finish_build()
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	actor.position = LOCATION.ENTRY+Vector3.UP*.12
	scene.add_child(actor)
	actor.set_physics_process(false)
	for frame in 4: await physics_frame
	var floors := region.find_children("SerenoForestFloor","MeshInstance3D",true,false)
	var floors_valid := not floors.is_empty()
	for floor_mesh in floors:
		var faces: PackedVector3Array = floor_mesh.mesh.get_faces()
		floors_valid = floors_valid and floor_mesh.get_child_count()==1
		for index in range(0,faces.size(),3):
			floors_valid = floors_valid and is_zero_approx(faces[index].y) and (faces[index+1]-faces[index]).cross(faces[index+2]-faces[index]).y<0
	check(floors_valid,"woodland uses one upward-facing visual and collision mesh at native ground height")
	check(region.coastal_protection.on_land(Vector2(LOCATION.ANCHOR.x,LOCATION.ANCHOR.z)),"new lake land belongs to the coastal dry footprint")
	var tree_point: Vector3 = trees[0].point
	region.prepare_collision_at(tree_point)
	for frame in 3: await physics_frame
	var tree_ray := PhysicsRayQueryParameters3D.create(tree_point+Vector3(0,.9,-1.5),tree_point+Vector3(0,.9,1.5),1)
	var tree_hit := scene.get_world_3d().direct_space_state.intersect_ray(tree_ray)
	check(not tree_hit.is_empty() and tree_hit.collider.name=="WoodlandTrunks","native tree trunks block a pedestrian-height physical sweep")
	var supported := true
	var clear := true
	for point in probes:
		supported = supported and support(point)
		clear = clear and capsule_clear(point)
	check(supported,"both wheel paths and road centre retain support over every 2-metre sample and terrain seam")
	check(clear,"road width remains clear of all generated trunks and props")
	var legacy_ok := true
	for x in range(-210,-138,4):
		for z in range(-27,31,4):
			var point := Vector3(x,.10,z)
			region.prepare_collision_at(point)
			legacy_ok = legacy_ok and LOCATION.reserved(Vector2(x,z),.4)
	for frame in 3: await physics_frame
	for point in [LOCATION.LEGACY_ANCHOR,LOCATION.LEGACY_ANCHOR+Vector3(10,0,24),LOCATION.LEGACY_ANCHOR+Vector3(0,0,30)]:
		legacy_ok = legacy_ok and support(point+Vector3.UP*.1) and capsule_clear(point+Vector3.UP*.1)
	check(legacy_ok,"retired lake checkpoints keep flat support and remain free of trunks")
	for spot in site.fishing_spots():
		region.prepare_collision_at(spot.position)
	for frame in 3: await physics_frame
	check(site.fishing_spots().map(func(spot): return spot.id)==["sereno_0","sereno_1","sereno_2","sereno_3"],"all fishing station identifiers survive relocation")
	check(site.fishing_spots().all(func(spot): return support(spot.position) and capsule_clear(spot.position)),"all relocated fishing stations have support and full capsule clearance")
	# A real actor crosses the previously ocean/land join, using the actual floor.
	actor.teleport(Vector3(-426,.10,25.8))
	actor.speed = 3.5
	actor.set_physics_process(true)
	actor.automatic_direction = Vector3.LEFT
	for frame in 190: await physics_frame
	actor.automatic_direction = Vector3.ZERO
	check(actor.global_position.x< -435 and actor.global_position.y>-.05,"real actor crosses old/new terrain seam without a drop or hidden step")
	var before := trees
	region.release_chunks()
	region.prepare_collision_at(LOCATION.ENTRY)
	for frame in 3: await physics_frame
	check(WOODLAND.tree_inventory()==before,"unload and return preserve tree transforms")
	check(support(LOCATION.ENTRY+Vector3.UP*.1),"return recreates physical land at entrance")
	check(FileAccess.get_sha256("res://world/editing/world_edits.json")==document,"saved world-edit document preserved")
	print("FISHING_RELOCATION_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func support(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*.6,1,[actor.get_rid()])
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and absf(hit.position.y)<.15

func capsule_clear(point: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = .3
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.86)
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
