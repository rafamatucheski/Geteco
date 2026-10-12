extends RefCounted
## Authored-terrain orthographic safety: canyon/quarry footprints and near plane.
## Height queries occur in at most one batch per 0.1s (except a fresh camera/teleport).
const TERRAIN := preload("res://world/desert/DesertTerrainMesh.gd")
const MINING_LAYOUT := preload("res://world/mining/MiningLayout.gd")
const MINING_TERRAIN := preload("res://world/mining/MiningExterior.gd")
const BOUNDS := Rect2(-1140.0,-1936.0,580.0,368.0)
const INTERVAL := .1
const MAX_PITCH := deg_to_rad(82.0)
const SIGHT_MARGIN := .9
const PLANE_MARGIN := 1.0
const CACHE_MARGIN := 8.0
const MAX_VERTEX_SAMPLES := 4096
## Conservative authored field bound:17+29+2.4+3.5=51.9m, plateau22m; all blends convex.
const FIELD_HEIGHT_CEILING := 60.0
## Falling past successive quarry benches must not repeatedly lower/raise the
## view between safety samples. Retain the raised view until clearance settles.
const PITCH_RELEASE_DELAY := .85
const PITCH_RELEASE_SPEED := deg_to_rad(8.0)
var _retained_pitch := 0.0
var _pitch_release_clock := 0.0
var _pitch := 0.0
var _distance := 0.0
var _minimum_pitch := 0.0
var _desired_pitch := 0.0
var _near_height := 0.0
var _elapsed := INTERVAL
var _active := false
var _height_cache: Dictionary={}
var _next_cache: Dictionary={}
var _last_focus := Vector3.ZERO
var _height_queries := 0
var _last_batch_queries := 0
var _fallback_bound := false
var _needed_pitch := 0.0
var _near_clearance := INF
var _last_direction := Vector3.ZERO
var _last_target := Vector3.INF
var _last_velocity := Vector3.ZERO
var _last_view := Vector2.ZERO
var _last_radius := 0.0
var _last_near := 0.0
var _cached_pitch := 0.0
var _cached_distance := 0.0
var _query_bounds := BOUNDS
var _boundary_camera := preload("res://world/desert/entrance/DesertBoundaryCamera.gd").new()

