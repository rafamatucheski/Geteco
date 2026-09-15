extends SceneTree
const LAYOUT = preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd")
const POCKET = preload("res://world/mountain_pass/MountainVillageLayout.gd")
var failures := 0
class StreamFixture extends Node:
	var mountain: Node2D
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func query(world: Node2D, point: Vector2, shape: Shape2D, angle := 0.0) -> Array[Dictionary]:
	var request := PhysicsShapeQueryParameters2D.new()
	request.shape = shape
	request.transform = Transform2D(angle,point)
	request.collision_mask = 1
	return world.get_world_2d().direct_space_state.intersect_shape(request,32)
func has_native_mesh(model:Node)->bool:
	if model is MeshInstance3D:return true
	for child in model.get_children():
		if has_native_mesh(child):return true
	return false
func run() -> void:
	var production := OS.get_cmdline_user_args().has("--production")
	var audit_dressing:=OS.get_cmdline_user_args().has("--dressing")
	var audit_mouths:=OS.get_cmdline_user_args().has("--mouths")
	var world: Node2D
	var road: Node2D
	var shelter: Node2D
	var coach_access: Path2D
	if production:
		root.get_node("SaveManager").clear_pending_save()
		world=load("res://world/mountain_pass/MountainPass.tscn").instantiate()
		world.connect_to_harbor=false
		world.spawn_player_on_ready=false
		world.spawn_suv_on_ready=false
		root.add_child(world)
		while not world.region_ready:await process_frame
		road=world.get_node("MountainPassRoad")
		shelter=world.get_node("MountainSettlement/WinterShelter1")
		var service:=preload("res://world/shared/transit/HarborMountainCoachService.gd").new()
		service.set_process(false)
		var stream:=StreamFixture.new()
		stream.mountain=world
		world.add_child(stream)
		world.add_child(service)
		service.stream=stream
		service.mountain_lane=world.get_node("MountainTraffic").lane
		service._build_access()
		coach_access=service.access_lane
	else:
		world=Node2D.new()
		root.add_child(world)
		var village:=preload("res://world/mountain_pass/transit/MountainTransitVillage.gd").new()
		world.add_child(village)
		road=preload("res://world/mountain_pass/MountainPassRoad.gd").new()
		world.add_child(road)
		var overlook:=Area2D.new()
		world.add_child(overlook)
		preload("res://world/mountain_pass/MountainSceneryBuilder.gd").build_detailed_overlook(overlook)
		shelter=preload("res://world/mountain_pass/MountainProp.gd").new()
		shelter.model_script=preload("res://world/mountain_pass/art/winter_props/PatrolShelter3D.gd")
		shelter.position=POCKET.POCKETS[1]+Vector2(0,-15)
		world.add_child(shelter)
		preload("res://world/mountain_pass/transit/MountainBenchGeometry.gd").install_prop(shelter,"PatrolShelter3D")
	await physics_frame
	await physics_frame
	var walker := CircleShape2D.new()
	walker.radius = 9.0
	var routes: Array = [LAYOUT.BUS_TO_PLAZA,LAYOUT.PLAZA_TO_SHOP,LAYOUT.PLAZA_TO_WAIT]
	for index in 4: routes.append(LAYOUT.cabin_route(index))
	for point in LAYOUT.BENCH_CENTERS:
		for side in [-8.0,8.0]: routes.append(LAYOUT.bench_access_route(point+Vector2(side,0)))
	var dressing_counts:Dictionary={}
	if audit_dressing:
		var props:=get_nodes_in_group("mountain_dressing")
		check(not props.is_empty(),"Production includes the new native winter dressing")
		for prop in props:
			var kind:=String(prop.get_meta("dressing_kind",""))
			dressing_counts[kind]=int(dressing_counts.get(kind,0))+1
			var model:Node=prop.get_meta("dressing_model",null)
			check(is_instance_valid(model) and model is Node3D and has_native_mesh(model),"Dressing has real 3D mesh: %s"%prop.name)
			var footprint:PackedVector2Array=prop.get_meta("dressing_polygon",PackedVector2Array())
			check(footprint.size()>=3 and prop.has_meta("geometry_contract"),"Dressing declares its projected footprint: %s"%prop.name)
			var walkable:=bool(prop.get_meta("walkable",false))
			check(prop is StaticBody2D and (prop.collision_layer==0 if walkable else (prop.collision_layer&1)!=0),"Dressing physics matches declared walkability: %s"%prop.name)
			if walkable:
				var polygon:=PackedVector2Array()
				for point in footprint:polygon.append(prop.to_global(point))
				for route in routes:
					for ribbon in Geometry2D.offset_polyline(PackedVector2Array(route),9.0,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND):
						check(Geometry2D.intersect_polygons(polygon,ribbon).is_empty(),"Walkable branches remain outside pedestrian corridors: %s"%prop.name)
		for kind in ["pine","rock","log","branches"]:check(int(dressing_counts.get(kind,0))>0,"Winter scene includes %s"%kind)
	var blocked := []
	var walker_body := CharacterBody2D.new()
	walker_body.collision_layer = 0
	walker_body.collision_mask = 3
	world.add_child(walker_body)
	var navigation := preload("res://ResponderNavigation.gd").new()
	for route_index in routes.size():
		var route: Array = Array(routes[route_index])
		for segment in range(route.size()-1):
			var a: Vector2 = route[segment]
			var b: Vector2 = route[segment+1]
			check(navigation.clear_segment(walker_body,a,b),"Navigation segment must clear all three rays: route %d segment %d" % [route_index,segment])
			for step in range(101):
				var point := a.lerp(b,float(step)/100.0)
				for hit in query(world,point,walker):
					blocked.append({"route":route_index,"point":point,"body":str(hit.collider.name)})
	check(blocked.is_empty(),"Public paths blocked at 9px navigation clearance: %s" % str(blocked.slice(0,8)))
	for index in 4:
		var point: Vector2 = LAYOUT.CABIN_CENTERS[index]+Vector2(0,-62)
		check(not query(world,point,walker).is_empty(),"Chalet roof silhouette must block actors above its floor footprint")
	var vehicle := RectangleShape2D.new()
	vehicle.size = Vector2(120,34)
	check(query(world,LAYOUT.BERTH,vehicle).is_empty(),"Coach berth must clear all projected terminal geometry")
	var coach_blocks:=[]
	if coach_access!=null:
		var hull:=CharacterBody2D.new()
		hull.collision_layer=0
		hull.collision_mask=1
		var collision:=CollisionShape2D.new()
		collision.shape=vehicle
		hull.add_child(collision)
		world.add_child(hull)
		await physics_frame
		await physics_frame
		for offset in range(0,int(coach_access.curve.get_baked_length())-2,2):
			var pose:=coach_access.global_transform*coach_access.curve.sample_baked_with_rotation(float(offset),true)
			var next:=coach_access.to_global(coach_access.curve.sample_baked(float(offset+2),true))
			var collision_result:=KinematicCollision2D.new()
			if hull.test_move(pose,next-pose.origin,collision_result):
				coach_blocks.append({"offset":offset,"body":str(collision_result.get_collider().get_path())})
		check(coach_blocks.is_empty(),"Dressing must clear the translating coach hull along its actual route: %s" % str(coach_blocks.slice(0,8)))
	vehicle.size = Vector2(90,37)
	check(query(world,POCKET.PARKING[1][0],vehicle).is_empty(),"Parked SUV must clear projected shelter and rails")
	check(not query(world,shelter.global_position+Vector2(0,-37),vehicle).is_empty(),"Vehicles cannot overlap the visible shelter roof")
	var access: Curve2D = POCKET.winter_stop_access_curve(road.curve,1)
	var access_blocks := []
	for offset in range(0,int(access.get_baked_length()),4):
		var frame := access.sample_baked_with_rotation(float(offset),true)
		for hit in query(world,frame.origin,vehicle,frame.get_rotation()):
			access_blocks.append({"offset":offset,"body":str(hit.collider.name)})
	check(access_blocks.is_empty(),"Parking access blocks car hull: %s" % str(access_blocks.slice(0,8)))
	var mouths:Dictionary={}
	if audit_mouths:
		var opening_labels:Array[String]=[]
		var rail_sections:Array=road._guard_rail_sections()
		check(not rail_sections.is_empty() and road.guard_rails.get_child_count()>0,"Defensas remain physically present outside access mouths")
		for mouth in road.junctions.mouths:
			opening_labels.append(String(mouth.label))
			check(not Geometry2D.triangulate_polygon(mouth.polygon).is_empty(),"Access mouth surface triangulates: %s"%mouth.label)
			for section in rail_sections:
				check(Geometry2D.intersect_polyline_with_polygon(section,mouth.polygon).is_empty(),"Visible guardrail section cannot cross an open mouth: %s"%mouth.label)
		for label in ["winter_pocket","coach_entry","coach_exit"]:check(opening_labels.has(label),"Road registers matching visual and physical mouth: %s"%label)
		var sweep:=preload("res://tests/MountainAccessMouthAudit.gd")
		mouths["pocket1_car"]=await sweep.sweep(world,access,road.global_transform,62.0,Vector2(90,37),0.0,access.get_baked_length())
		check(coach_access!=null,"Regional mouth audit requires the production coach route")
		if coach_access!=null:
			var length:=coach_access.curve.get_baked_length()
			for size in [Vector2(90,37),Vector2(120,34)]:
				var type:="coach" if size.x>100 else "car"
				mouths["regional_entry_"+type]=await sweep.sweep(world,coach_access.curve,coach_access.global_transform,88.0,size,0.0,280.0)
				mouths["regional_exit_"+type]=await sweep.sweep(world,coach_access.curve,coach_access.global_transform,88.0,size,length-280.0,length)
		for name in mouths:check(int(mouths[name].blocked)==0,"Entire usable access width must remain clear: %s %s"%[name,str(mouths[name])])
	print("MOUNTAIN_GEODATA production=",production," failures=",failures," routes=",routes.size()," blocked_samples=",blocked.size()," access_blocks=",access_blocks.size()," coach_blocks=",coach_blocks.size()," dressing=",dressing_counts)
	if audit_mouths:print("MOUNTAIN_ACCESS_MOUTHS ",mouths)
	world.queue_free()
	for frame in 4:await process_frame
	quit(0 if failures==0 else 1)
