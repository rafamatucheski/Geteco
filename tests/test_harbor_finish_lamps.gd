extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var scene := load("res://district/harbor_preview/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		await physics_frame
	var known := {}
	var count := 0
	var roads: Array = scene.get_node("RoadNetwork").get_graph_data().roads
	for id in ["District","EastDistrict","NorthDistrict"]:
		var district := scene.get_node(id)
		var land: Rect2 = {"District":Rect2(-100,-100,3300,2580),"EastDistrict":Rect2(4380,-100,2380,2700),"NorthDistrict":Rect2(4380,-2400,2380,2300)}[id]
		var local_count := 0
		for lamp in district.get_children():
			if not lamp is StreetLamp:
				continue
			local_count += 1
			count += 1
			check(not known.has(lamp.global_position),"No duplicate lamp at %s" % lamp.global_position)
			known[lamp.global_position] = true
			check(land.has_point(lamp.global_position),"Lamp is geographically inside its owning provider")
			for site in district.sites:
				check(not site.bounds.grow(6).has_point(lamp.position),"Lamp outside building "+site.id)
			for access in district.accesses:
				check(not access.bounds.grow(5).has_point(lamp.position),"Lamp does not block access "+access.id)
			for road in roads:
				var points: PackedVector2Array = road.points
				for j in range(points.size()-1):
					check(Geometry2D.get_closest_point_to_segment(lamp.global_position,points[j],points[j+1]).distance_to(lamp.global_position)>float(road.width)*0.5+5,"Lamp stays outside asphalt")
			var query := PhysicsShapeQueryParameters2D.new()
			var shape := CircleShape2D.new()
			shape.radius = 5
			query.shape = shape
			query.transform = Transform2D(0,lamp.global_position)
			query.collision_mask = 1
			query.exclude = [lamp.get_rid()]
			check(scene.get_world_2d().direct_space_state.intersect_shape(query).is_empty(),"Lamp does not overlap another physical solid")
			check(scene.weather.time_changed.is_connected(lamp.set_lit),"Lamp bound to production weather")
			scene.weather.time_changed.emit(true)
			check(lamp.is_lit,"Night signal illuminates lamp")
			scene.weather.time_changed.emit(false)
			check(not lamp.is_lit,"Day signal extinguishes lamp")
		check(local_count==(5 if id=="District" else 6),"Provider owns its own local posts")
	print("HARBOR FINISH LAMPS: lamps=%d failures=%d" % [count,failures])
	scene.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
