extends RefCounted
## A* híbrido incremental: poses, arcos para frente/ré e o casco real do M8.
## A busca usa apoio físico e espaço varrido, incluindo calçadas.
const STEP := 2.0
const TURN := PI/8.0
const MAX_NODES := 7000
const BUDGET_US := 1800
const HEAP := preload("res://gameplay/dispatch/DispatchRoadRouter.gd").MinHeap
var car
var goal := Vector3.ZERO
var goal_yaw := 0.0
var origin := Vector3.ZERO
var nodes: Array[Dictionary] = []
var visited: Dictionary = {}
var heap
var result: Array[Dictionary] = []
var searching := false
var pending := -1
var action := 0
var expanded := 0
var padded_shape: BoxShape3D
var query := PhysicsShapeQueryParameters3D.new()
var ray := PhysicsRayQueryParameters3D.new()

func begin(vehicle, target: Vector3, yaw: float) -> void:
	car = vehicle
	goal = target
	goal_yaw = yaw
	origin = car.global_position
	nodes = [{"p":origin,"yaw":car.rotation.y,"gear":1,"g":0.0,"parent":-1,"turn":0.0}]
	visited = {_key(origin,car.rotation.y,1):0.0}
	heap = HEAP.new()
	heap.push(origin.distance_to(goal),0)
	result.clear()
	searching = true
	pending = -1
	action = 0
	expanded = 0
	var box := BoxShape3D.new()
	# Cobre os cantos varridos entre amostras de orientação, além do casco.
	box.size = car.rotation_shape.size+Vector3(.3,0,.3)
	padded_shape = box
	query.shape = box
	query.collision_mask = 7
	query.exclude = [car.get_rid()]
	ray.collision_mask = 1
	ray.exclude = [car.get_rid()]

func _key(p: Vector3, yaw: float, gear: int) -> Vector4i:
	return Vector4i(roundi(p.x/1.0),roundi(p.z/1.0),posmod(roundi(yaw/TURN),16),gear)

func tick() -> void:
	if not searching: return
	var until := Time.get_ticks_usec()+BUDGET_US
	var primitives := 0
	while Time.get_ticks_usec()<until and primitives<8:
		if pending<0:
			if heap.is_empty() or nodes.size()>=MAX_NODES:
				searching = false
				return
			pending = heap.pop()
			var n: Dictionary = nodes[pending]
			if float(n.g)>float(visited.get(_key(n.p,n.yaw,n.gear),INF)):
				pending = -1
				continue
			if (n.p as Vector3).distance_to(goal)<1.8 and absf(angle_difference(n.yaw,goal_yaw))<.55:
				_reconstruct(pending)
				return
			action = 0
			expanded += 1
		var gear := 1 if action<3 else -1
		var turn := float(action%3-1)*TURN
		var parent: Dictionary = nodes[pending]
		var p := primitive(parent.p,parent.yaw,gear,turn)
		primitives += 1
		if p.is_finite() and p.distance_to(origin)<64.0:
			var yaw: float = parent.yaw+turn
			var cost: float = parent.g+STEP*(1.0 if gear>0 else 1.45)+absf(turn)*.5+(2.0 if gear!=parent.gear else 0.0)
			var key := _key(p,yaw,gear)
			if cost<float(visited.get(key,INF)):
				visited[key] = cost
				nodes.append({"p":p,"yaw":yaw,"gear":gear,"g":cost,"parent":pending,"turn":turn})
				heap.push(cost+p.distance_to(goal)*1.15,nodes.size()-1)
		action += 1
		if action==6: pending = -1

func primitive(start: Vector3, yaw: float, gear: int, turn: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = car.get_world_3d().direct_space_state
	var p := start
	for i in 8:
		# Um para-choque parado pode estar a milímetros do bloqueio. Não proíbe
		# o primeiríssimo movimento de ré só porque a folga de planejamento se sobrepõe.
		query.shape = car.rotation_shape if i==0 else padded_shape
		var angle := yaw+turn*(float(i)+.5)/8.0
		var basis := Basis(Vector3.UP,angle)
		var next := p-basis.z*float(gear)*STEP/8.0
		var height := support(next,basis)
		if not is_finite(height) or absf(height-p.y)>.23: return Vector3.INF
		next.y = height
		var sweep_start := p
		# Meios-fios pequenos são degraus para a roda, não paredes. Checa a varredura horizontal
		# inteira do casco elevado; o motorista faz o movimento real checado para cima.
		sweep_start.y = maxf(p.y,next.y)
		query.transform = Transform3D(basis,sweep_start+basis*car.shape.position)
		query.motion = next-sweep_start
		if not space.intersect_shape(query,1).is_empty(): return Vector3.INF
		var fractions := space.cast_motion(query)
		if fractions.size()!=2 or fractions[0]<1.0: return Vector3.INF
		query.transform.origin = next+basis*car.shape.position
		query.shape = padded_shape
		if not space.intersect_shape(query,1).is_empty(): return Vector3.INF
		p = next
	return p

func support(p: Vector3, basis: Basis) -> float:
	var space: PhysicsDirectSpaceState3D = car.get_world_3d().direct_space_state
	var high := -INF
	var low := INF
	var w: float = car.half_width+.15
	var l: float = car.half_length+.15
	for local in [Vector3.ZERO,Vector3(w,0,l),Vector3(-w,0,l),Vector3(w,0,-l),Vector3(-w,0,-l)]:
		var point: Vector3 = p+basis*local
		ray.from = point+Vector3.UP*.45
		ray.to = point-Vector3.UP*.6
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP)<.85: return INF
		var height: float = hit.position.y+.01
		high = maxf(high,height)
		low = minf(low,height)
	return high if high-low<.24 else INF

func _reconstruct(index: int) -> void:
	while index>=0:
		result.push_front(nodes[index])
		index = int(nodes[index].parent)
	searching = false
