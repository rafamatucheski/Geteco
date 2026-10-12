extends Node3D
## Bichos do esgoto: ratos que correm pelo rodapé e baratas que disparam em arrancos. Fogem do
## jogador (que reage com um susto de verdade) e só se mexem enquanto ele está na sala: o sensor
## liga e desliga o `_process`, então sala vazia custa zero. Peças pequenas, sem sombra, sem colisão.

const RAT_SCARE := 2.4
const ROACH_SCARE := 1.7

var _half := Vector2(8, 5)
var _avoid: Array[Rect2] = []
var _rng := RandomNumberGenerator.new()
var _rats: Array[Dictionary] = []
var _roaches: Array[Dictionary] = []
var _player: Node3D
var _time := 0.0
var _fur: StandardMaterial3D
var _skin: StandardMaterial3D
var _shell: StandardMaterial3D


## `half` = meia-dimensão da sala (m); `avoid` = retângulos sólidos (caixotes, canos) onde bicho não pousa.
func configure(half: Vector2, avoid: Array, rats := -1, roaches := -1) -> void:
	_half = half
	for rect in avoid:
		_avoid.append(rect)
	_rng.seed = hash("critters_%s" % [half])
	_fur = _solid("#4a4038", 0.95)
	_skin = _solid("#b38c84", 0.8)
	_shell = _solid("#3a2412", 0.3)
	var area := half.x * half.y
	var rat_count := clampi(int(area / 45.0), 1, 5) if rats < 0 else rats
	var roach_count := clampi(int(area / 9.0), 6, 22) if roaches < 0 else roaches
	for index in rat_count:
		_spawn_rat()
	for index in roach_count:
		_spawn_roach()
	_build_sensor()
	set_process(false)


