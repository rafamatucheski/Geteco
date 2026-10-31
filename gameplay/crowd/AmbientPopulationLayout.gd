extends RefCounted
## Cached street-length samples. A bounded candidate search favours unoccupied
## stretches without creating additional per-frame agents or raising population.
var slots: Array[Dictionary] = []

func configure(roads: Array) -> void:
	slots.clear()
	for road in roads:
		if road.get("surface","")=="tunnel": continue
		for i in range(road.points.size()-1):
			var a: Vector3 = road.points[i]
			var b: Vector3 = road.points[i+1]
			var length := a.distance_to(b)
			if length<4: continue
			var count := maxi(1,ceili(length/22.0))
			for n in count:
				slots.append({"a":a,"b":b,"point":a.lerp(b,(n+.5)/count),"width":road.width,"road":road})
	# O grafo de trânsito é mais estreito que a pista definida da ponte.
	# Amostra as calçadas reais dela em vez de deslocar uma faixa de veículos.
	slots.append_array(preload("res://world/regions/unified_bridge/BridgeWalkSafety.gd").population_slots())

func select(production, vehicle := false) -> Dictionary:
	if slots.is_empty(): return {}
	var best := {}
	var best_score := INF
	var start := randi_range(0,slots.size()-1)
	# Random strides sample long streets as well as short, densely subdivided ones.
	for attempt in mini(slots.size(),32):
		var index := posmod(start+int(float(attempt)*slots.size()/mini(slots.size(),32)),slots.size())
		var slot: Dictionary = slots[index]
		if vehicle and slot.get("bridge_walk",false): continue
		if not vehicle and not slot.get("bridge_walk",false) and preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd").owns_east_point(Vector2(slot.point.x,slot.point.z)): continue
		if vehicle and (slot.width<5 or slot.a.distance_to(slot.b)<16): continue
		var direction: Vector3 = slot.a.direction_to(slot.b)
		var point: Vector3 = slot.point
		var lane_index := 0
		var side := 1.0 if randf()>.5 else -1.0
		if vehicle:
			var one_way: bool = str(slot.road.id).contains("inbound") or str(slot.road.id).contains("outbound")
			if not one_way and side<0: direction = -direction
			lane_index = randi_range(0,maxi(1,int(slot.road.get("lanes_per_direction",1)))-1)
			point += production.ambient_traffic_routes._lane_offset(direction,{"width":slot.width,"one_way":one_way,"lanes":slot.road.get("lanes_per_direction",1)},lane_index)
		elif not slot.get("bridge_walk",false): point += direction.cross(Vector3.UP)*(slot.width*.5+.85)*side
		if not production._spawn_point_allowed(point,3.0 if vehicle else 1.0,45.0 if vehicle else 18.0): continue
		var nearby := 0
		var too_close := false
		var actors: Array = production.vehicles if vehicle else production.world.people
		for actor in actors:
			if not is_instance_valid(actor) or not actor.visible: continue
			var distance: float = actor.global_position.distance_to(point)
			if distance<(16.0 if vehicle else 5.0): too_close = true; break
			if distance<(35.0 if vehicle else 22.0): nearby += 1
		if too_close or nearby>=(4 if vehicle else 4): continue
		var score := nearby*10.0+randf()
		if score<best_score:
			best_score = score
			best = slot.duplicate()
			best.point = point
			best.direction = direction
			best.lane_index = lane_index
	return best