func offset_for(focus: Vector3,nominal: Vector3,delta: float,snap: bool,enabled: bool,view_size := Vector2(36,20),near_clip := .1,target_position := Vector3.INF,target_radius := 3.4,target_velocity := Vector3.ZERO,falling := false) -> Vector3:
	var nominal_length := nominal.length()
	var flat := Vector3(nominal.x,0,nominal.z)
	var direction := flat.normalized()
	var base_pitch := atan2(nominal.y,flat.length())
	var planar_focus := Vector2(focus.x,focus.z)
	var at_quarry := MINING_LAYOUT.enabled() and MINING_LAYOUT.BOUNDS.grow(24.0).has_point(planar_focus)
	_query_bounds=MINING_LAYOUT.BOUNDS if at_quarry else BOUNDS
	var local := enabled and _query_bounds.grow(24.0).has_point(planar_focus)
	if not enabled:
		_active=false
		_retained_pitch=base_pitch
		_pitch_release_clock=0.0
		_pitch=base_pitch
		_distance=nominal_length
		return nominal
	if not local:
		_active=false
		# Outside the terrain's24m guard the nearby basin is flat. Restore the usual view gently.
		if _pitch<=0 or snap:
			_pitch=base_pitch
			_distance=nominal_length
		else:
			_pitch=lerpf(_pitch,base_pitch,1.0-exp(-5.0*maxf(delta,0)))
			_distance=lerpf(_distance,nominal_length,1.0-exp(-5.0*maxf(delta,0)))
		var restored_offset:=direction*cos(_pitch)*_distance+Vector3.UP*sin(_pitch)*_distance
		return _boundary_camera.offset_for(focus,restored_offset,view_size,near_clip,delta,snap)
	var target := focus if target_position==Vector3.INF else target_position
	_elapsed+=maxf(delta,0)
	var fresh := not _active or snap or focus.distance_to(_last_focus)>8.0
	var changed := focus.distance_to(_last_focus)>.1 or target.distance_to(_last_target)>.1 or direction.distance_to(_last_direction)>.008 or view_size.distance_to(_last_view)>.05 or target_velocity.distance_to(_last_velocity)>.1 or absf(target_radius-_last_radius)>.01 or absf(near_clip-_last_near)>.01 or absf(_pitch-_cached_pitch)>deg_to_rad(.5) or absf(_distance-_cached_distance)>.5
	if fresh or (_elapsed>=INTERVAL and changed):
		_elapsed=0
		_height_queries=0
		_fallback_bound=false
		_next_cache={}
		_solve_sight(target,direction,base_pitch,target_radius,target_velocity)
		var candidate_pitch := clampf(_pitch,_minimum_pitch,MAX_PITCH) if _active else _desired_pitch
		_near_height=0
		var candidate_distance := maxf(nominal_length,_distance)
		# Every footprint covers whole terrain cells, including an8m motion/heading guard.
		# Retain the maximum across trials so an intermediate/smoothed distance is safe too.
		for iteration in 4:
			_near_height=maxf(_near_height,_plane_height_bound(focus,direction,candidate_pitch,candidate_distance,view_size,near_clip))
			var required := _required_distance(focus,candidate_pitch,nominal_length,view_size,near_clip)
			if required<=candidate_distance+.01: break
			candidate_distance=required
			if iteration==3:
				# Finite fallback is an authored elevation bound, not skipped safety work.
				_near_height=_field_height_ceiling()
				_fallback_bound=true
		_height_cache=_next_cache
		_last_batch_queries=_height_queries
		_last_focus=focus
		_last_direction=direction
		_last_target=target
		_last_velocity=target_velocity
		_last_view=view_size
		_last_radius=target_radius
		_last_near=near_clip
		_cached_pitch=candidate_pitch
		_cached_distance=candidate_distance
		if fresh:
			_pitch=_desired_pitch
			_retained_pitch=_desired_pitch
			_pitch_release_clock=PITCH_RELEASE_DELAY
		_active=true
	# Safety still raises the lens immediately. Lowering waits for sustained
	# clearance, then has a bounded rate, instead of chasing every bench edge.
	if falling: _retained_pitch=maxf(_retained_pitch,_pitch)
	if _desired_pitch>=_retained_pitch-deg_to_rad(.25):
		_retained_pitch=maxf(_retained_pitch,_desired_pitch)
		_pitch_release_clock=PITCH_RELEASE_DELAY
	else:
		_pitch_release_clock=PITCH_RELEASE_DELAY if falling else maxf(0.0,_pitch_release_clock-maxf(delta,0))
		if _pitch_release_clock<=0.0:
			_retained_pitch=move_toward(_retained_pitch,_desired_pitch,PITCH_RELEASE_SPEED*maxf(delta,0))
	_pitch=maxf(_minimum_pitch,lerpf(_pitch,_retained_pitch,1.0-exp(-6.0*maxf(delta,0))))
	var required_distance := _required_distance(focus,_pitch,nominal_length,view_size,near_clip)
	_distance=maxf(required_distance,lerpf(_distance,required_distance,1.0-exp(-5.0*maxf(delta,0))))
	_near_clearance=focus.y+(_distance-near_clip)*sin(_pitch)-view_size.y*.5*cos(_pitch)-_near_height
	return direction*cos(_pitch)*_distance+Vector3.UP*sin(_pitch)*_distance

