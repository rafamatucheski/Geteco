extends Node3D
var state := "closed"
var owner_coach: Node3D
var queue: Array[Node3D] = []
var opening := 0.0
var timer := 0.0
var entering := false
var arm: Node3D
var body: StaticBody3D
var collider: CollisionShape3D
var signals: Array[StandardMaterial3D] = []
var requests := 0
var authorizations := 0
var passages := 0
var occupancy_query := PhysicsShapeQueryParameters3D.new()
func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh
func _ready() -> void:
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	collider = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.75,.16,.18)
	collider.shape = shape
	collider.position.y = 1.22
	body.add_child(collider)
	box(self,Vector3(-2.375,.6,0),Vector3(.38,1.2,.4),Color("e7bc4b"))
	arm = Node3D.new()
	arm.position = Vector3(-2.375,1.22,0)
	add_child(arm)
	box(arm,Vector3(2.375,0,0),Vector3(4.75,.12,.14),Color("f8ebce"))
	for i in 8: box(arm,Vector3(.3+i*.56,0,0),Vector3(.2,.125,.15),Color("bf4537"))
	for i in 3:
		var lamp := box(self,Vector3(-2.375,2.2-i*.26,.22),Vector3(.2,.2,.07),Color("253331"))
		signals.append(lamp.material_override)
	signals[0].albedo_color = Color("ed5344")
	var zone := BoxShape3D.new()
	zone.size = Vector3(4.9,1.7,1.0)
	occupancy_query.shape = zone
	occupancy_query.collision_mask = 7
	occupancy_query.exclude = [body.get_rid()]

func stop_distance(coach: Node3D, route: Curve3D) -> float:
	var size: Vector3 = coach.shape.shape.size
	var hull := AABB(-size*.5,size)
	var barrier := AABB(global_position+Vector3(-2.375,1.1,-.1),Vector3(4.75,.3,.2))
	var length := route.get_baked_length()
	var d := 0.0
	while d <= length:
		var point := route.sample_baked(d)
		var direction := route.sample_baked(minf(d+.1,length))-route.sample_baked(maxf(0,d-.1))
		var yaw := atan2(-direction.x,-direction.z)
		var bounds: AABB = Transform3D(Basis(Vector3.UP,yaw),point+Vector3.UP*coach.shape.position.y)*hull
		if bounds.intersects(barrier): return maxf(0,d-.6)
		d += .1
	return INF

func clearance(coach: Node3D) -> float:
	if coach.gate_passed: return INF
	if owner_coach == coach and state == "passing" and opening >= .99: return INF
	var distance: float = maxf(0,coach.gate_stop-coach.progress)
	if distance < .15 and coach.speed < .2 and owner_coach != coach and not queue.has(coach):
		queue.append(coach)
		requests += 1
	return distance

func occupied() -> bool:
	occupancy_query.transform.origin = global_position+Vector3.UP*1.3
	return not get_world_3d().direct_space_state.intersect_shape(occupancy_query,1).is_empty()

func tick(delta: float) -> void:
	if state=="closed" and queue.is_empty(): return
	var in_use := occupied()
	timer += delta
	match state:
		"closed":
			while not queue.is_empty() and not is_instance_valid(queue[0]): queue.pop_front()
			if not queue.is_empty(): owner_coach = queue.pop_front(); state = "checking"; timer = 0
		"checking":
			if not is_instance_valid(owner_coach): state = "closed"
			elif timer >= 2.2 and not in_use: state = "opening"; authorizations += 1
		"opening":
			opening = move_toward(opening,1,delta*.85)
			if opening >= .99: state = "passing"
		"passing":
			var cleared := not is_instance_valid(owner_coach)
			if not cleared:
				var size: Vector3 = owner_coach.shape.shape.size
				var hull: AABB = owner_coach.global_transform*AABB(Vector3(-size.x*.5,0,-size.z*.5),size)
				cleared = hull.end.z < global_position.z-.56 if entering else hull.position.z > global_position.z+.56
			if cleared and not in_use:
				if is_instance_valid(owner_coach): owner_coach.gate_passed = true
				owner_coach = null; passages += 1; state = "closing"
		"closing":
			opening = move_toward(opening,1 if in_use else 0,delta*.85)
			if opening <= 0: state = "closed"
	collider.disabled = opening >= .99 or in_use
	arm.rotation.z = opening*PI*.49
	var selected := 2 if state in ["opening","passing"] else (1 if state=="checking" else 0)
	for i in 3: signals[i].albedo_color = [Color("ed5344"),Color("ffd365"),Color("64eaa5")][i] if i==selected else Color("253331")
