extends RefCounted
## Optional outdoor discoveries in the empty north and west of the desert.
## The owning region streams each anchor once and reserves clear approaches.
const RAIL := preload("res://world/desert/expansion/DesertRelicsRail.gd")
const SITES := preload("res://world/desert/expansion/DesertRelicsSites.gd")
const BATCH := preload("res://world/desert/expansion/DesertRelicsBatch.gd")
const STATION := Vector2(-960,-465)
const MINE := Vector2(-1260,-1080)
const WAGON := Vector2(-732,-430)
const WRECK := Vector2(-510,-460)

static func build_chunk(parent: Node3D, rect: Rect2, world_seed: int, height_callable: Callable) -> int:
	if not height_callable.is_valid(): return 0
	var count := RAIL.build_chunk(parent, rect, world_seed, height_callable)
	count += _build_approaches(parent,rect,height_callable)
	for record in sites():
		var point: Vector2 = record.position
		if not rect.has_point(point): continue
		SITES.build(parent, record.id, Vector3(point.x, float(height_callable.call(point)), point.y), world_seed)
		count += 1
	return count

static func _build_approaches(parent: Node3D, rect: Rect2, height: Callable) -> int:
	var batch: RefCounted = null
	var count := 0
	for path in approach_paths():
		for i in range(1,path.size()):
			var a: Vector2 = path[i-1]
			var b: Vector2 = path[i]
			var direction := (b-a).normalized()
			var side := Vector2(-direction.y,direction.x)
			var length := a.distance_to(b)
			var steps := ceili(length/4.0)
			for j in steps:
				if j%17 == 9: continue
				var point: Vector2 = a.lerp(b,(float(j)+.5)/float(steps))
				if not rect.has_point(point): continue
				if batch==null: batch=BATCH.new(parent,"RelicApproachTracks",Vector3.ZERO)
				for offset in [-.8,.8]:
					var p: Vector2 = point+side*float(offset)
					batch.box("WornTyreRut",Vector3(p.x,float(height.call(p))+.005,p.y),Vector3(length/float(steps)+.025,.01,.27),"trail",false,Vector3(0,-atan2(direction.y,direction.x),0))
				count+=1
	if batch!=null: batch.finish()
	return count

static func sites() -> Array[Dictionary]:
	return [
		{"id":"station", "position":STATION, "radius":27.0},
		{"id":"mine", "position":MINE, "radius":28.0},
		{"id":"wagon", "position":WAGON, "radius":14.0},
		{"id":"wreck", "position":WRECK, "radius":10.0},
	]

static func reservation_clear(point: Vector2, radius: float = 0.0) -> bool:
	if station_yard_bounds().grow(maxf(radius,0.0)+2.0).has_point(point): return false
	for record in sites():
		if point.distance_to(record.position) < float(record.radius) + maxf(radius, 0.0): return false
	# A worn approach from the west highway gives the remote mine a readable route.
	for path in approach_paths():
		for i in range(1, path.size()):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, path[i-1], path[i])) < 3.5 + maxf(radius, 0.0): return false
	return RAIL.reservation_clear(point, radius)

static func station_yard_bounds() -> Rect2:
	var platform: Rect2 = SITES.station_platform().bounds
	var start := STATION+Vector2(-12,6)
	return Rect2(start,Vector2(24,platform.end.y-start.y))

static func approach_paths() -> Array:
	return [
		[Vector2(-1060,-860), Vector2(-1120,-980), Vector2(-1200,-1100), Vector2(-1238,-1080)],
		[Vector2(-960,-540), Vector2(-978,-525), Vector2(-996,-505), Vector2(-970,-485)],
	]

static func secrets() -> Array[Dictionary]:
	return [
		{"id":"desert_relic_station", "position":Vector3(-957,0,-463), "target":Vector3(-955.6,.65,-463), "amount":950, "action":"Examinar caixa de passagens", "clue":"O último bilhete foi emitido há décadas. Sob os papéis, Dante encontra o caixa esquecido da estação."},
		{"id":"desert_relic_mine", "position":Vector3(-1248,0,-1074), "target":Vector3(-1246.8,.5,-1074), "amount":1650, "action":"Abrir caixa de ferramentas", "clue":"Entre ferramentas gastas, há um envelope com o pagamento que um garimpeiro nunca voltou para buscar."},
		{"id":"desert_relic_wagon", "position":Vector3(-732,0,-426.4), "target":Vector3(-732,.5,-427.9), "amount":1250, "action":"Examinar carga caída", "clue":"Uma caixa se abriu quando o vagão descarrilou. Debaixo da lona ressecada, Dante encontra dinheiro guardado em uma lata."},
		{"id":"desert_relic_wreck", "position":Vector3(-506.9,0,-457), "target":Vector3(-508.3,.45,-457), "amount":700, "action":"Vasculhar maleta", "clue":"A areia entrou pela cabine da caminhonete. Uma maleta ainda está presa ao lado da carroceria."},
	]

static func locations() -> Array[Dictionary]:
	# Local route/solid samples are deliberately authored independently of the
	# placement builder so a fixture can detect obstructed accesses and clipping.
	return [
		{"id":"station", "position":Vector3(STATION.x,0,STATION.y), "camera_target":Vector3(-964,1,-450), "camera_size":62.0,
		 "approach":[Vector3(0,0,10),Vector3(3,0,7),Vector3(3,0,2)],
		 "solids":[{"id":"station_wall","start":Vector3(0,.04,-7),"motion":Vector3(0,0,6)}, {"id":"ticket_chest","start":Vector3(7,.04,2),"motion":Vector3(-4,0,0)}, {"id":"tower_leg","start":Vector3(-17.65,.04,-11),"motion":Vector3(0,0,4)}]},
		{"id":"mine", "position":Vector3(MINE.x,0,MINE.y), "camera_target":Vector3(-1260,1,-1080), "camera_size":56.0,
		 "approach":[Vector3(24,0,16),Vector3(12,0,16),Vector3(12,0,6)],
		 "solids":[{"id":"mine_seal","start":Vector3(-5,.04,2),"motion":Vector3(0,0,-8)}, {"id":"mine_cart","start":Vector3(-1.5,.04,5.8),"motion":Vector3(-5,0,0)}, {"id":"tool_chest","start":Vector3(15.5,.04,6),"motion":Vector3(-4,0,0)}]},
		{"id":"wagon", "position":Vector3(WAGON.x,0,WAGON.y), "camera_target":Vector3(-732,1,-430), "camera_size":25.0,
		 "approach":[Vector3(8,0,7),Vector3(0,0,7),Vector3(0,0,3.6)],
		 "solids":[{"id":"wagon_end","start":Vector3(-8,.04,0),"motion":Vector3(5,0,0)}, {"id":"spilled_crate","start":Vector3(-3.3,.04,6),"motion":Vector3(0,0,-4)}, {"id":"wagon_cache","start":Vector3(0,.04,3.6),"motion":Vector3(0,0,-2)}]},
		{"id":"wreck", "position":Vector3(WRECK.x,0,WRECK.y), "camera_target":Vector3(-510,1,-460), "camera_size":17.0,
		 "approach":[Vector3(6,0,6),Vector3(3.1,0,6),Vector3(3.1,0,3)],
		 "solids":[{"id":"wreck_cab","start":Vector3(3,.04,-.2),"motion":Vector3(-5,0,0)}, {"id":"wreck_cache","start":Vector3(3.1,.04,3),"motion":Vector3(-3,0,0)}]},
	]
