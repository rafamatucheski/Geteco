extends Node3D
## Um peixe reaproveitável atravessa a água, a margem e o arco de pouso sem interrupção.
const RULES := preload("res://activities/fishing/FishingRules.gd")
const FISH := preload("res://activities/fishing/FishingFishModel.gd")
const MOTION := preload("res://activities/fishing/FishingMotion.gd")
const RELEASE_DURATION := 2.6
const STORE_DURATION := .9
var _segments: Array[MeshInstance3D] = []
var _line: MeshInstance3D
var _float: MeshInstance3D
var _reel: MeshInstance3D
var _handle: MeshInstance3D
var _fish: Node3D
var _ripple: MeshInstance3D
var _wake: MeshInstance3D
var _drops: Array[MeshInstance3D] = []
var _age := 0.0
var _phase := ""
var _phase_age := 0.0
var _fish_initialized := false
var _landing_start := Vector3.ZERO
var _landing_basis := Basis.IDENTITY
var _splash_at := Vector3.ZERO
var _splash_age := 2.0
var _last_jump := false
var _disposition_start := Vector3.ZERO
var _disposition_start_basis := Basis.IDENTITY
var _disposition_position := Vector3.ZERO
var _disposition_basis := Basis.IDENTITY
var _disposition_hands := 0.0
var _release_splashed := false
var water_surface: Node3D
var _buoyancy := 0.0
var _buoyancy_speed := 0.0
var right_grip := Vector3(.17, 1.02, -.33)
var left_grip := Vector3(-.02, .98, -.43)

func _ready() -> void:
	var carbon := _material(Color("35434a"))
	var cork := _material(Color("b69667"))
	for i in 9:
		var mesh := CylinderMesh.new()
		mesh.top_radius = .018 if i == 0 else maxf(.004, .014 - i * .0012)
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 1.0
		mesh.radial_segments = 6
		_segments.append(_mesh(mesh, cork if i == 0 else carbon))
	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = .004
	line_mesh.bottom_radius = .004
	line_mesh.height = 1.0
	line_mesh.radial_segments = 3
	_line = _mesh(line_mesh, _material(Color("d9e2d3")))
	_float = _mesh(_sphere(.065), _material(Color("ec6c43")))
	_float.scale = Vector3(.7, 1.5, .7)
	_reel = _mesh(_sphere(.075), carbon)
	_reel.scale = Vector3(1, .65, 1)
	_handle = _mesh(_sphere(.027), cork)
	var ring := TorusMesh.new()
	ring.inner_radius = .975
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 4
	var foam := _material(Color("708d82"))
	foam.roughness = 1.0
	foam.metallic_specular = 0.0
	_ripple = _mesh(ring, foam)
	_wake = _mesh(ring, foam)
	for index in 8:
		var drop := _mesh(_sphere(.025), foam)
		drop.hide()
		_drops.append(drop)
	_fish = FISH.new()
	_fish.name = "HookedFish"
	add_child(_fish)
	_fish.hide()

