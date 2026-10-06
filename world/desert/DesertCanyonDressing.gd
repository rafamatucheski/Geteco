extends RefCounted
## Static fallen sandstone and exposed buttresses. Chunk ownership uses each centre;
## all chunks must pass the same world seed. The supplied height is the final terrain surface.
const FIELD := preload("res://world/desert/DesertTerrainRelief.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const FORMS := preload("res://world/desert/DesertHorizonRelief.gd")
const ROCKS := preload("res://world/desert/DesertSurfaceRocks.gd")
const PASSAGE_MARGIN := 2.0
static var _records: Dictionary = {}

static func build_chunk(parent: Node3D, rect: Rect2, world_seed: int, height_callable: Callable) -> int:
	if not rect.intersects(FIELD.BOUNDS) or not height_callable.is_valid(): return 0
	if not _records.has(world_seed): _records[world_seed]=_placements(world_seed)
	var count := 0
	for record in _records[world_seed]:
		var p: Vector2=record.position
		if not rect.has_point(p): continue
		var radius: float=record.radius
		if not _clear(p,radius): continue
		var normal := FIELD.normal_at(p)
		if normal.y<.50 or normal.y>.992: continue
		var base := _base_height(p,radius,height_callable)
		var node: Node3D
		if bool(record.buttress):
			node=FORMS.create_outcrop(parent,Vector3(p.x,base,p.y),radius,float(record.height),int(record.seed),true)
			node.name="CanyonExposedButtress"
		else:
			var size: Vector3=record.size
			node=ROCKS.rock(parent,"CanyonFallenSandstone",Vector3(p.x,base+size.y*.40,p.y),size,record.color,true)
			# Reuse the shared vertex-colour material; one new material per stone is unnecessary.
			(node as MeshInstance3D).material_override=FORMS.material()
			for child in node.get_children():
				if child is StaticBody3D: child.set_meta("vehicle_surface","hard")
		node.set_meta("canyon_dressing",true)
		node.set_meta("footprint_radius",radius)
		count+=1
	return count

static func _placements(world_seed: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var centers := FIELD.canyon_centerline(28.0)
	var rng := RandomNumberGenerator.new()
	rng.seed=world_seed+17031
	# Alternating gaps leave the route open and avoid two artificial rows of identical stones.
	for i in range(3,centers.size()-2):
		for side in [-1.0,1.0]:
			if (i+int(side))%4==0: continue
			var center := Vector2(centers[i].x,centers[i].z+rng.randf_range(-4.0,4.0))
			var anchor := _flank(center,side,3.0)
			if not anchor.is_finite(): continue
			for stone in 3:
				var p := anchor+Vector2(side*float(stone)*1.8,rng.randf_range(-4.3,4.3))
				var size := Vector3(rng.randf_range(2.7,4.8),rng.randf_range(2.0,3.9),rng.randf_range(2.2,4.5))
				if stone==2: size*=.59
				var radius := maxf(size.x,size.z)*.5
				if not _clear(p,radius): continue
				result.append({"position":p,"radius":radius,"size":size,"buttress":false,"color":Color("96744f").lerp(Color("b08c61"),rng.randf_range(.0,.48))})
	# Three exposed ribs sit on the wall itself. The western ascent and its landing remain reserved.
	for index in 3:
		var i := clampi(4+index*3,3,centers.size()-3)
		var side := -1.0 if index==1 else 1.0
		var center := Vector2(centers[i].x,centers[i].z)
		var radius := 6.0+float(index)*.55
		var p := _flank(center,side,radius)+Vector2(side*3.0,0)
		if not p.is_finite() or not _clear(p,radius): continue
		result.append({"position":p,"radius":radius,"height":11.5+float(index)*1.4,"seed":world_seed+index*271,"buttress":true})
	return result

static func _flank(center: Vector2, side: float, radius: float) -> Vector2:
	for distance in range(18,89,3):
		var p := center+Vector2(side*float(distance),0)
		if _clear(p,radius) and FIELD.height_at(p)>1.5: return p
	return Vector2(INF,INF)

static func _clear(p: Vector2, radius: float) -> bool:
	if not FIELD.BOUNDS.grow(-radius-1.0).has_point(p): return false
	if FIELD.passage_clear(p,radius+PASSAGE_MARGIN): return false
	return LAYOUT.road_clear(p,radius+3.0)

static func _base_height(p: Vector2, radius: float, height_callable: Callable) -> float:
	# The convex footprints fit inside this circle. Embed downhill feet and all uphill faces.
	var base := float(height_callable.call(p))
	for i in 12:
		var angle := float(i)*TAU/12.0
		base=minf(base,float(height_callable.call(p+Vector2(cos(angle),sin(angle))*radius)))
	return base-.16
