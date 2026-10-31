extends RefCounted
## Dono único do pulo, travessia de telhados, dano de queda e recuperação.
## A cápsula nativa continua varrida contra as paredes/telhado reais o tempo todo.
const GRAVITY := 20.0
const JUMP_SPEED := 6.7
const VAULT_SPEED := 8.0
const SAFE_DROP := 2.5
const DAMAGE_PER_METRE := 12.0
var actor: CharacterBody3D
var phase := "ground"
var age := 0.0
var peak := 0.0
var last_drop := 0.0
var landings := 0
var requested := false
var roof: Node3D
var edge_direction := Vector3.ZERO
var edge_age := 0.0
var vaulting := false
var grip_done := false
var roof_height := 0.0
var low_roof := false

func configure(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor
	peak = actor.global_position.y

func reset() -> void:
	phase = "ground"
	age = 0.0
	requested = false
	vaulting = false
	grip_done = false
	edge_age = 0.0
	roof = null
	peak = actor.global_position.y
	actor.set_meta("player_air_busy", false)

func request_jump() -> bool:
	if not available() or phase != "ground" or not actor.is_on_floor(): return false
	requested = true
	return true

func available() -> bool:
	return not actor.dead and not actor.input_locked and not actor.get_meta("developer_free_flight", false) and not actor.has_meta("street_pose_owned") and not (is_instance_valid(actor.ski_controller) and actor.ski_controller.skiing)

func before_move(delta: float, direction: Vector3) -> void:
	age += delta
	if not available():
		requested = false
		actor.velocity.y = 0.0 if actor.is_on_floor() else actor.velocity.y - GRAVITY * delta
		return
	if phase in ["land", "recover"]:
		actor.velocity.x = 0.0
		actor.velocity.z = 0.0
		actor.velocity.y = 0.0 if actor.is_on_floor() else actor.velocity.y - GRAVITY * delta
		if age >= (1.35 if phase == "recover" else .28):
			phase = "ground"
			age = 0.0
			actor.set_meta("player_air_busy", false)
		return
	if phase == "grip":
		actor.velocity = Vector3.ZERO
		if age >= .24:
			phase = "fall"
			age = 0.0
		return
	if phase == "ground" and actor.is_on_floor():
		peak = actor.global_position.y
		_try_roof_edge(delta, direction)
		if requested:
			requested = false
			phase = "jump"
			age = 0.0
			actor.velocity.y = VAULT_SPEED if vaulting else JUMP_SPEED
			actor.set_meta("player_air_busy", true)
		else:
			actor.velocity.y = 0.0
			return
	else:
		actor.velocity.y -= GRAVITY * delta
	if vaulting:
		var exit_speed := 3.4
		if low_roof and not grip_done and is_instance_valid(roof):
			var edge_local: Vector3 = roof.to_local(actor.global_position)
			var edge_half: Vector2 = roof.definition.size * .5
			var outside := maxf(absf(edge_local.x)-edge_half.x, absf(edge_local.z)-edge_half.y)
			if outside > .38:
				# Algumas fachadas originais têm cornija fora da laje nova do telhado.
				# Continua se movendo até a cápsula varrida inteira passar dela. Agarrar só
				# é possível ao alcance do braço do parapeito físico.
				var descent := maxf(.02, actor.global_position.y - roof_height + .5)
				if not actor.test_move(actor.global_transform,Vector3.DOWN*descent):
					if outside <= .58: exit_speed = 0.0
					else: grip_done = true
		actor.velocity.x = edge_direction.x * exit_speed
		actor.velocity.z = edge_direction.z * exit_speed
	if actor.velocity.y <= 0.0 and phase == "jump":
		phase = "fall"
		age = 0.0
	# Agarra ao descer fora da laje, com as mãos na altura do parapeito.
	if phase == "fall" and vaulting and low_roof and not grip_done and is_instance_valid(roof) and actor.global_position.y < roof_height - .42:
		var local: Vector3 = roof.to_local(actor.global_position)
		var half: Vector2 = roof.definition.size * .5
		if absf(local.x) > half.x + .30 or absf(local.z) > half.y + .30:
			grip_done = true
			phase = "grip"
			age = 0.0
			actor.velocity = Vector3.ZERO

func _try_roof_edge(delta: float, direction: Vector3) -> void:
	if not is_instance_valid(roof) or direction.length_squared() < .01:
		edge_age = 0.0
		return
	var point: Vector3 = roof.to_local(actor.global_position)
	var half: Vector2 = roof.definition.size * .5
	var local_direction: Vector3 = roof.global_basis.inverse() * direction.normalized()
	var outward := Vector3.ZERO
	if point.z > half.y - .85 and local_direction.z > .65: outward = Vector3.BACK
	elif point.z < -half.y + .85 and local_direction.z < -.65: outward = Vector3.FORWARD
	elif point.x > half.x - .85 and local_direction.x > .65: outward = Vector3.RIGHT
	elif point.x < -half.x + .85 and local_direction.x < -.65: outward = Vector3.LEFT
	if outward.is_zero_approx():
		edge_age = 0.0
		return
	edge_age += delta
	if edge_age < .15 and not requested: return
	# A swept upward body test rejects an overhang; no rail or wall is disabled.
	if actor.test_move(actor.global_transform, Vector3.UP * 1.65): return
	vaulting = true
	grip_done = false
	edge_direction = (roof.global_basis * outward).normalized()
	roof_height = roof.global_position.y
	low_roof = int(roof.definition.get("floor_count", 1)) <= 1 and float(roof.definition.get("roof_height", 4.0)) <= 5.5
	requested = true

func after_move() -> void:
	if not available(): return
	if phase == "ground" and not actor.is_on_floor():
		# Admission teleports leave a small floor clearance. Do not turn that
		# settling step into Jump/Jump_Land; actual drops still own their pose.
		if actor.velocity.y > -2.0 and peak - actor.global_position.y < .3:
			var support := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP*.05, actor.global_position - Vector3.UP*.3, 1)
			support.exclude = [actor.get_rid()]
			var ground: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(support)
			if not ground.is_empty() and ground.normal.y > .7:
				peak = actor.global_position.y
				return
		phase = "fall"
		age = 0.0
		actor.set_meta("player_air_busy", true)
	peak = maxf(peak, actor.global_position.y)
	if phase in ["jump", "fall"] and actor.is_on_floor():
		_land()