func _solve_sight(target: Vector3,direction: Vector3,base_pitch: float,radius: float,velocity: Vector3) -> void:
	var right := Vector3(direction.z,0,-direction.x)
	var anticipation := Vector3(velocity.x,0,velocity.z)*.15
	if anticipation.length()>6: anticipation=anticipation.normalized()*6
	_needed_pitch=base_pitch
	# Parallel orthographic rays start from centre and four footprint corners, now and ahead.
	for future in [Vector3.ZERO,anticipation]:
		for corner in [Vector2.ZERO,Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1)]:
			var start: Vector3=target+future+(right*corner.x+direction*corner.y)*radius
			for step in range(1,31):
				var distance := float(step)*1.5
				var point := start+direction*distance
				var height := _surface_height(Vector2(point.x,point.z))
				_height_queries+=1
				_needed_pitch=maxf(_needed_pitch,atan2(height+SIGHT_MARGIN-start.y,distance))
	_minimum_pitch=minf(MAX_PITCH,_needed_pitch)
	_desired_pitch=minf(MAX_PITCH,_minimum_pitch+deg_to_rad(3.0)) if _minimum_pitch>base_pitch+.001 else base_pitch

func _required_distance(focus: Vector3,pitch: float,nominal_length: float,view_size: Vector2,near_clip: float) -> float:
	# Bottom of the entire near-plane rectangle, not only its centre, clears the highest sampled cell.
	return maxf(nominal_length,(_near_height+PLANE_MARGIN+view_size.y*.5*cos(pitch)-focus.y)/maxf(sin(pitch),.1)+near_clip)

func _plane_height_bound(focus: Vector3,direction: Vector3,pitch: float,distance: float,view_size: Vector2,near_clip: float) -> float:
	var right := Vector3(direction.z,0,-direction.x)
	var up := Vector3.UP*cos(pitch)-direction*sin(pitch)
	var normal := direction*cos(pitch)+Vector3.UP*sin(pitch)
	var center := focus+normal*(distance-near_clip)
	var area := Rect2(Vector2(center.x,center.z),Vector2.ZERO)
	for x in [-1.0,1.0]:
		for y in [-1.0,1.0]:
			var point: Vector3=center+right*float(x)*view_size.x*.5+up*float(y)*view_size.y*.5
			area=area.expand(Vector2(point.x,point.z))
	area=area.grow(CACHE_MARGIN+TERRAIN.CAMERA_SAMPLE_STEP).intersection(_query_bounds)
	if not area.has_area(): return 0
	var highest := 0.0
	for x in range(floori(area.position.x/TERRAIN.CAMERA_SAMPLE_STEP),ceili(area.end.x/TERRAIN.CAMERA_SAMPLE_STEP)+1):
		for z in range(floori(area.position.y/TERRAIN.CAMERA_SAMPLE_STEP),ceili(area.end.y/TERRAIN.CAMERA_SAMPLE_STEP)+1):
			var key := Vector2i(x,z)
			var height: float
			if _next_cache.has(key): height=float(_next_cache[key])
			elif _height_cache.has(key):
				height=float(_height_cache[key])
				_next_cache[key]=height
			else:
				if _next_cache.size()>=MAX_VERTEX_SAMPLES:
					_fallback_bound=true
					return _field_height_ceiling()
				height=_surface_height(Vector2(key)*TERRAIN.CAMERA_SAMPLE_STEP)
				_height_queries+=1
				_next_cache[key]=height
			highest=maxf(highest,height)
	return highest

func _surface_height(point: Vector2) -> float:
	if MINING_LAYOUT.enabled() and MINING_LAYOUT.BOUNDS.has_point(point): return MINING_TERRAIN.surface_height(point)
	return TERRAIN.surface_height(point)

func _field_height_ceiling() -> float:
	# Excavation only removes earth: the rim stays at datum. Keep the canyon's
	# existing conservative 60 m bound; a quarry fallback need not invent a hill.
	return 0.0 if _query_bounds==MINING_LAYOUT.BOUNDS else FIELD_HEIGHT_CEILING

func diagnostics() -> Dictionary:
	return {"active":_active,"pitch_degrees":rad_to_deg(_pitch),"required_pitch_degrees":rad_to_deg(_needed_pitch),"pitch_limit_reached":_needed_pitch>MAX_PITCH,"distance":_distance,"near_plane_conservative_clearance":_near_clearance,"terrain_queries_last_batch":_last_batch_queries,"cached_vertices":_height_cache.size(),"query_interval":INTERVAL,"authored_height_fallback_used":_fallback_bound,"scope":"Terrain only; no prop/roof collision. Target footprint now/ahead and near-plane cells, with8m movement guard."}