func present(actor, target: Vector3, phase: String, tension: float, progress: float, charge: float, fish: Dictionary, delta: float, hint := "steady", held := false, phase_time := -1.0) -> void:
	_age += delta
	if phase != _phase:
		_phase = phase
		_phase_age = 0.0
		if phase == "casting": _fish_initialized = false
		if phase == "landing" and _fish_initialized:
			_landing_start = _fish.global_position
			_landing_basis = _fish.global_basis.orthonormalized()
		if phase in ["releasing", "storing"] and _fish_initialized:
			_disposition_start = _fish.global_position
			_disposition_start_basis = _fish.global_basis.orthonormalized()
			_release_splashed = false
		if phase in ["waiting", "hooking", "landing"]: _splash(target if phase == "waiting" else _fish.global_position)
	else: _phase_age += delta
	if phase_time >= 0.0: _phase_age = phase_time
	var direction: Vector3 = target - actor.global_position
	direction.y = 0
	direction = direction.normalized()
	var right := direction.cross(Vector3.UP)
	if not fish.is_empty(): _fish.configure(RULES.definition(str(fish.get("id", "tilapia"))), int(fish.get("grams", 2500)))
	var pose := MOTION.pose(phase, _phase_age, charge, tension, held, _age)
	var disposition := phase in ["releasing", "storing"]
	var support := _capture_support(fish) if (phase in ["landing", "caught"] or disposition) and not fish.is_empty() else {}
	if not support.is_empty() and not disposition:
		var handoff := smoothstep(.60, 1.0, _phase_age / 1.9) if phase == "landing" else 1.0
		pose.right = (pose.right as Vector3).lerp(support.right, handoff)
		pose.left = (pose.left as Vector3).lerp(support.left, handoff)
		if handoff > .8:
			pose.right_grip = false
			pose.left_grip = false
	if disposition and not support.is_empty():
		_update_disposition(actor, target, direction, right, phase, support)
		var palm_right: Vector3 = actor.visual.to_local(_disposition_position + _disposition_basis * (support.head_anchor as Vector3))
		var palm_left: Vector3 = actor.visual.to_local(_disposition_position + _disposition_basis * (support.tail_anchor as Vector3))
		pose.right = (pose.right as Vector3).lerp(palm_right, _disposition_hands)
		pose.left = (pose.left as Vector3).lerp(palm_left, _disposition_hands)
	right_grip = pose.right
	left_grip = pose.left
	actor.set_combat_weapon_pose("fishing", pose)
	actor._apply_combat_weapon_pose()
	var grip: Vector3 = actor.visual.to_global(right_grip)
	if actor.skeleton != null: grip = actor.combat_palm_position("Right")
	var parked := smoothstep(.60, 1.0, _phase_age / 1.9) if phase == "landing" else (1.0 if phase == "caught" or disposition else 0.0)
	# Passa a vara para o lado enquanto a mão livre segura a captura.
	grip = grip.lerp(actor.visual.to_global(Vector3(.60, .03, -.12)), parked)
	var pitch := float(pose.pitch)
	var previous := grip - direction * .18
	for i in _segments.size():
		var t := float(i + 1) / float(_segments.size())
		var reach := t * 2.5
		var bend := tension * pow(t, 2.3) * .65 if phase in ["reeling", "hooking"] else 0.0
		var point := grip + direction * (reach * cos(pitch) + bend) + Vector3.UP * (reach * sin(pitch) - bend)
		_between(_segments[i], previous, point)
		previous = point
	_reel.global_position = grip + Vector3.DOWN * .07
	_handle.global_position = _reel.global_position - right * .095 + direction * sin(_age * 10.0) * (.032 if held else 0.0)
	var bobber := target + Vector3.UP * (.045 + sin(_age * 3.0) * .012)
	if phase == "casting":
		var cast := clampf(_phase_age / .72, 0.0, 1.0)
		bobber = previous.lerp(target, cast) + Vector3.UP * sin(cast * PI) * 1.5
	if phase == "bite": bobber.y -= .07 + sin(_age * 20.0) * .04
	var swimming := phase in ["waiting", "bite", "hooking", "reeling"]
	var landing := phase == "landing"
	var escaping := phase in ["missed", "line_broke"] and _phase_age < .8 and _fish_initialized
	var disposing_visible := (phase == "releasing" and _phase_age < RELEASE_DURATION) or (phase == "storing" and _phase_age < STORE_DURATION)
	_fish.visible = (swimming or landing or phase == "caught" or escaping or disposing_visible) and not fish.is_empty()
	if _fish.visible:
		var desired := target + Vector3.DOWN * .16
		if phase == "waiting":
			desired += direction * (.55 + sin(_age * .8) * .35) + right * cos(_age * .9) * .46
		elif phase in ["bite", "hooking"]:
			desired += right * sin(_age * 4.0) * .12
		elif phase == "reeling":
			# Mantém até o bagre mais longo longe do parapeito antes da subida vertical.
			var bank: Vector3 = actor.global_position + direction * 3.10
			bank.y = target.y - .12
			desired = desired.lerp(bank, progress)
			var run := hint == "run"
			var sway := sin(_age * (5.0 if run else 2.4))
			desired += right * sway * (.30 + (1.0 - progress) * (.65 if run else .26))
			var jump := 0.0
			# Cada corrida tem uma arrancada visível. O peixe continua sendo o mesmo nó de apresentação física.
			if run: jump = maxf(0.0, sin(_age * 4.0))
			desired.y += jump * .78
			if _last_jump and jump < .12: _splash(_fish.global_position)
			_last_jump = jump > .12
		elif landing or phase == "caught":
			var finish: Vector3 = actor.visual.to_global(support.center)
			var amount := smoothstep(0.0, 1.0, _phase_age / 1.9) if landing else 1.0
			# Sobe na vertical ainda sobre a água e depois cruza o parapeito de 1.04 m.
			var raised := Vector3(_landing_start.x, maxf(actor.global_position.y + 1.72, _landing_start.y), _landing_start.z)
			if amount < .42: desired = _landing_start.lerp(raised, smoothstep(0.0, .42, amount))
			else: desired = raised.lerp(finish, smoothstep(.42, 1.0, amount))
			var held_basis := Basis.looking_at(right, Vector3.UP)
			_fish.global_basis = _landing_basis.slerp(held_basis, amount)
		elif disposition:
			desired = _disposition_position
			_fish.global_basis = _disposition_basis
		elif escaping:
			desired = _fish.global_position + direction * delta * 2.0 + Vector3.DOWN * delta * .5
		var old_position := _fish.global_position
		if not _fish_initialized or landing or phase == "caught" or disposition: _fish.global_position = desired
		else: _fish.global_position = old_position.lerp(desired, 1.0 - exp(-delta * (9.0 if phase == "reeling" else 4.0)))
		if not landing and phase != "caught" and not disposition:
			var travel := _fish.global_position - old_position if _fish_initialized else -direction
			var horizontal := Vector2(travel.x, travel.z).length()
			# Mantém a direção bem definida enquanto o peixe salta na vertical.
			travel.y = clampf(travel.y, -horizontal * .7, horizontal * .7)
			if travel.length_squared() > .00001:
				var heading := Basis.looking_at(travel.normalized(), Vector3.UP)
				_fish.global_basis = _fish.global_basis.orthonormalized().slerp(heading, 1.0 - exp(-delta * 7.0))
		_fish_initialized = true
		var effort := (1.55 if hint == "run" else (.85 if held else .45)) if phase == "reeling" else (.26 if phase in ["caught", "storing"] else .6)
		if phase == "releasing" and _phase_age >= 1.55: effort = 1.15
		_fish.animate(delta, effort)
		if phase in ["reeling", "hooking"]: bobber = Vector3(_fish.global_position.x, target.y + .035, _fish.global_position.z)
	var floating := phase in ["waiting", "bite", "hooking", "reeling", "casting"]
	# Uma boia amortecida segue o mesmo campo guiado pela chuva que deforma o lago.
	var water_offset := 0.0
	if is_instance_valid(water_surface):
		water_offset = water_surface.rain_surface_height_at(bobber) - target.y
	var buoyancy_delta := minf(delta, 1.0 / 30.0)
	_buoyancy_speed += ((water_offset - _buoyancy) * 90.0 - _buoyancy_speed * 15.0) * buoyancy_delta
	_buoyancy += _buoyancy_speed * buoyancy_delta
	if floating and phase != "casting": bobber.y += _buoyancy
	_float.visible = floating
	_ripple.visible = floating and phase != "casting"
	_wake.visible = (swimming or (phase == "releasing" and _phase_age >= 1.55 and _phase_age < RELEASE_DURATION)) and _fish_initialized
	_line.visible = floating or landing
	_float.global_position = bobber
	_ripple.global_position = Vector3(bobber.x, target.y + water_offset + .025, bobber.z)
	var ripple_size := .08 + fmod(_age * .16, .26)
	_ripple.scale = Vector3(ripple_size, .005, ripple_size)
	if _wake.visible:
		_wake.global_position = Vector3(_fish.global_position.x, target.y + .029, _fish.global_position.z)
		if is_instance_valid(water_surface): _wake.global_position.y = water_surface.rain_surface_height_at(_fish.global_position) + .029
		var wake_size := .14 + fmod(_age * .25, .40)
		_wake.scale = Vector3(wake_size, .005, wake_size * .66)
	if _line.visible:
		var end: Vector3 = _fish.mouth_global_position() if phase in ["hooking", "reeling", "landing"] and _fish.visible else bobber
		_between(_line, previous, end)
	_update_splash(delta, target.y)