func _solid(color: String, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	return material


func _free_point(margin := 0.35) -> Vector3:
	for attempt in 12:
		var at := Vector3(_rng.randf_range(-_half.x + margin, _half.x - margin), 0.0, _rng.randf_range(-_half.y + margin, _half.y - margin))
		var blocked := false
		for rect in _avoid:
			if rect.grow(0.15).has_point(Vector2(at.x, at.z)):
				blocked = true
				break
		if not blocked:
			return at
	return Vector3(0, 0, 0)


func _wall_route() -> Array[Vector3]:
	# Ratos correm rente ao rodapé: dois pontos na mesma parede e um terceiro afastado.
	var z := -_half.y + 0.4 if _rng.randf() < 0.65 else _half.y - 0.4
	var x0 := _rng.randf_range(-_half.x + 0.8, _half.x * 0.2)
	var route: Array[Vector3] = [Vector3(x0, 0, z), Vector3(x0 + _rng.randf_range(2.5, 5.0), 0, z)]
	route.append(Vector3(route[1].x, 0, z + (1.8 if z < 0.0 else -1.8)))
	var valid: Array[Vector3] = []
	for point in route:
		var clamped := Vector3(clampf(point.x, -_half.x + 0.5, _half.x - 0.5), 0, clampf(point.z, -_half.y + 0.4, _half.y - 0.4))
		var blocked := false
		for rect in _avoid:
			if rect.grow(0.1).has_point(Vector2(clamped.x, clamped.z)):
				blocked = true
		if not blocked:
			valid.append(clamped)
	if valid.size() < 2:
		valid = [_free_point(), _free_point()]
	return valid


func _spawn_rat() -> void:
	var route := _wall_route()
	var rat := Node3D.new()
	rat.name = "Rat"
	var body := Node3D.new()
	body.name = "Body"
	rat.add_child(body)
	var torso := CapsuleMesh.new()
	torso.radius = 0.06
	torso.height = 0.26
	torso.radial_segments = 8
	torso.rings = 3
	var torso_node := _part(torso, _fur, Vector3(0, 0.06, 0))
	torso_node.rotation.x = PI * 0.5
	torso_node.scale = Vector3(1.0, 1.0, 0.8)
	body.add_child(torso_node)
	var skull := SphereMesh.new()
	skull.radius = 0.045
	skull.height = 0.08
	skull.radial_segments = 8
	skull.rings = 4
	var head := _part(skull, _fur, Vector3(0, 0.06, -0.15))
	head.scale = Vector3(0.9, 0.85, 1.3)
	body.add_child(head)
	for side in [-1, 1]:
		var ear_mesh := SphereMesh.new()
		ear_mesh.radius = 0.02
		ear_mesh.height = 0.02
		body.add_child(_part(ear_mesh, _skin, Vector3(side * 0.03, 0.1, -0.13)))
	var tail_pivot := Node3D.new()
	tail_pivot.name = "TailPivot"
	tail_pivot.position = Vector3(0, 0.04, 0.12)
	body.add_child(tail_pivot)
	var tail := CylinderMesh.new()
	tail.top_radius = 0.006
	tail.bottom_radius = 0.014
	tail.height = 0.26
	tail.radial_segments = 5
	var tail_node := _part(tail, _skin, Vector3(0, -0.015, 0.13))
	tail_node.rotation.x = PI * 0.5 - 0.15
	tail_pivot.add_child(tail_node)
	rat.position = route[0]
	add_child(rat)
	_rats.append({"node": rat, "route": route, "target": 1, "pause": _rng.randf_range(0.4, 3.0), "speed": 0.0, "phase": _rng.randf() * TAU})


func _spawn_roach() -> void:
	var roach := Node3D.new()
	roach.name = "Roach"
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.03
	body_mesh.height = 0.06
	body_mesh.radial_segments = 8
	body_mesh.rings = 4
	var body := _part(body_mesh, _shell, Vector3(0, 0.012, 0))
	body.scale = Vector3(0.7, 0.34, 1.25)
	roach.add_child(body)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.014
	head_mesh.height = 0.028
	head_mesh.radial_segments = 6
	head_mesh.rings = 3
	roach.add_child(_part(head_mesh, _shell, Vector3(0, 0.01, -0.043)))
	for side in [-1, 1]:
		var antenna := BoxMesh.new()
		antenna.size = Vector3(0.003, 0.003, 0.06)
		var node := _part(antenna, _shell, Vector3(side * 0.012, 0.016, -0.08))
		node.rotation.y = side * 0.35
		roach.add_child(node)
	roach.position = _free_point()
	roach.rotation.y = _rng.randf() * TAU
	add_child(roach)
	_roaches.append({"node": roach, "goal": roach.position, "pause": _rng.randf_range(0.2, 4.0), "moving": false, "speed": 0.0})


func _part(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _build_sensor() -> void:
	var sensor := Area3D.new()
	sensor.name = "CritterSensor"
	sensor.collision_layer = 0
	sensor.collision_mask = 2
	sensor.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_half.x * 2.0, 2.0, _half.y * 2.0)
	shape.shape = box
	shape.position = Vector3(0, 1.0, 0)
	sensor.add_child(shape)
	add_child(sensor)
	sensor.body_entered.connect(func(body: Node3D):
		if body.get_meta("gameplay_role", "") == "player":
			_player = body
			set_process(true))
	sensor.body_exited.connect(func(body: Node3D):
		if body == _player:
			_player = null
			set_process(false))


func _process(delta: float) -> void:
	_time += delta
	var player_at := Vector3.INF
	if _player != null and is_instance_valid(_player):
		player_at = to_local(_player.global_position)
	for rat in _rats:
		_update_rat(rat, delta, player_at)
	for roach in _roaches:
		_update_roach(roach, delta, player_at)


func _face(node: Node3D, direction: Vector3, rate: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	node.rotation.y = lerp_angle(node.rotation.y, atan2(-direction.x, -direction.z), clampf(rate, 0.0, 1.0))


func _update_rat(rat: Dictionary, delta: float, player_at: Vector3) -> void:
	var node: Node3D = rat.node
	var route: Array = rat.route
	var tail: Node3D = node.get_node("Body/TailPivot")
	if player_at != Vector3.INF and node.position.distance_to(player_at) < RAT_SCARE and rat.speed < 3.0:
		# Corre para o ponto da rota mais longe do jogador.
		rat.target = 0 if (route[0] as Vector3).distance_to(player_at) > (route[-1] as Vector3).distance_to(player_at) else route.size() - 1
		rat.pause = 0.0
		rat.speed = 3.8
	if rat.pause > 0.0:
		rat.pause -= delta
		tail.rotation.y = 0.35 * sin(_time * 2.2 + rat.phase)
		return
	if rat.speed <= 0.0:
		rat.speed = _rng.randf_range(1.2, 2.2)
	var goal: Vector3 = route[rat.target]
	var to_goal := goal - node.position
	var step: float = rat.speed * delta
	if to_goal.length() <= step:
		node.position = goal
		rat.speed = 0.0
		rat.pause = _rng.randf_range(0.8, 4.0)
		rat.target = _rng.randi_range(0, route.size() - 1)
		return
	var direction := to_goal.normalized()
	node.position += direction * step
	_face(node, direction, delta * 12.0)
	node.get_node("Body").position.y = absf(sin(_time * 28.0 + rat.phase)) * 0.012
	tail.rotation.y = 0.5 * sin(_time * 14.0 + rat.phase)


func _update_roach(roach: Dictionary, delta: float, player_at: Vector3) -> void:
	var node: Node3D = roach.node
	if player_at != Vector3.INF and node.position.distance_to(player_at) < ROACH_SCARE and not (roach.moving and roach.speed > 1.4):
		# Dispara para longe do jogador, em arranco.
		var away := (node.position - player_at)
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
		away = away.rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
		var target := node.position + away * _rng.randf_range(1.6, 3.2)
		roach.goal = Vector3(clampf(target.x, -_half.x + 0.3, _half.x - 0.3), 0, clampf(target.z, -_half.y + 0.3, _half.y - 0.3))
		roach.moving = true
		roach.speed = 2.2
	if not roach.moving:
		roach.pause -= delta
		if roach.pause <= 0.0:
			var target := _free_point(0.3)
			var near := node.position + Vector3(_rng.randf_range(-1.6, 1.6), 0, _rng.randf_range(-1.6, 1.6))
			roach.goal = near if _rng.randf() < 0.6 and absf(near.x) < _half.x - 0.3 and absf(near.z) < _half.y - 0.3 else target
			roach.moving = true
			roach.speed = _rng.randf_range(0.5, 1.0)
		return
	var to_goal: Vector3 = roach.goal - node.position
	var step: float = roach.speed * delta
	if to_goal.length() <= step:
		node.position = roach.goal
		roach.moving = false
		roach.pause = _rng.randf_range(0.4, 5.0)
		return
	var direction := to_goal.normalized()
	node.position += direction * step
	_face(node, direction, delta * 18.0)
