extends "res://tests/tank_control/test_heavy_impacts.gd"
## Production mountain geometry through the vehicle's swept impact path.
const REGION := preload("res://world/editing/EditableRegion.gd")
const APPROACH := preload("res://world/mountain_detail/MountainCaveApproach.gd")

func strike(item: Dictionary) -> void:
	var prop: Node3D = item.root.get_ref()
	var vehicle := car(1.0)
	vehicle.position = item.point + Vector3(0,0,6)
	await physics_frame
	check(vehicle.test_move(vehicle.global_transform,Vector3.FORWARD*10), "intact prop has a native collision")
	vehicle.position = item.point + Vector3(0,0,vehicle.half_length + item.radius - .01)
	street._hit_props(vehicle,Vector3.FORWARD*.1,Vector3.FORWARD*.01)
	check(item.state == "standing", "creeping vehicle leaves mountain prop intact")
	vehicle.position = item.point + Vector3(0,0,6)
	CRUSH.set_planar(vehicle,Vector3.FORWARD*42)
	var before := street.get_child_count()
	street._hit_props(vehicle,vehicle.horizontal_velocity,Vector3.FORWARD*10)
	check(item.state == "down", "high-speed sweep breaks mountain prop: " + item.kind)
	check(not prop.visible, "original prop is hidden after fracture")
	check(street.get_child_count() >= before+2, "fast impact creates separate fragments")
	for body in prop.find_children("*","CollisionObject3D",true,false):
		check(body.collision_layer == 0, "broken prop releases native collision")
	check(not vehicle.test_move(vehicle.global_transform,Vector3.FORWARD*10), "vehicle can cross the former obstacle")
	check(not FRAGILE.hit(item,42,Vector3.FORWARD,street), "repeated impact does not duplicate debris")
	vehicle.free()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	street = Street.new()
	world.add_child(street)
	var region := REGION.new()
	region.region_id = "mountain"
	for variant in 8:
		var chunk := Node3D.new()
		world.add_child(chunk)
		region._build_record(chunk,{"kind":"tree","variant":variant,"snow":true,"position":Vector3(0,3,0)})
		var items: Array = FRAGILE.query(Vector3(0,3,0),1)
		check(items.size() == 1, "snowy pine registered at its actual elevation")
		if items.size() == 1: await strike(items[0])
		chunk.free()
		check(FRAGILE.query(Vector3(0,3,0),1).is_empty(), "unloaded pine is removed from spatial query")
	for scale_factor in [.5,2.0]:
		var edited_chunk := Node3D.new()
		world.add_child(edited_chunk)
		region._build_record(edited_chunk,{"kind":"tree","variant":0,"snow":true,"position":Vector3(0,3,0),"editor_id":"test/pine","editor_scale":scale_factor,"editor_rotation":.7})
		var edited: Array = FRAGILE.query(Vector3(0,3,0),1)
		check(edited.size() == 1, "editor-authored pine participates in impacts")
		if edited.size() == 1:
			check(is_equal_approx(edited[0].radius,.4*scale_factor), "edited pine contact follows scale")
			await strike(edited[0])
		edited_chunk.free()
		FRAGILE.query(Vector3(0,3,0),1)
	var chunk := Node3D.new()
	world.add_child(chunk)
	region._build_record(chunk,{"kind":"mountain_road_lamp","position":Vector3.ZERO})
	region.mountain_night_level = 1.0
	region._apply_night_lights(chunk)
	var lamp: Node3D = chunk.get_child(0)
	var light := lamp.get_node("RoadNightLight")
	check(light.light_energy > 0, "intact mountain lamp lights at night")
	var lamps: Array = FRAGILE.query(Vector3.ZERO,1)
	check(lamps.size() == 1, "mountain road lamp registered")
	if lamps.size() == 1: await strike(lamps[0])
	for level in [0.0,0.5,1.0]:
		region.mountain_night_level = level
		region._apply_night_lights(chunk)
		check(light.light_energy == 0 and not light.visible, "night updates cannot relight destroyed lamp")
	chunk.free()
	FRAGILE.query(Vector3.ZERO,10)
	var approach := APPROACH.new()
	world.add_child(approach)
	var objects: Array = FRAGILE.query(Vector3.ZERO,10)
	check(objects.size() == 6, "three cave rocks and three pines registered")
	# Isolate each real object so neighboring rocks cannot shield the target.
	for item in objects:
		var prop: Node3D = item.root.get_ref()
		item.state = "standing"
		for body in prop.find_children("*","CollisionObject3D",true,false): body.collision_layer = 1
		for other in objects:
			if other == item: continue
			other.state = "down"
			var sibling: Node3D = other.root.get_ref()
			for body in sibling.find_children("*","CollisionObject3D",true,false): body.collision_layer = 0
		if item.kind == "desert_rock": check(item.radius > 1.1, "large cave rock uses its own collision footprint")
		await strike(item)
	approach.free()
	check(FRAGILE.query(Vector3.ZERO,10).is_empty(), "cave chunk unload leaves no candidates")
	region.free()
	await create_timer(.5).timeout
	world.free()
	await process_frame
	print("MOUNTAIN_BREAKABLES checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
