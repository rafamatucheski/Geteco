extends CharacterBody3D
## Lightweight tunnel wildlife. It follows authored points and only simulates
## while the secret tunnel is occupied; no navigation map or per-frame raycasts.

var route: Array[Vector3] = []
var player: Node3D
var route_index := 0
var speed := 1.15
var active := false
var _pause := 0.0

func configure(points: Array[Vector3], target: Node3D, phase := 0) -> void:
	route = points
	player = target
	route_index = posmod(phase, maxi(1, route.size()))
	_build_model()
	set_active(false)

func set_active(value: bool) -> void:
	active = value
	visible = value
	set_physics_process(value and not route.is_empty())
	velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if not active or route.is_empty(): return
	_pause = maxf(0.0, _pause-delta)
	var destination := route[route_index]
	if is_instance_valid(player) and global_position.distance_squared_to(player.global_position) < 6.25:
		var away := global_position-player.global_position
		away.y = 0.0
		if away.length_squared() > .01: destination = global_position+away.normalized()*3.0
	var offset := destination-global_position
	offset.y = 0.0
	if offset.length() < .22:
		route_index = (route_index+1)%route.size()
		_pause = .35
		velocity = Vector3.ZERO
		return
	if _pause > 0.0: return
	velocity = offset.normalized()*speed
	look_at(global_position+velocity, Vector3.UP)
	move_and_slide()

func _build_model() -> void:
	name = "TunnelRat"
	collision_layer = 0
	collision_mask = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("3a332d")
	material.roughness = .94
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = .13
	body_mesh.height = .24
	body.mesh = body_mesh
	body.scale = Vector3(1.15,.72,1.65)
	body.position = Vector3(0,.13,0)
	body.material_override = material
	add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = .085
	head_mesh.height = .16
	head.mesh = head_mesh
	head.position = Vector3(0,.14,-.20)
	head.material_override = material
	add_child(head)
	for side in [-1.0,1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := SphereMesh.new()
		ear_mesh.radius = .035
		ear_mesh.height = .025
		ear.mesh = ear_mesh
		ear.position = Vector3(side*.065,.225,-.16)
		ear.material_override = material
		add_child(ear)
	var tail := MeshInstance3D.new()
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = .012
	tail_mesh.bottom_radius = .018
	tail_mesh.height = .36
	tail_mesh.radial_segments = 7
	tail.mesh = tail_mesh
	tail.position = Vector3(0,.10,.29)
	tail.rotation.x = PI*.5
	tail.material_override = material
	add_child(tail)
	var shape := CapsuleShape3D.new()
	shape.radius = .12
	shape.height = .28
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = .13
	add_child(collider)
