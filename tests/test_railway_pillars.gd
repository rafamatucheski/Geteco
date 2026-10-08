extends SceneTree

const RAILWAY := preload("res://world/railway/RailwayWorld.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")

class Controller extends RefCounted:
	var regions: Dictionary = {}
	var _region_cache: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var failures := 0
	for initial_region in ["harbor", "mountain", "desert"]:
		failures += await check_start_region(initial_region)
	quit(1 if failures > 0 else 0)

func check_start_region(initial_region: String) -> int:
	var controller := Controller.new()
	var prepared: Dictionary = {}
	for id in ["harbor", "mountain", "desert"]:
		var region = REGION.build_region(id)
		region.prepare_data()
		prepared[id] = region
	controller.regions[initial_region] = prepared[initial_region]
	var railway := RAILWAY.new()
	railway.configure(controller)
	var initial_count: int = railway._source_roads.size()
	# Exercise columns streamed before neighbouring data becomes available.
	for key in railway._descriptors: railway._build_chunk(key)
	var harbor_exposed := 0
	var harbor_points: Array[Vector3] = []
	for descriptors in railway._descriptors.values():
		for segment in descriptors:
			if not segment.pillar: continue
			var point: Vector3 = (segment.a + segment.b) * .5
			if not railway._pillar_clear(point): continue
			for road in prepared.harbor.roads:
				for i in range(1, road.points.size()):
					var a: Vector3 = road.points[i-1]
					var b: Vector3 = road.points[i]
					var flat := Vector2(point.x,point.z)
					if Geometry2D.get_closest_point_to_segment(flat,Vector2(a.x,a.z),Vector2(b.x,b.z)).distance_to(flat) < float(road.width)*.5+.85:
						harbor_exposed += 1
						var floor_point := Vector3(point.x,1,point.z)
						if floor_point not in harbor_points: harbor_points.append(floor_point)
						print("HARBOR_BEFORE_REGION_AVAILABLE start=",initial_region," point=",point," road=",road.id)
	for id in prepared:
		if id != initial_region: controller._region_cache[id] = prepared[id]
	var failures := 0
	var checked := 0
	for descriptors in railway._descriptors.values():
		for segment in descriptors:
			if not segment.pillar: continue
			var point: Vector3 = (segment.a + segment.b) * .5
			for region in prepared.values():
				var roads: Array = region.roads.duplicate()
				if region.get("walkways") is Array: roads.append_array(region.walkways)
				for road in roads:
					for index in range(1,road.points.size()):
						var a: Vector3 = road.points[index-1]
						var b: Vector3 = road.points[index]
						var flat := Vector2(point.x,point.z)
						var nearest := Geometry2D.get_closest_point_to_segment(flat,Vector2(a.x,a.z),Vector2(b.x,b.z))
						if nearest.distance_to(flat) >= float(road.width)*.5 + .85: continue
						checked += 1
						if railway._pillar_clear(point):
							failures += 1
							print("PILLAR_FAIL ",point," road=",road.get("id","")," region=",region.region_id)
	if railway.has_method("_recheck_supports"):
		railway._recheck_supports()
		railway.controller = null
		root.add_child(railway)
		railway.set_process(false)
		await physics_frame
		await physics_frame
		var physics_points: Array = [Vector3(730,1,-333),Vector3(307.9028,1,-751.8972),Vector3(296.8972,1,-762.9028),Vector3(-72,1,-875.125)]
		physics_points.append_array(harbor_points)
		for point in physics_points:
			var box := BoxShape3D.new()
			box.size = Vector3(2,1.8,4.8)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = box
			query.transform = Transform3D(Basis.IDENTITY,point)
			query.collision_mask = 1
			var hits := railway.get_world_3d().direct_space_state.intersect_shape(query)
			checked += 1
			if not hits.is_empty():
				failures += 1
				print("PILLAR_PHYSICS_FAIL ",point)
	print("PILLAR_RESULT start=",initial_region," checks=",checked," failures=",failures," harbor_exposed_before=",harbor_exposed," initial_roads=",initial_count," final_roads=",railway._source_roads.size())
	railway.free()
	for region in prepared.values(): region.free()
	return failures + (1 if checked == 0 else 0)
