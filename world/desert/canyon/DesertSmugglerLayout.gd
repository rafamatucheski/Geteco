extends RefCounted
## Independent west-side gorge. Heights are metres below the desert datum.
const BOUNDS := Rect2(-1480,-790,270,360)
const CENTER := Vector3(-1344,0,-492)
const CAMP_BOUNDS := Rect2(-1380,-524,72,64)
const ARMORY_POS := Vector3(-1360,0,-481)
const APPROACH := Vector3(-1344,0,-805)
const BRIDGE_START := Vector3(-1344,0,-775)
const BRIDGE_END := Vector3(-1344,0,-530)
const BRIDGE_WIDTH := 3.8
const BRIDGE_DECK := .12
const GATE_Z := -540.0
const DEPTH := 72.0
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
	return PackedVector3Array([Vector3(-1150,0,-880),Vector3(-1230,0,-850),Vector3(-1315,0,-839),APPROACH,BRIDGE_START])

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
	if not enabled(): return 0.0
	if not BOUNDS.has_point(point): return 0.0
	# Eroded, asymmetric oval; all four rectangle boundaries return to datum.
	# A long slot canyon exposes both walls beside the bridge at gameplay zoom;
	# it opens into a wider basin around the isolated contraband mesa.
	var opening := smoothstep(-620,-550,point.y)
	var half_width := lerpf(38+3.0*sin(point.y*.023+1.0),125,opening)
	var center_x := -1345+(1-opening)*(3.0*sin((point.y+760)*.027)+1.8*sin((point.y+701)*.043))
	var q := (point-Vector2(center_x,-610))/Vector2(half_width,174)
	var angle := atan2(q.y,q.x)
	var erosion := .028*sin(angle*7+.7)+.021*sin(angle*11-1.4)
	var radial := q.length()+erosion
	# Three geological scarps and two broad benches replace one featureless
	# excavated slope. Roughly 20/26/26 m rises occupy 5-6 m horizontally,
	# leaving 3-4 m shelves between them. Sub-metre rock samples resolve these
	# transitions rather than stretching 26 m cliffs across two grid vertices;
	# the uninterrupted floor and upper rim still share the original datum.
	var wall := .28*smoothstep(.36,.52,radial)+.36*smoothstep(.63,.78,radial)+.36*smoothstep(.85,.99,radial)
	var wash := 1.0-smoothstep(3.0,8.0,absf(point.x-wash_center(point.y)))
	var floor_height := -DEPTH+2.5*sin(point.y*.027)+1.7*sin(point.x*.041+point.y*.01)-wash*2.2
	var height := lerpf(floor_height,0.0,clampf(wall,0,1))
	var island := (point-Vector2(CENTER.x,CENTER.z))/Vector2(42,31)
	var island_r := island.length()+.025*sin(atan2(island.y,island.x)*5)
	var mesa := 1.0-smoothstep(.88,1.20,island_r)
	return maxf(height,lerpf(floor_height,0.0,mesa))

static func wash_center(z: float) -> float:
	return CENTER.x+sin(z*.041)*9.0+sin(z*.019)*4.0

static func camera_weight(point: Vector3) -> float:
	if not enabled(): return 0.0
	if point.y < -5.0: return 0.0
	var across := 1.0-smoothstep(6,18,absf(point.x-CENTER.x))
	var along := smoothstep(-809,-775,point.z)*(1.0-smoothstep(-561,-523,point.z))
	return across*along

static func ground_remainders(rect: Rect2) -> Array[Rect2]:
	if not enabled(): return [rect]
	var overlap := rect.intersection(BOUNDS)
	if not overlap.has_area(): return [rect]
	var result: Array[Rect2]=[]
	for part in [Rect2(rect.position.x,rect.position.y,rect.size.x,overlap.position.y-rect.position.y),Rect2(rect.position.x,overlap.end.y,rect.size.x,rect.end.y-overlap.end.y),Rect2(rect.position.x,overlap.position.y,overlap.position.x-rect.position.x,overlap.size.y),Rect2(overlap.end.x,overlap.position.y,rect.end.x-overlap.end.x,overlap.size.y)]:
		if part.has_area(): result.append(part)
	return result
