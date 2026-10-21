extends RefCounted
## Independent west-side gorge. Heights are metres below the desert datum.
const DIMENSIONS := preload("res://world/desert/canyon/CanyonDimensions.gd")
## 29,160 square metres: 30% of the former 270 x 360 m formation.
const BOUNDS := Rect2(-1285,-610,162,180)
const CENTER := Vector3(-1204,0,-492)
const CAMP_BOUNDS := Rect2(-1240,-524,72,64)
const ARMORY_POS := Vector3(-1220,0,-481)
const APPROACH := Vector3(-1204,0,-612.5)
const BRIDGE_START := Vector3(-1204,0,-603.5)
const BRIDGE_END := Vector3(-1204,0,-530)
const BRIDGE_WIDTH := 3.8
const BRIDGE_DECK := .12
const GATE_Z := -540.0
const DEPTH := 21.6
const STEP := 1.5
const CAMERA_SIZE := 40.0
const POSTS := [Vector3(-8,0,-20),Vector3(8,0,-20),Vector3(-20,0,-9),Vector3(20,0,-9),Vector3(-24,0,5),Vector3(22,0,5),Vector3(-6,0,14),Vector3(10,0,17)]
static var _enabled := -1

static func enabled() -> bool:
	if _enabled<0:
		var args := OS.get_cmdline_user_args()
		var baseline := OS.is_debug_build() and "--smuggler-baseline" in args and "--benchmark" in args and "--no-save" in args
		_enabled=0 if baseline else 1
	return _enabled==1

static func combat_spawn_points() -> PackedVector3Array:
	var result := PackedVector3Array()
	for offset: Vector3 in POSTS: result.append(CENTER+offset)
	return result

static func approach_path() -> PackedVector3Array:
	return PackedVector3Array([Vector3(-1060,0,-650),Vector3(-1120,0,-650),Vector3(-1204,0,-633.5),APPROACH,BRIDGE_START])

static func gate_walk_path() -> PackedVector3Array:
	return PackedVector3Array([Vector3(CENTER.x+.725,BRIDGE_DECK,GATE_Z-4),Vector3(CENTER.x+.725,BRIDGE_DECK,GATE_Z+6),BRIDGE_END+Vector3(.725,BRIDGE_DECK,3)])

static func reservation_clear(point: Vector2,radius := 0.0) -> bool:
	if not enabled(): return true
	if BOUNDS.grow(radius+5).has_point(point): return false
	var path := approach_path()
	for i in range(1,path.size()):
		if Geometry2D.get_closest_point_to_segment(point,Vector2(path[i-1].x,path[i-1].z),Vector2(path[i].x,path[i].z)).distance_to(point)<7+radius: return false
	return true

static func analytic_height(point: Vector2) -> float:
	if not enabled() or not BOUNDS.has_point(point): return 0.0
	# Compress only the empty gorge. Camp furniture, guards and its natural mesa
	# retain their original metre dimensions and entrance/armory positions.
	var source := DIMENSIONS.field_to_source(point)
	if not DIMENSIONS.SOURCE_BOUNDS.has_point(source): return 0.0
	var opening := smoothstep(-620,-550,source.y)
	var half_width := lerpf(38+3.0*sin(source.y*.023+1.0),125,opening)
	var center_x := -1205+(1-opening)*(3.0*sin((source.y+760)*.027)+1.8*sin((source.y+701)*.043))
	var q := (source-Vector2(center_x,-610))/Vector2(half_width,174)
	var angle := atan2(q.y,q.x)
	var erosion := .028*sin(angle*7+.7)+.021*sin(angle*11-1.4)
	var radial := q.length()+erosion
	# Three scarps and their benches keep the sandstone's geological structure.
	var wall := .28*smoothstep(.36,.52,radial)+.36*smoothstep(.63,.78,radial)+.36*smoothstep(.85,.99,radial)
	var wash := 1.0-smoothstep(3.0,8.0,absf(source.x-_source_wash_center(source.y)))
	var variation := 2.5*sin(source.y*.027)+1.7*sin(source.x*.041+source.y*.01)-wash*2.2
	var floor_height := -DEPTH+variation*DIMENSIONS.DEPTH_FACTOR
	var height := lerpf(floor_height,0.0,clampf(wall,0,1))
	# This island stays full size: every existing guard, cover and cache needs
	# the same solid, level metre-space as before the gorge was shortened.
	var island := (point-Vector2(CENTER.x,CENTER.z))/Vector2(42,31)
	var island_r := island.length()+.025*sin(atan2(island.y,island.x)*5)
	var mesa := 1.0-smoothstep(.88,1.20,island_r)
	return maxf(height,lerpf(floor_height,0.0,mesa))

static func _source_wash_center(z: float) -> float:
	return CENTER.x+sin(z*.041)*9.0+sin(z*.019)*4.0

static func wash_center(z: float) -> float:
	var source := DIMENSIONS.field_to_source(Vector2(CENTER.x,z))
	return DIMENSIONS.source_to_field(Vector2(_source_wash_center(source.y),source.y)).x

static func camera_weight(point: Vector3) -> float:
	if not enabled() or point.y < -5.0: return 0.0
	var across := 1.0-smoothstep(6,18,absf(point.x-CENTER.x))
	var along := smoothstep(BRIDGE_START.z-10.2,BRIDGE_START.z,point.z)*(1.0-smoothstep(-539.3,-523,point.z))
	return across*along

static func ground_remainders(rect: Rect2) -> Array[Rect2]:
	if not enabled(): return [rect]
	var overlap := rect.intersection(BOUNDS)
	if not overlap.has_area(): return [rect]
	var result: Array[Rect2]=[]
	for part in [Rect2(rect.position.x,rect.position.y,rect.size.x,overlap.position.y-rect.position.y),Rect2(rect.position.x,overlap.end.y,rect.size.x,rect.end.y-overlap.end.y),Rect2(rect.position.x,overlap.position.y,overlap.position.x-rect.position.x,overlap.size.y),Rect2(overlap.end.x,overlap.position.y,rect.end.x-overlap.end.x,overlap.size.y)]:
		if part.has_area(): result.append(part)
	return result