func _capture_support(fish: Dictionary) -> Dictionary:
	var profile: Dictionary = FISH.PROFILES.get(str(fish.get("id", "piau")), FISH.PROFILES.piau)
	var body_scale: float = _fish._rig.scale.y
	# A 68 cm à frente o IK saturava o alcance do braço e deixava as duas palmas acima
	# da barriga. 46 cm mantém a captura longe do tronco e ao alcance do braço dobrado.
	var center := Vector3(0, 1.10 + float(profile.depth) * body_scale + .015, -.46)
	# Duas posições longitudinais escritas sob a barriga, escaladas pelo espécime
	# real. Um espaçamento fixo de 40 cm entre as mãos erraria a barriga de um Piau pequeno.
	var head_z := -.18
	var tail_z := .10
	var head_radius: float = FISH._radii(profile, (head_z + .5) / .9).y * body_scale
	var tail_radius: float = FISH._radii(profile, (tail_z + .5) / .9).y * body_scale
	return {"center":center,
		"right":center + Vector3(-head_z * body_scale, -head_radius - .012, 0),
		"left":center + Vector3(-tail_z * body_scale, -tail_radius - .012, 0),
		"head_anchor":Vector3(0, -head_radius - .012, head_z * body_scale),
		"tail_anchor":Vector3(0, -tail_radius - .012, tail_z * body_scale)}

