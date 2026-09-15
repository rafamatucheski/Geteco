extends RefCounted
## Bounded car-pose search through the actual driveway, including three-point
## maneuvers. Every edge is an arc or straight travel, never lateral motion.
const STEP := 13.7444679 # radius 70 * PI/16
var open: Array[int] = []
var nodes: Array[Dictionary] = []
var costs := {}
var path := PackedVector2Array()
var headings := PackedFloat32Array()
var finished := false
var expansions := 0
var _goal := Vector2.ZERO
var _angle := 0.0
var _bounds := Rect2()
var _query: PhysicsShapeQueryParameters2D
var _hull: CollisionShape2D
var _space: PhysicsDirectSpaceState2D

func configure(unit: CharacterBody2D, goal: Vector2, heading: float) -> void:
	_goal = goal
	_angle = heading
	_bounds = Rect2(unit.global_position,Vector2.ZERO).expand(goal).grow(200)
	_hull = unit.get_node("CollisionShape2D")
	_query = PhysicsShapeQueryParameters2D.new()
	_query.shape = _hull.shape
	_query.exclude = [unit.get_rid()]
	_query.collision_mask = unit.collision_mask
	_query.margin = preload("res://emergency/AmbulanceApproach.gd")._hull_margin(unit)+.2
	_space = unit.get_world_2d().direct_space_state
	var start := Vector3(unit.global_position.x,unit.global_position.y,unit.global_rotation)
	nodes.append({"pose":start,"cost":0.0,"score":_heuristic(start),"parent":-1,"direction":0})
	open.append(0)
	costs[_key(start)] = 0.0

func _key(at: Vector3) -> Vector3i:
	return Vector3i(roundi(at.x/7),roundi(at.y/7),posmod(roundi(at.z/(PI/16)),32))

func _heuristic(at: Vector3) -> float:
	return Vector2(at.x,at.y).distance_to(_goal)+35*absf(angle_difference(at.z,_angle))

func _arc(at: Vector3, travel: float, turn: float) -> Vector3:
	var half := turn*.5
	var length := travel if absf(turn)<.001 else travel*sin(half)/half
	var motion := Vector2.from_angle(at.z+half)*length
	return Vector3(at.x+motion.x,at.y+motion.y,at.z+turn)

func advance() -> void:
	var deadline := Time.get_ticks_usec()+900
	while not open.is_empty() and Time.get_ticks_usec()<deadline:
		open.sort_custom(func(a:int,b:int):return nodes[a].score<nodes[b].score)
		var id: int = open.pop_front()
		var node: Dictionary = nodes[id]
		var at: Vector3 = node.pose
		if node.cost>float(costs.get(_key(at),INF))+.01: continue
		expansions+=1
		var local := (Vector2(at.x,at.y)-_goal).rotated(-_angle)
		if local.x>=-1 and local.x<=12 and absf(local.y)<=4 and absf(angle_difference(at.z,_angle))<.025:
			while id>=0:
				var pose: Vector3 = nodes[id].pose
				path.insert(0,Vector2(pose.x,pose.y))
				headings.insert(0,pose.z)
				id = nodes[id].parent
			finished = true
			return
		if expansions>=4500: finished = true; return
		for direction in [-1,1]:
			for steering in [-1,0,1]:
				# Replanning may start halfway through an arc. Anchor turns to
				# the bay heading instead of preserving that fractional error.
				var aligned := _angle+roundf((at.z-_angle)/(PI/16))*PI/16
				var turn: float = 0 if steering==0 else angle_difference(at.z,aligned+direction*steering*PI/16)
				var travel := maxf(STEP,70*absf(turn))
				var to := _arc(at,direction*travel,turn)
				if not _bounds.has_point(Vector2(to.x,to.y)): continue
				var cost: float = node.cost+travel*(1.0 if direction==1 else 1.12)+(12 if node.direction!=0 and node.direction!=direction else 0)
				var key := _key(to)
				if cost>=float(costs.get(key,INF)): continue
				var clear := true
				for part in 4:
					var a := _arc(at,direction*travel*part/4,turn*part/4)
					var b := _arc(at,direction*travel*(part+1)/4,turn*(part+1)/4)
					_query.transform = Transform2D(b.z,Vector2(a.x,a.y))*_hull.transform
					_query.motion = Vector2(b.x-a.x,b.y-a.y)
					if not _space.intersect_shape(_query,1).is_empty() or _space.cast_motion(_query)[0]<1: clear=false; break
				if not clear: continue
				costs[key] = cost
				nodes.append({"pose":to,"cost":cost,"score":cost+_heuristic(to)*1.5,"parent":id,"direction":direction})
				open.append(nodes.size()-1)
	if open.is_empty(): finished = true