func _land() -> void:
	last_drop = maxf(0.0, peak - actor.global_position.y)
	landings += 1
	vaulting = false
	grip_done = false
	edge_age = 0.0
	phase = "recover" if last_drop > SAFE_DROP else "land"
	age = 0.0
	var gameplay = actor.get_parent().get("gameplay")
	if gameplay != null and last_drop > SAFE_DROP:
		var damage := (last_drop - SAFE_DROP) * DAMAGE_PER_METRE
		# O dono do telhado libera o interior ao sair da área dele, antes de
		# aterrissar. O dano é aplicado uma vez aqui, nunca de novo por nenhum dos donos do telhado.
		gameplay.damage_environment(damage)
		if is_instance_valid(gameplay.effects):
			gameplay.effects.impact(actor.global_position + Vector3.UP * .04, Vector3.UP, "concrete", damage)
			if gameplay.health <= 0.0:
				gameplay.effects.blood(actor.global_position + Vector3.UP * .2, Vector3.UP, 100.0)
				gameplay.effects.stain(actor.global_position, .85)
		if gameplay.health <= 0.0:
			actor.present_fall_death()
			phase = "dead"

func pose() -> bool:
	if phase == "ground" or phase == "dead" or not available(): return false
	match phase:
		"jump": actor._pose_clip("ual/Jump_Start", minf(age * 2.0, .85))
		"fall":
			actor._pose_clip("ual/Jump", 1.1)
			_freefall_pose()
		"grip":
			actor._pose_clip("ual/Jump", .65)
			_grip_pose()
		"land": actor._pose_clip("ual/Jump_Land", minf(age * 3.8, 1.2))
		"recover": actor._pose_clip("ual/Jump_Land", minf(age * .9, 1.2))
	return true

func _freefall_pose() -> void:
	var spread := smoothstep(.0, .35, age)
	_bone("LeftArm", Vector3(.0, .0, -.65) * spread)
	_bone("RightArm", Vector3(.0, .0, .65) * spread)
	_bone("LeftForeArm", Vector3(-.35, .0, .0) * spread)
	_bone("RightForeArm", Vector3(-.35, .0, .0) * spread)
	_bone("Spine01", Vector3(.15, .0, .0) * spread)

func _grip_pose() -> void:
	if not is_instance_valid(roof): return
	var local: Vector3 = roof.to_local(actor.global_position)
	var half: Vector2 = roof.definition.size * .5
	var rail := roof.to_global(Vector3(clampf(local.x,-half.x+.12,half.x-.12),1.04,clampf(local.z,-half.y+.12,half.y-.12)))
	var across := edge_direction.cross(Vector3.UP).normalized()
	var palms: Basis = actor.visual.global_basis.orthonormalized().inverse() * Basis.looking_at(-edge_direction,Vector3.UP)
	for side in ["Left", "Right"]:
		var sign_side := -1.0 if side == "Left" else 1.0
		actor._solve_combat_arm(side, actor.visual.to_local(rail + across * sign_side * .20), palms, true, sign_side)
	actor._set_combat_grips(true,true)

func _bone(name: String, rotation: Vector3) -> void:
	if not is_instance_valid(actor.skeleton): return
	var index: int = actor.skeleton.find_bone(name)
	if index >= 0:
		actor.skeleton.set_bone_pose_rotation(index, actor.skeleton.get_bone_pose_rotation(index) * Quaternion.from_euler(rotation))