func _update_disposition(actor, target: Vector3, direction: Vector3, right: Vector3, phase: String, support: Dictionary) -> void:
	if phase == "storing":
		var halfway: Vector3 = actor.visual.to_global(Vector3(-.40, 1.12, -.10))
		var pocket: Vector3 = actor.visual.to_global(Vector3(-.38, 1.03, .18))
		if _phase_age < .45: _disposition_position = _disposition_start.lerp(halfway, smoothstep(0.0, .45, _phase_age))
		else: _disposition_position = halfway.lerp(pocket, smoothstep(.45, STORE_DURATION, _phase_age))
		_disposition_basis = _disposition_start_basis.slerp(Basis.looking_at(Vector3.UP, -direction), smoothstep(0.0, STORE_DURATION, _phase_age))
		_disposition_hands = 1.0
		return
	var lift: Vector3 = actor.visual.to_global((support.center as Vector3) + Vector3(0, .48, -.08))
	var entry: Vector3 = actor.global_position + direction * 3.10
	entry.y = _surface_height(entry, target.y) - .10
	var above_water := Vector3(entry.x, maxf(lift.y, actor.global_position.y + 1.85), entry.z)
	var swim_basis := Basis.looking_at(direction, Vector3.UP)
	_disposition_hands = 1.0 - smoothstep(.55, .78, _phase_age)
	if _phase_age < .55:
		_disposition_position = _disposition_start.lerp(lift, smoothstep(0.0, .55, _phase_age))
		_disposition_basis = _disposition_start_basis
	elif _phase_age < 1.15:
		var arc := smoothstep(.55, 1.15, _phase_age)
		# Cruza o parapeito inteiro no alto antes de descer; até a cauda mais longa
		# fica acima da barreira de 1.04 m em vez de passar pelas tábuas.
		_disposition_position = lift.lerp(above_water, arc) + Vector3.UP * sin(arc * PI) * .15
		_disposition_basis = _disposition_start_basis.slerp(swim_basis, arc)
	elif _phase_age < 1.55:
		_disposition_position = above_water.lerp(entry, smoothstep(1.15, 1.55, _phase_age))
		_disposition_basis = swim_basis
	else:
		if not _release_splashed:
			_splash(Vector3(entry.x, _surface_height(entry, target.y), entry.z))
			_release_splashed = true
		var swim := smoothstep(1.55, RELEASE_DURATION, _phase_age)
		_disposition_position = entry + direction * swim * 1.55 + right * sin(swim * PI) * .14
		_disposition_position.y = _surface_height(_disposition_position, target.y) - .10 - swim * .38
		_disposition_basis = Basis.looking_at(direction + right * cos(swim * PI) * .12, Vector3.UP)

func _surface_height(point: Vector3, fallback: float) -> float:
	if is_instance_valid(water_surface):
		var height: float = water_surface.rain_surface_height_at(point)
		if is_finite(height): return height
	return fallback

func _splash(point: Vector3) -> void:
	_splash_at = point
	_splash_age = 0.0

func _update_splash(delta: float, water_y: float) -> void:
	_splash_age += delta
	if _splash_age < .55: water_y = _surface_height(_splash_at, water_y)
	for index in _drops.size():
		var drop := _drops[index]
		drop.visible = _splash_age < .55
		if not drop.visible: continue
		var angle := float(index) * TAU / float(_drops.size())
		var speed := .65 + float(index % 3) * .18
		var height := maxf(0.0, (1.7 + float(index % 2) * .3) * _splash_age - 3.7 * _splash_age * _splash_age)
		drop.global_position = Vector3(_splash_at.x, water_y, _splash_at.z) + Vector3(cos(angle), 0, sin(angle)) * _splash_age * speed + Vector3.UP * height
		drop.scale = Vector3(.7, 1.6, .7) * (1.0 - _splash_age)

func _between(node: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var direction := b - a
	if direction.length_squared() < .000001: return
	node.global_position = (a + b) * .5
	var y_axis := direction.normalized()
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() < .0001: x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	# Scale the cylinder's local Y column; Basis.scaled() stretches world rows
	# and made diagonal rod/line pieces miss their endpoints.
	node.global_basis = Basis(x_axis, y_axis * direction.length(), x_axis.cross(y_axis))

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .68
	return material

func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node
