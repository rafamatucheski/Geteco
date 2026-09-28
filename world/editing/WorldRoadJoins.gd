extends RefCounted
## Resolve small endpoint gaps inside another street's asphalt before both
## rendering and traffic consume the edited roads. Never changes the saved map.
static func resolve(source: Array) -> Array:
	var result := source.duplicate(true)
	for pass_index in 2:
		var previous := result.duplicate(true)
		for road_index in previous.size():
			var road: Dictionary = previous[road_index]
			if float(road.width)<5 and not _one_way(road): continue
			var points: PackedVector3Array = road.points
			if points.size()<2: continue
			for endpoint in [0,points.size()-1]:
				var at := points[endpoint]
				var neighbour := points[1 if endpoint==0 else points.size()-2]
				var forward := at.direction_to(neighbour)
				var best := INF
				var chosen := at
				for target_index in previous.size():
					if target_index==road_index: continue
					var target: Dictionary = previous[target_index]
					if float(target.width)<5 and not _one_way(target): continue
					var target_points: PackedVector3Array = target.points
					var radius := minf(3.0,float(target.width)*.5)
					for segment in range(target_points.size()-1):
						var a := target_points[segment]
						var b := target_points[segment+1]
						if a.distance_to(b)<.1: continue
						var closest := Geometry3D.get_closest_point_to_segment(at,a,b)
						if absf(closest.y-at.y)>.25: continue
						var parallel := absf(forward.dot(a.direction_to(b)))>.85
						var target_endpoint := -1
						if parallel and at.distance_to(closest)>.1:
							# Parallel lanes are not junctions. Only end-to-end continuations.
							var first := target_points[0]
							var last := target_points[-1]
							closest = first if at.distance_to(first)<at.distance_to(last) else last
							if at.distance_to(closest)>.04 and absf(forward.dot(at.direction_to(closest)))<.85: continue
							target_endpoint = 0 if closest==first else target_points.size()-1
						elif closest.distance_to(target_points[0])<.04: target_endpoint=0
						elif closest.distance_to(target_points[-1])<.04: target_endpoint=target_points.size()-1
						if absf(closest.y-at.y)>.25: continue
						var distance := at.distance_to(closest)
						if distance>radius or distance>=best or closest.distance_to(neighbour)<.25: continue
						# Stable owner prevents two endpoints swapping places every pass.
						if target_endpoint>=0 and str(road.id)+"/"+str(endpoint)<str(target.id)+"/"+str(target_endpoint): closest=at
						best=distance
						chosen=closest
				var updated: PackedVector3Array = result[road_index].points
				updated[endpoint]=chosen
				result[road_index].points=updated
	return result

static func _one_way(road: Dictionary) -> bool:
	return str(road.id).contains("inbound") or str(road.id).contains("outbound")
