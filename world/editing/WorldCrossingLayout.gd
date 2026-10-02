@tool
extends RefCounted
## One derived layout for the road mesh, editor handles and vehicle stop targets.
## Overrides live on roads; identities use road IDs and order, not world coordinates.
static func build(geometry) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var groups := {}
	for junction in geometry._junctions:
		var arms: Array[Dictionary] = geometry._crossing_arms(junction)
		if arms.size() < 3: continue
		var ids: Array[String] = []
		for index in junction.roads: ids.append(str(geometry._roads[index].id))
		ids.sort()
		var signature := JSON.stringify(ids)
		if not groups.has(signature): groups[signature] = []
		groups[signature].append({"source":junction,"arms":arms,"ids":ids})
	for signature in groups:
		var siblings: Array = groups[signature]
		var local_reference: PackedVector2Array
		for road in geometry._roads:
			if road.id == siblings[0].ids[0]: local_reference = road.points; break
		siblings.sort_custom(func(a,b): return offset_on(local_reference,a.source.position)<offset_on(local_reference,b.source.position))
		for ordinal in siblings.size():
			var item: Dictionary = siblings[ordinal]
			var center: Vector2 = item.source.position
			var id := str(signature)+"#"+str(ordinal)
			var widest := 0.0
			for arm in item.arms: widest = maxf(widest,float(arm.width))
			var setback := maxf(1.5,widest*.68+.375)
			var entries: Array[Dictionary] = []
			for arm in item.arms:
				var road: Dictionary = arm.road
				var key := id+":"+str(arm.side)
				var setting: Dictionary = road.get("crossing_entries",{}).get(key,{})
				var mode := str(setting.get("mode","auto"))
				var automatic: bool = road.crossings and not geometry._is_unsignalized(center)
				var enabled: bool = mode == "on" or (mode == "auto" and automatic)
				var show_stop := bool(setting.get("stop",automatic or mode == "on"))
				var depth := float(setting.get("depth",road.crossing_depth))
				var offset := float(setting.get("offset",road.crossing_offset))
				var direction: Vector2 = arm.direction
				var maximum := minf(setback+10.0,float(arm.length)-depth*.5-1.25)
				# Leave room for the opposite approach of the next junction as well.
				for other in geometry._junctions:
					var delta: Vector2 = other.position-center
					var forward := delta.dot(direction)
					if forward > .1 and absf(delta.cross(direction)) < .08:
						maximum = minf(maximum,forward*.5-depth*.5-1.25)
				var fits := maximum >= setback
				var distance := clampf(setback+offset,setback,maxf(setback,maximum))
				var position := center+direction*distance
				var stop := position+direction*(depth*.5+1.0)
				entries.append({"key":key,"road_id":str(road.id),"direction":direction,"position":position,"stop_position":stop,"depth":depth,"width":float(arm.width),"sidewalk":float(road.sidewalk_width),"offset":distance-setback,"max_offset":maxf(0,maximum-setback),"mode":mode,"enabled":enabled and fits,"stop_line":show_stop and fits,"show_stop":show_stop,"fits":fits,"reason":"" if fits else "Sem espaço antes da curva ou do próximo cruzamento.","junction":center})
			result.append({"id":id,"position":center,"entries":entries})
	# A crossing cannot occupy another crossing at a nearby/acute junction.
	result.sort_custom(func(a,b): return a.id < b.id)
	var occupied: Array[PackedVector2Array] = []
	for junction in result:
		for entry in junction.entries:
			if not entry.enabled: continue
			var polygon: PackedVector2Array = geometry._quad(entry.position,entry.direction,entry.depth+2.0,entry.width)
			for other in occupied:
				if not Geometry2D.intersect_polygons(polygon,other).is_empty():
					entry.enabled = false
					entry.reason = "Faixa omitida para evitar sobreposição."
					break
			if entry.enabled: occupied.append(polygon)
	return result

static func offset_on(points: PackedVector2Array, at: Vector2) -> float:
	var best := INF
	var offset := 0.0
	var distance := 0.0
	for i in range(points.size()-1):
		var projected := Geometry2D.get_closest_point_to_segment(at,points[i],points[i+1])
		var gap := projected.distance_squared_to(at)
		if gap < best:
			best = gap
			offset = distance+points[i].distance_to(projected)
		distance += points[i].distance_to(points[i+1])
	return offset
