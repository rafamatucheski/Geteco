extends "res://tests/tank_control/test_heavy_impacts.gd"
func run() -> void:
	world = Node3D.new(); root.add_child(world)
	street = Street.new(); world.add_child(street)
	solid(Vector3(1000,.2,1000),Vector3(0,-.1,0))
	for kind in ["harbor","public","cobra","terminal","cemetery","village"]:
		FRAGILE.cells.clear()
		var prop: Node3D
		match kind:
			"harbor":
				prop = preload("res://world/urban_detail/HarborProp3D.gd").new()
				prop.configure({"kind":"bench","source_id":"test"})
			"public":
				prop = preload("res://world/urban_detail/HarborPublicRealm3D.gd").new(); prop.zone_id = "foundry_courtyard"
			"cobra":
				prop = preload("res://world/urban_detail/HarborAreaDressing3D.gd").new(); prop.configure("cobra")
			"terminal": prop = preload("res://world/urban_detail/HarborTerminalModel3D.gd").new()
			"cemetery": prop = preload("res://world/regions/OriginalCemetery3D.gd").new()
			"village": prop = preload("res://world/mountain_detail/OriginalVillageArchitecture.gd").new()
		prop.position = Vector3(40,0,40)
		world.add_child(prop)
		await physics_frame
		if kind in ["cobra","public"]:
			for loose_kind in (["barrel"] if kind == "cobra" else ["dumpster","pallet"]):
				var loose: Array = []
				for rows in FRAGILE.cells.values():
					for item in rows:
						if item.kind == loose_kind: loose.append(item)
				check(not loose.is_empty(),kind+": loose "+loose_kind+" registered")
				if not loose.is_empty(): check(FRAGILE.hit(loose[0],12,Vector3.FORWARD,street),kind+": loose "+loose_kind+" yields")
				for body in street.find_children("*","RigidBody3D",true,false): body.free()
		var benches: Array = []
		for rows in FRAGILE.cells.values():
			for item in rows:
				if item.kind == "bench_seat": benches.append(item)
		check(not benches.is_empty(),kind+": authored benches registered")
		if not benches.is_empty():
			var item: Dictionary = benches[0]
			var point: Vector3 = item.point
			var vehicle := car(1200,Vector3(2,1.4,4),point+Vector3(0,.04,3.8))
			if kind == "harbor": vehicle.position.x += 2.8 # actual outer end of the wide bench
			await physics_frame
			if kind == "village":
				# Station benches sit behind structural solids: test their ownership
				# directly; the road-facing banks exercise the real car sweep.
				FRAGILE.hit(item,12,Vector3.FORWARD,street)
			else: street._hit_props(vehicle,Vector3(0,0,-12),Vector3(0,0,-3))
			check(item.state == "down",kind+": impact breaks bench")
			if item.state == "down":
				check(not item.root.get_ref().visible,kind+": intact bench removed")
				for body in item.root.get_ref().find_children("*","CollisionObject3D",true,false): check(body.collision_layer == 0,kind+": bench collider removed")
				for reference in item.get("colliders",[]): check(reference.get_ref().disabled,kind+": only owned shared shapes disabled")
				var fragments: Array = street.find_children("*","RigidBody3D",true,false)
				check(not fragments.is_empty(),kind+": physical fragments created")
				for fragment in fragments:
					for mesh in fragment.find_children("*","MeshInstance3D",true,false):
						var center: Vector3 = mesh.global_transform*mesh.get_aabb().get_center()
						check(center.distance_to(point)<6,kind+": fragments stay at impact instead of double offset")
			vehicle.free()
		prop.free()
		for body in street.find_children("*","RigidBody3D",true,false): body.free()
	FRAGILE.cells.clear()
	# Compound batches must release only the planter struck by the car.
	var chunk := Node3D.new(); world.add_child(chunk)
	var transform := Transform3D(Basis.IDENTITY,Vector3(20,0,20))
	preload("res://world/city_look/CityChunkDressing.gd")._flush(chunk,{"planter":[transform,Transform3D(Basis.IDENTITY,Vector3(25,0,20))],"dumpster":[Transform3D(Basis.IDENTITY,Vector3(20,0,28))],"trash_bags":[Transform3D(Basis.IDENTITY,Vector3(20,0,32))]})
	for kind in ["planter","dumpster","trash_bags"]:
		var items: Array = FRAGILE.query(Vector3(20,0,20),20).filter(func(item): return item.kind == kind)
		items.sort_custom(func(a,b): return a.index < b.index)
		check(not items.is_empty(),kind+": registered city batch")
		if not items.is_empty(): check(FRAGILE.hit(items[0],12,Vector3.FORWARD,street),kind+": yields to car impact")
	check(chunk.get_node("CityPlanterSolids").get_child(0).disabled and not chunk.get_node("CityPlanterSolids").get_child(1).disabled,"planter break preserves neighbouring solid")
	world.free()
	print("VEHICLE_BREAKABLE_FURNITURE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
