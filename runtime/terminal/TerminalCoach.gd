extends "res://scripts/Vehicle.gd"
## Conserved coach body: swept native collision for both forward and reverse travel.
const ROUTES := preload("res://runtime/terminal/TerminalRoutes.gd")
var platform := 0
var model: Node3D
var path: Curve3D
var progress := 0.0
var reverse := false
var blocked_by := ""
var travelled := 0.0
var doors := 0.0
var door_leaves: Array[Node3D] = []
var coach_wheels: Array[Node3D] = []
var clearance_query := PhysicsShapeQueryParameters3D.new()
var passengers: Array = []
var state := "parked"
var timer := 0.0
var trips := 0
var boarded := 0
var alighted := 0
var gate_passed := false
var gate_stop := INF
func _ready() -> void:
	health = 300
	max_health = 300
	half_width = .9
	half_length = 2.57
	body_height = 1.9
	collision_layer = 4
	collision_mask = 7
	floor_snap_length = .4
	shape = CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(1.8,1.9,5.14)
	shape.shape = hull
	shape.position.y = .95
	add_child(shape)
	var inset := BoxShape3D.new()
	inset.size = hull.size-Vector3.ONE*.06
	clearance_query.shape = inset
	clearance_query.collision_mask = 7
	clearance_query.exclude = [get_rid()]
	rotation_shape.size = hull.size-Vector3(0,.15,0)
	sensor_shape.size = Vector3(1.87,1.2,1)
	model = preload("res://runtime/terminal/CoachModel.gd").new()
	model.livery = [Color("247d88"),Color("a44937"),Color("426493"),Color("ae813e")][platform]
	model.operator_name = ["COSTA SUL","VIAÇÃO SERRA","EXPRESSO AZUL","LITORAL"][platform]
	model.fleet_number = str(2407+platform*131)
	model.scale = Vector3(.5625,.5,.43212447)
	# Legacy model nose is +Z; native traffic faces -Z.
	model.rotation.y = PI
	add_child(model)
	visual = model
	_batch_body()
	for side in [-1.0,1.0]:
		var leaf := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.03,1.02,.24)
		leaf.mesh = mesh
		leaf.position = Vector3(.79,.76,-2.18+side*.12)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("537482")
		leaf.material_override = material
		add_child(leaf)
		door_leaves.append(leaf)
	add_to_group("harbor_terminal_coach")
	set_meta("terminal_service","intercity")

func _physics_process(_delta: float) -> void:
	# The terminal controller schedules this body; do not run a second driver.
	pass

func set_path(value: Curve3D, backwards := false) -> void:
	_release_junction()
	path = value
	var offset := value.get_point_position(0)-global_position
	offset.y = 0
	if offset.length() > .08:
		path = Curve3D.new()
		path.bake_interval = value.bake_interval
		path.add_point(Vector3(global_position.x,.12,global_position.z))
		for point in value.get_baked_points(): path.add_point(point)
	path.set_meta("traffic_open",true)
	traffic = state=="road"
	route = path if traffic else null
	route_distance = 0
	horizontal_velocity = Vector3.ZERO
	progress = 0
	speed = 0
	reverse = backwards
	gate_passed = false
	gate_stop = INF

func set_doors(amount: float) -> void:
	doors = amount
	for i in door_leaves.size(): door_leaves[i].position.z = -2.18+(-1 if i==0 else 1)*(.12+amount*.23)

func receive_damage(amount: float, _source: Node = null) -> void:
	health = maxf(0,health-amount)

func arrived() -> bool:
	if state=="road": return path != null and route_distance >= path.get_baked_length()-1.4 and absf(speed)<.3
	return path != null and progress >= path.get_baked_length()-.08

func drive(delta: float, clearance := INF) -> void:
	if path == null or health <= 0: speed = 0; return
	if state=="road":
		# Shared traffic driver handles signals, queues, blocked lanes and safe
		# detours. Apron reversing remains under the terminal's exclusive control.
		var before := global_position
		super._physics_process(delta)
		progress = route_distance
		var distance := before.distance_to(global_position)
		travelled += distance
		for wheel in coach_wheels: wheel.rotate_object_local(Vector3.UP,distance/.29)
		blocked_by = str(blocker.get_path()) if is_instance_valid(blocker) and blocker is Node else ""
		return
	var remaining := path.get_baked_length()-progress
	var target_speed := minf(1.4 if reverse else (5.0 if state=="road" else 2.0),sqrt(3.0*maxf(0,minf(remaining,clearance))))
	speed = move_toward(speed,target_speed,2.5*delta)
	var next := minf(path.get_baked_length(),progress+speed*delta)
	var target := path.sample_baked(next,true)
	var direction := path.sample_baked(minf(next+.12,path.get_baked_length()),true)-path.sample_baked(maxf(0,next-.12),true)
	direction.y = 0
	var yaw := atan2(-direction.x,-direction.z)+(PI if reverse else 0.0)
	var query := clearance_query
	# Contact with the supporting floor is valid; use a slightly inset hull for
	# clearance queries while the full chassis still handles actual collisions.
	query.transform = Transform3D(Basis(Vector3.UP,yaw),global_position+Vector3.UP*shape.position.y)
	query.motion = Vector3.ZERO
	var contacts := get_world_3d().direct_space_state.intersect_shape(query,1)
	blocked = not contacts.is_empty()
	blocked_by = str(contacts[0].collider.get_path()) if blocked else ""
	if blocked: speed = 0; return
	rotation.y = yaw
	var motion := target-global_position
	motion.y = 0
	# Probe the complete hull ahead before applying movement; never run over a queue.
	query.motion = motion.normalized()*maxf(.15,motion.length())
	var sweep := get_world_3d().direct_space_state.cast_motion(query)
	if motion.length_squared() > .000001 and sweep[0] < .99:
		var collision := KinematicCollision3D.new()
		if test_move(global_transform,query.motion,collision): blocked_by = str(collision.get_collider().get_path())+" at "+str(collision.get_position())
		blocked = true; speed = 0; return
	var before := global_position
	velocity = motion/maxf(delta,.001)
	velocity.y = -1 if is_on_floor() else -8
	move_and_slide()
	var displacement := Vector2(global_position.x-before.x,global_position.z-before.z).length()
	travelled += displacement
	for wheel in coach_wheels: wheel.rotate_object_local(Vector3.UP,displacement/.29*(-1 if reverse else 1))
	if Vector2(global_position.x-target.x,global_position.z-target.z).length() < .05: progress = next
	else: speed = 0; blocked = true

func _batch_body() -> void:
	# Preserve the original authored model while merging its static material
	# batches. Wheels and labels keep their independent transforms.
	var batches := {}
	for child in model.get_children():
		if not child is MeshInstance3D or child.mesh == null: continue
		if child.mesh is CylinderMesh: coach_wheels.append(child); continue
		var material: Material = child.material_override
		if not batches.has(material):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[material] = surface
		for index in child.mesh.get_surface_count(): batches[material].append_from(child.mesh,index,child.transform)
		child.free()
	for material in batches:
		var mesh := MeshInstance3D.new()
		mesh.mesh = batches[material].commit()
		mesh.material_override = material
		model.add_child(mesh)
