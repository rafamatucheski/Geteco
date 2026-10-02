extends CharacterBody3D
## Soldado do forte. Sentinela ou patrulheiro até perceber o jogador; depois vira
## combate tático: busca abrigo fora da linha de tiro, espia pelas pontas da cobertura
## para atirar, o flanqueador contorna pelo lado oposto e quem está ferido recua.
##
## A percepção é física (raio contra o cenário), então cobertura de verdade esconde e
## bloqueia tiro. A tática de esquadrão (abrigos, alarme, reforço) vem de FortOperation.
signal died(soldier)

const MODEL := preload("res://gameplay/PoliceModel.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const FALL := preload("res://gameplay/CharacterFallPresentation3D.gd")
const WALK_SPEED := 1.5
const RUN_SPEED := 4.2
const SIGHT_IDLE := 15.0
const SIGHT_ALERT := 24.0
const FOV_COS := 0.36
const FIRE_RANGE := 22.0
const RETREAT_FRACTION := .35

var operation
var gameplay: Node
var player: Node3D
var spec: Dictionary = {}
var role := "rifleman"
var health := 100.0
var max_health := 100.0
var dead := false
var state := "idle"
var phase := "hidden"
var awareness := 0.0
var cover: Dictionary = {}
var weapon_id := "m4a1"
var shots_fired := 0
var visual: Node3D
var last_known := Vector3.INF
var lost_time := 0.0
var _path := PackedVector3Array()
var _path_index := 0
var _repath := 0.0
var _phase_time := 0.0
var _hold := 0.0
var _burst_left := 0
var _fire_cd := 0.0
var _perceive := 0.0
var _stuck := 0.0
var _gait := 0.0
var _patrol_index := 0
var _look_clock := 0.0
var _home := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

func configure(owner_operation, definition: Dictionary) -> void:
	operation = owner_operation
	spec = definition.duplicate(true)
	name = str(spec.get("id","FortSoldier"))
	role = str(spec.get("role","rifleman"))
	max_health = 140.0 if role == "leader" else 100.0
	health = max_health
	_rng.seed = hash(name)

func _ready() -> void:
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	set_meta("gameplay_role","fort_soldier")
	add_to_group("v2_damageable")
	add_to_group("fort_soldiers")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .86
	add_child(shape)
	visual = MODEL.new()
	visual.tier = MODEL.UnitTier.ARMY
	add_child(visual)
	visual.equip(weapon_id)
	_home = global_position
	var facing: Vector3 = spec.get("facing",Vector3(0,0,1))
	visual.rotation.y = atan2(-facing.x,-facing.z)
	if spec.get("alerted",false): state = "combat"

func forward() -> Vector3:
	return -visual.global_basis.z

func eyes() -> Vector3:
	return global_position+Vector3.UP*1.55

func is_hidden_from(point: Vector3) -> bool:
	return operation.blocked(point+Vector3.UP*1.6,global_position+Vector3.UP*1.45)

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(player) or not is_instance_valid(operation): return
	if is_instance_valid(gameplay) and gameplay.get("health") != null and float(gameplay.health) <= 0.0:
		state = "idle"
		_move(Vector3.ZERO,delta)
		return
	_fire_cd = maxf(0,_fire_cd-delta)
	_phase_time += delta
	_repath -= delta
	_perceive -= delta
	var sees := false
	if _perceive <= 0:
		_perceive = .12
		sees = _sees_player()
		_update_awareness(sees,.12)
	elif state == "combat": sees = _has_los()
	match state:
		"idle": _idle(delta)
		"investigate": _investigate(delta)
		"combat": _combat(delta,sees)
	_animate(delta)

# --- Percepção ----------------------------------------------------------------

func _has_los() -> bool:
	var chest := player.global_position+Vector3.UP*1.1
	return not operation.blocked(eyes(),chest)

func _sees_player() -> bool:
	var to := player.global_position+Vector3.UP*1.1-eyes()
	var sight := SIGHT_ALERT if state == "combat" else SIGHT_IDLE
	if to.length() > sight: return false
	var flat := Vector3(to.x,0,to.z).normalized()
	if state != "combat" and flat.dot(forward()) < FOV_COS: return false
	return _has_los()

func _update_awareness(sees: bool,step: float) -> void:
	if sees:
		var distance := player.global_position.distance_to(global_position)
		awareness = minf(1.0,awareness+step*(2.4 if distance < 6.0 else 1.2 if distance < 12.0 else .7))
		last_known = player.global_position
		lost_time = 0.0
		if awareness >= 1.0 or state == "combat": operation.report_sighting(self,last_known)
		elif awareness >= .35 and state == "idle":
			state = "investigate"
			_go_to(last_known)
	else:
		awareness = maxf(0,awareness-step*.25)
		lost_time += step

func on_noise(point: Vector3,loud: bool) -> void:
	if dead or state == "combat": return
	last_known = point
	if loud:
		awareness = maxf(awareness,.6)
		state = "investigate"
		_go_to(point)

func alert(point: Vector3) -> void:
	if dead: return
	last_known = point
	awareness = 1.0
	if state != "combat":
		state = "combat"
		cover = {}
		phase = "hidden"
		_phase_time = 0.0
		_hold = _rng.randf_range(.2,.9)

# --- Comportamentos ------------------------------------------------------------

func _idle(delta: float) -> void:
	var route: Array = spec.get("route",[])
	if role == "patrol" and route.size() > 1:
		if _path.is_empty() or _path_index >= _path.size():
			_hold -= delta
			if _hold <= 0:
				_patrol_index = (_patrol_index+1)%route.size()
				_go_to(operation.to_world(route[_patrol_index]))
				_hold = 2.0
		else:
			_follow(delta,WALK_SPEED)
	else:
		# Sentinela varre o campo de visão devagar, sem sair do posto.
		_look_clock += delta
		var facing: Vector3 = spec.get("facing",Vector3(0,0,1))
		var yaw := atan2(-facing.x,-facing.z)+sin(_look_clock*.5+float(name.hash()%7))*.6
		visual.rotation.y = lerp_angle(visual.rotation.y,yaw,1-exp(-3*delta))
		_move(Vector3.ZERO,delta)

func _investigate(delta: float) -> void:
	if _path.is_empty() or _path_index >= _path.size():
		_hold -= delta
		if _hold > 0: return
		if lost_time > 4.0 and awareness < .35:
			state = "idle"
			_path = PackedVector3Array()
			if role == "patrol": _hold = 0.0
			else: _go_to(_home)
		else:
			_hold = 1.4
			visual.rotation.y += _rng.randf_range(-1.6,1.6)
		return
	_follow(delta,RUN_SPEED*.6)

func _combat(delta: float,sees: bool) -> void:
	var wounded := health <= max_health*RETREAT_FRACTION
	if sees:
		last_known = player.global_position
		lost_time = 0.0
	# Escolhe (ou refaz) o abrigo: sem abrigo, exposto a tiro ou ferido demais.
	var exposed := not cover.is_empty() and phase == "hidden" and _has_los()
	if cover.is_empty() or (exposed and _phase_time > .6):
		var mode := "retreat" if wounded else ("flank" if role == "flanker" else "hold")
		_take_cover(mode)
	if wounded and not cover.is_empty() and not cover.get("retreat",false):
		_take_cover("retreat")
	# Ciclo do abrigo: escondido → espia → esconde.
	match phase:
		"move":
			if _path.is_empty() or _path_index >= _path.size():
				phase = "hidden"
				_phase_time = 0.0
				_hold = _rng.randf_range(.8,1.8)
			else: _follow(delta,RUN_SPEED)
			_face(operation.player_point(),delta)
		"hidden":
			_move(Vector3.ZERO,delta)
			_face(operation.player_point(),delta)
			_hold -= delta
			var patience := 3.5 if wounded else 1.0
			if _hold <= 0 and (not wounded or _phase_time > patience*3.0):
				var peek := _best_peek()
				if peek.is_finite():
					phase = "peek"
					_phase_time = 0.0
					_peek_shots = 0
					_burst_left = 0
					_go_to(peek)
				else:
					# Nenhuma ponta enxerga o jogador: avança para outro abrigo mais próximo.
					if role == "flanker" or lost_time > 2.5: _take_cover("flank" if role == "flanker" else "advance")
					else: _hold = .8
		"peek":
			if not _path.is_empty() and _path_index < _path.size():
				_follow(delta,RUN_SPEED)
			else:
				_move(Vector3.ZERO,delta)
			_face(player.global_position,delta)
			if sees and global_position.distance_to(player.global_position) <= FIRE_RANGE:
				_shoot(delta)
			if (_burst_left <= 0 and _fire_cd <= 0 and _phase_time > .9 and shots_fired_in_peek() >= 3) or _phase_time > 4.2 or (not sees and _phase_time > 1.6):
				phase = "move"
				_phase_time = 0.0
				if not cover.is_empty(): _go_to(cover.hide)
	# Perdeu o jogador por muito tempo: vai até o último ponto e dá uma busca.
	if lost_time > 9.0 and not operation.alarm_active:
		state = "investigate"
		_hold = 0.0
		_go_to(last_known if last_known.is_finite() else _home)

var _peek_shots := 0
func shots_fired_in_peek() -> int:
	return _peek_shots

func _take_cover(mode: String) -> void:
	var chosen: Dictionary = operation.pick_cover(self,mode)
	if chosen.is_empty(): return
	if not cover.is_empty(): operation.release_cover(cover,self)
	cover = chosen
	cover["retreat"] = mode == "retreat"
	operation.claim_cover(cover,self)
	phase = "move"
	_phase_time = 0.0
	_peek_shots = 0
	_go_to(cover.hide)

func _best_peek() -> Vector3:
	if cover.is_empty(): return Vector3.INF
	var best := Vector3.INF
	var best_distance := INF
	var target: Vector3 = operation.player_point()
	for candidate in cover.peeks:
		if operation.blocked(candidate+Vector3.UP*1.5,target+Vector3.UP*1.1): continue
		var distance := global_position.distance_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best

# --- Tiro ----------------------------------------------------------------------

func _shoot(_delta: float) -> void:
	if _fire_cd > 0: return
	if _burst_left <= 0:
		_burst_left = _rng.randi_range(3,5)
	_burst_left -= 1
	_fire_cd = .13 if _burst_left > 0 else _rng.randf_range(.5,.9)
	shots_fired += 1
	_peek_shots += 1
	var origin: Vector3 = visual.muzzle_position()
	var end := player.global_position+Vector3.UP*1.1
	var distance := origin.distance_to(end)
	var moving := Vector2(player.velocity.x,player.velocity.z).length() > 1.0 if player is CharacterBody3D else false
	# Erra mais de longe e contra alvo em movimento; ferido atira pior.
	var chance := clampf(.66-distance*.022-(.14 if moving else 0.0)-(.12 if health < max_health*RETREAT_FRACTION else 0.0),.1,.7)
	var hit := _rng.randf() < chance
	var aim := end+(Vector3.ZERO if hit else Vector3(_rng.randf_range(-1.2,1.2),_rng.randf_range(-.5,.6),_rng.randf_range(-1.2,1.2)))
	visual.attack()
	if is_instance_valid(gameplay):
		if gameplay.has_method("_sound"): gameplay._sound(weapon_id,origin)
		if gameplay.has_method("_trace"): gameplay._trace(origin,aim,.06,.012)
		if hit and gameplay.has_method("damage_player"): gameplay.damage_player(7.0)
		if gameplay.has_signal("npc_gunfire"): gameplay.npc_gunfire.emit(origin,(aim-origin).normalized(),self)

# --- Movimento -----------------------------------------------------------------

func _go_to(point: Vector3) -> void:
	_path = operation.find_path(global_position,point)
	_path_index = 0
	_repath = 1.0

func _follow(delta: float,speed: float) -> void:
	if _path_index >= _path.size():
		_move(Vector3.ZERO,delta)
		return
	var destination := _path[_path_index]
	var direction := destination-global_position
	direction.y = 0
	if direction.length() < .35:
		_path_index += 1
		return
	var before := global_position
	_move(direction.normalized()*speed,delta)
	if Vector2(global_position.x-before.x,global_position.z-before.z).length() < delta*.1:
		_stuck += delta
		if _stuck > .8:
			_stuck = 0
			if _path.size() > 0: _go_to(_path[_path.size()-1])
	else: _stuck = 0
	if state == "idle" or state == "investigate": _face(destination,delta)

func _face(point: Vector3,delta: float) -> void:
	var aim := point-global_position
	aim.y = 0
	if aim.length_squared() > .01:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(-aim.x,-aim.z),1-exp(-9*delta))

func _move(motion: Vector3,delta: float) -> void:
	var separation: Vector3 = operation.separation(self)
	velocity.x = motion.x+separation.x
	velocity.z = motion.z+separation.z
	velocity.y = -1.0 if is_on_floor() else velocity.y-20*delta
	move_and_slide()
	_gait += Vector2(velocity.x,velocity.z).length()*delta*3.4

func _animate(delta: float) -> void:
	visual.left_upper_leg.rotation.x = sin(_gait)*.55
	visual.right_upper_leg.rotation.x = -sin(_gait)*.55
	visual.update_pose(delta,state == "combat" and phase == "peek",false,0.0,_gait)

# --- Dano ----------------------------------------------------------------------

func receive_damage(amount: float,source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0: return
	health = maxf(0,health-amount)
	if is_instance_valid(source) and source is Node3D:
		operation.report_sighting(self,(source as Node3D).global_position)
	if health > 0: return
	dead = true
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	if not cover.is_empty(): operation.release_cover(cover,self)
	var impact: Vector3 = (global_position-(source as Node3D).global_position).normalized() if source is Node3D else Vector3.ZERO
	visual.muzzle_flash_3d.hide()
	FALL.apply_fall(self,visual,impact)
	died.emit(self)
