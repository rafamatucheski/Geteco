extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	for angle in [0.0,PI,PI*0.5,-PI*0.5]:
		var station := preload("res://world/harbor/urban_transit/UrbanTubeStop.gd").new()
		station.position = Vector2(540,420)
		station.rotation = angle
		station.terminal = true
		root.add_child(station)
		for sign in [-1.0, 1.0]:
			var outward: Vector2 = Vector2.RIGHT.rotated(angle) * sign
			var original := station.to_global(Vector2(20, 24))
			var cleared: Vector2 = station.clear_signal_position(original, outward)
			var local_cleared: Vector2 = station.to_local(cleared)
			check(local_cleared.x > 255 if sign > 0 else local_cleared.x < -235,"signal clears canopy and access at angle %s" % angle)
			check(absf(local_cleared.y - 24) < 0.01,"signal stays on the same sidewalk")
			check((cleared-original).dot(outward)>0,"signal moves away from the junction")
			check(station.clear_signal_position(cleared,outward).distance_to(cleared)<0.01,"signal clearance is stable on rebuild")
		var junction := preload("res://world/shared/roads/traffic/JunctionSignalVisual2D.gd").new()
		var tangent := Vector2.RIGHT.rotated(angle)
		junction.configure(&"station_clearance",48,[{"road_index":0,"entry_tangent":tangent,"road_width":100}])
		junction.position = station.to_global(Vector2(20,24)) - junction.get_signal_layout()[0].pole_base
		root.add_child(junction)
		var post_position: Vector2 = junction.signal_posts[0].global_position
		check(station.to_local(post_position).x < -235,"production junction places pole beyond station")
		junction._rebuild_posts()
		check(junction.signal_posts[0].global_position.distance_to(post_position)<0.01,"junction rebuild preserves clear foundation")
		junction.free()
		for point in [Vector2(-145,-102),Vector2(7,-58),Vector2(100,-4),Vector2(151,7),Vector2(-146,-29)]:
			var displayed: Vector2 = station.view.to_global(station.view.project_point(station.view.model.floor_point(point)))
			check(displayed.distance_to(station.to_global(point))<0.1,"ground/model alignment at angle %s point %s"%[angle,point])
		check(station.find_children("*","Label",true,false).is_empty(),"no floating station labels")
		var before: Color = station.view.model.service_material.albedo_color
		station.refresh(false,0)
		check(station.view.model.service_material.albedo_color != before,"closure changes the physical indicator")
		for mesh in station.view.model.get_children():
			var bounds: AABB = mesh.get_aabb()
			for i in 8:
				var screen: Vector2 = station.view.camera_3d.unproject_position(bounds.get_endpoint(i))
				check(Rect2(Vector2.ZERO,Vector2(station.view.viewport_3d.size)).has_point(screen),"native geometry fits texture at angle %s"%angle)
		station.free()
	print("URBAN_STATION_3D failures=",failures)
	quit(0 if failures.is_empty() else 1)
