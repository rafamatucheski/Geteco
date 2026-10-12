extends RefCounted
## Keep the whole orthographic near plane outside solid perimeter rocks.
## Extending the lens along its existing view preserves pitch and apparent size.
const LAYOUT:=preload("res://world/desert/DesertLayout.gd")
const INTERVAL:=.1
var enabled:=true
var _elapsed:=INTERVAL
var _distance:=0.0
var _last_focus:=Vector3.INF
var _last_direction:=Vector3.ZERO
var _shape:=BoxShape3D.new()
var _query:=PhysicsShapeQueryParameters3D.new()
var last_queries:=0

func offset_for(focus: Vector3,nominal: Vector3,view_size: Vector2,near_clip: float,delta: float,snap: bool) -> Vector3:
	if not enabled: return nominal
	var bounds:=LAYOUT.BOUNDS
	var p:=Vector2(focus.x,focus.z)
	var border:=bounds.grow(30).has_point(p) and not bounds.grow(-70).has_point(p)
	if not border:
		_distance=nominal.length()
		_last_focus=Vector3.INF
		return nominal
	var tree:=Engine.get_main_loop() as SceneTree
	if tree==null or tree.root.world_3d==null: return nominal
	var direction:=nominal.normalized()
	var fresh:=snap or not _last_focus.is_finite() or _last_focus.distance_to(focus)>8 or _last_direction.distance_to(direction)>.12
	_elapsed+=delta
	if fresh or _elapsed>=INTERVAL:
		_elapsed=0
		last_queries=0
		var desired:=nominal.length()
		if not fresh: desired=maxf(desired,_distance-delta*18)
		_shape.size=Vector3(view_size.x+2,view_size.y+2,.6)
		_query.shape=_shape
		_query.collision_mask=1
		_query.collide_with_areas=false
		var space:=tree.root.world_3d.direct_space_state
		# Four bounded queries. The final distance clears the authored <=30m
		# perimeter relief at the production pitch, without a per-triangle scan.
		for attempt in 4:
			_query.transform=Transform3D(Basis.looking_at(-direction),focus+direction*(desired-near_clip))
			last_queries+=1
			var obstructed:=false
			for hit in space.intersect_shape(_query,64):
				var body: Node=hit.collider
				if body.name=="SandstoneVolumes" or body.is_in_group("scenario_boundary"):
					obstructed=true
					break
			if not obstructed: break
			desired+=16
		_distance=desired
		_last_focus=focus
		_last_direction=direction
	return direction*maxf(nominal.length(),_distance)
