extends RefCounted
## Levantar do chão com os clipes do Mixamo (mocap; `tools/retarget_mixamo_vehicle_clips.gd`) sobre o rig
## articulado de `assets/CivilianModel.gd`. Antes (até 28/10) o corpo deitado só desgirava de volta à pose
## de pé em 0,9 s, pivotando no quadril: lia como alguém içado por um guindaste ("arrastado para cima").
##
## Quem caiu de costas usa "Getting Up From Back" (rola, apoia o braço, ajoelha e sobe); de bruços,
## "Getting Up From Stomach" ou "Getting Up Knocked Down" (flexão, joelho, de pé). Sem a biblioteca ou sem
## alguma junta, `begin` devolve false e `BodyFlight3D` segue o levantar antigo. GETECO_MOCAP_GETUP=0 também.
const LIBRARY := "res://assets/dante/mixamo/npc_vehicle.res"
const MIXAMO_DEATH := preload("res://gameplay/MixamoDeath.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Da pose em que o corpo pousou para o primeiro quadro do clipe (ainda deitado).
const SETTLE_SECONDS := 0.45
## Uma tentativa que falha: o corpo sobe até os braços/joelho e desaba de volta antes de conseguir.
## Só quem se machucou (vida abaixo de FAIL_HEALTH) e só de bruços, onde o desabar é a flexão cedendo.
const FAIL_HEALTH := 75.0
const FAIL_CHANCE := 0.55
static var enabled := OS.get_environment("GETECO_MOCAP_GETUP") != "0"
static var _library: AnimationLibrary
static var _requested := false

var actor: Node3D
var visual: Node3D
var joints: Dictionary = {}
var clip: Animation
var clip_name := ""
var rotations: Dictionary = {}
var position_track := -1
var time := 0.0
var speed := 1.0
var finished := false
var attempt_only := false
var _start: Dictionary = {}
var _start_position := Vector3.ZERO
var _settle := 0.0
var _settle_seconds := SETTLE_SECONDS
## Tempo do clipe em que o corpo já está de pé (ver `_standing_time`).
var _end := 0.0
## Tentativa frustrada: sobe até `_fail_peak` (s do clipe), desaba até `_fail_floor` e espera `_fail_rest`.
var _fail_peak := -1.0
var _fail_floor := 0.0
var _fail_rest := 0.0
var _failing := 0
## Quem tinha `_process` ligado antes do levantar (o modelo do civil anda sozinho quando liga).
var _processing: Dictionary = {}

static func prewarm() -> void:
	if not enabled or _library != null or _requested or not ResourceLoader.exists(LIBRARY): return
	_requested = ResourceLoader.load_threaded_request(LIBRARY, "AnimationLibrary") == OK

## Mesmo contrato de `MixamoDeath.library`: depois do `prewarm` nunca espera a leitura.
static func library() -> AnimationLibrary:
	if not enabled or _library != null or not ResourceLoader.exists(LIBRARY): return _library
	if _requested:
		var status := ResourceLoader.load_threaded_get_status(LIBRARY)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return null
		_requested = false
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_library = ResourceLoader.load_threaded_get(LIBRARY) as AnimationLibrary
			return _library
	var began := STALL_WORK.begin()
	_library = load(LIBRARY) as AnimationLibrary
	STALL_WORK.finish_slow("gameplay.mocap_getup_library", began, 2000)
	return _library

## Escolhe o clipe pela posição em que o corpo ficou e alinha o primeiro quadro (deitado) ao corpo:
## a cabeça do clipe aponta para onde a cabeça caiu e a pelve do clipe fica sobre a pelve do corpo.
## `attempt_only`: só a tentativa que falha (senta ou faz a flexão e desaba); o corpo continua no chão.
func begin(p_actor: Node3D, p_visual: Node3D, health := 100.0, p_attempt_only := false) -> bool:
	attempt_only = p_attempt_only
	var lib := library()
	if lib == null or not is_instance_valid(p_actor) or not is_instance_valid(p_visual): return false
	actor = p_actor
	visual = p_visual
	joints = MIXAMO_DEATH.joints_of(visual)
	if joints.is_empty(): return false
	var pelvis: Node3D = joints["Pelvis"]
	var spine: Node3D = joints["Spine"]
	var head: Node3D = joints["Head"]
	var frame := pelvis.get_parent() as Node3D
	if frame == null: return false
	# Frente do peito (+Z do rig) para cima = de costas. De bruços só há um clipe (flexão, quatro apoios,
	# joelho, de pé). De costas: machucado senta devagar, vira de lado e sobe ("Injury Level" 53); inteiro
	# apoia nas mãos atrás e levanta num impulso (2,7 s).
	var chest_front := spine.global_basis.orthonormalized().z
	var supine := chest_front.y > 0.0
	clip_name = "getup_stomach"
	if supine: clip_name = "getup_back" if attempt_only or health < FAIL_HEALTH or randf() < 0.35 else "getup_knocked"
	if not lib.has_animation(clip_name): return false
	clip = lib.get_animation(clip_name)
	rotations.clear()
	position_track = -1
	for track in clip.get_track_count():
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D: rotations[String(clip.track_get_path(track))] = track
		elif clip.track_get_type(track) == Animation.TYPE_POSITION_3D: position_track = track
	if position_track < 0 or not rotations.has("Pelvis") or not rotations.has("Spine"): return false
	# O clipe de costas foi baixado com "Injury Level" 53: é longo (~10 s) e sofrido; um pouco mais rápido.
	speed = 1.25 if clip_name == "getup_back" else 1.0
	_end = _standing_time(clip)
	# "Knocked" começa meio sentado (tronco apoiado nas mãos): a passagem do corpo estendido até ali é mais longa.
	_settle_seconds = 0.8 if clip_name == "getup_knocked" else SETTLE_SECONDS
	var head_now := head.global_position - pelvis.global_position
	head_now.y = 0.0
	var pelvis_now := pelvis.global_position
	var saved := {}
	for joint_name in joints: saved[joint_name] = (joints[joint_name] as Node3D).global_transform
	# Guinada que leva a cabeça do primeiro quadro do clipe à cabeça caída. O visual volta a ficar em pé
	# (o voo varrido deixava o visual inteiro deitado) e só a pelve guarda a inclinação do corpo.
	var clip_pelvis := Basis(clip.rotation_track_interpolate(rotations["Pelvis"], 0.0))
	var clip_head: Vector3 = clip_pelvis * Basis(clip.rotation_track_interpolate(rotations["Spine"], 0.0)) * Vector3.UP
	var upright := Basis(Vector3.UP, visual.global_rotation.y)
	var frame_upright: Basis = upright * (visual.global_basis.orthonormalized().inverse() * frame.global_basis.orthonormalized())
	var clip_head_world := frame_upright * clip_head
	clip_head_world.y = 0.0
	var turn := 0.0
	if clip_head_world.length_squared() > 0.0001 and head_now.length_squared() > 0.0001:
		turn = clip_head_world.normalized().signed_angle_to(head_now.normalized(), Vector3.UP)
	var scale := visual.global_basis.get_scale()
	visual.global_basis = (Basis(Vector3.UP, turn) * upright).scaled(scale)
	# Pelve do clipe sobre a pelve do corpo, no plano: o resto do deslocamento vem do próprio clipe.
	var clip_pelvis_world := frame.to_global(clip.position_track_interpolate(position_track, 0.0))
	var shift := pelvis_now - clip_pelvis_world
	shift.y = 0.0
	visual.global_position += shift
	for joint_name in joints:
		var node: Node3D = joints[joint_name]
		var node_scale := node.global_basis.get_scale()
		var kept: Transform3D = saved[joint_name]
		node.global_transform = Transform3D(kept.basis.orthonormalized().scaled(node_scale), kept.origin)
		_start[joint_name] = node.quaternion
	_start_position = pelvis.position
	for model in [frame, visual]:
		_processing[model] = model.is_processing()
		model.set_process(false)
	time = 0.0
	_settle = 0.0
	_failing = 0
	_fail_peak = -1.0
	if clip_name != "getup_knocked" and (attempt_only or (health < FAIL_HEALTH and randf() < FAIL_CHANCE)):
		# De bruços sobe até os braços estendidos (~40 %); de costas senta (~43 %). Desaba de volta quase ao
		# chão e, se não for só a tentativa, tenta de novo até conseguir.
		_fail_peak = clip.length * (randf_range(0.34, 0.44) if clip_name == "getup_stomach" else randf_range(0.40, 0.47))
		_fail_floor = clip.length * (0.06 if clip_name == "getup_stomach" else 0.12)
		_fail_rest = randf_range(0.7, 1.3)
		_failing = 1
	_apply(0.0)
	return true

## Os clipes terminam com 2–3 s de pé parado: o levantar acaba quando a pelve chegou à altura final
## (dentro de 3 cm) E o tronco já está em pé (eixo do peito a menos de ~16° da vertical), mais 0,2 s; o
## modelo do civil retoma dali sem endireitar o tronco num quadro (test_body_ragdoll, 28/10).
static func _standing_time(animation: Animation) -> float:
	var track := animation.find_track(NodePath("Pelvis"), Animation.TYPE_POSITION_3D)
	var pelvis := animation.find_track(NodePath("Pelvis"), Animation.TYPE_ROTATION_3D)
	var spine := animation.find_track(NodePath("Spine"), Animation.TYPE_ROTATION_3D)
	if track < 0: return animation.length
	var final_y: float = animation.position_track_interpolate(track, animation.length).y
	var time := animation.length
	while time > 0.0:
		var level := absf(animation.position_track_interpolate(track, time).y - final_y) < 0.03
		var upright := true
		if pelvis >= 0 and spine >= 0:
			var chest: Vector3 = Basis(animation.rotation_track_interpolate(pelvis, time)) * Basis(animation.rotation_track_interpolate(spine, time)) * Vector3.UP
			upright = chest.normalized().y > 0.96
		if not (level and upright): break
		time -= 0.05
	return minf(animation.length, time + 0.2)

## Avança o levantar; devolve true quando o clipe terminou (o corpo está de pé).
func step(delta: float) -> bool:
	if finished or clip == null: return true
	if _settle < _settle_seconds:
		_settle += delta
		_apply(smoothstep(0.0, 1.0, _settle / _settle_seconds))
		return false
	match _failing:
		1:
			time = minf(time + delta * speed, _fail_peak)
			if time >= _fail_peak: _failing = 2
		2:
			# O braço cede: volta ao chão mais rápido do que subiu.
			time = maxf(time - delta * 2.6, _fail_floor)
			if time <= _fail_floor: _failing = 3
		3:
			_fail_rest -= delta
			if _fail_rest <= 0.0:
				if attempt_only:
					finished = true
					return true
				_failing = 0
		_:
			time = minf(time + delta * speed, _end)
	_apply(1.0)
	finished = _failing == 0 and time >= _end
	return finished

func _apply(blend: float) -> void:
	for joint_name in rotations:
		var node: Node3D = joints.get(joint_name)
		if not is_instance_valid(node): continue
		var target: Quaternion = clip.rotation_track_interpolate(rotations[joint_name], time)
		node.quaternion = (_start.get(joint_name, target) as Quaternion).slerp(target, blend)
	var pelvis: Node3D = joints.get("Pelvis")
	if is_instance_valid(pelvis):
		pelvis.position = _start_position.lerp(clip.position_track_interpolate(position_track, time), blend)

## De pé: a origem do corpo vai para baixo da pelve, o visual volta à base olhando para a frente final do
## clipe e as juntas voltam ao repouso do rig. Devolve a guinada final (convenção de `visual.rotation.y`).
func finish(base: Transform3D) -> float:
	var pelvis: Node3D = joints.get("Pelvis")
	var facing_yaw := visual.global_rotation.y
	if is_instance_valid(pelvis):
		var front := pelvis.global_basis.orthonormalized().z
		front.y = 0.0
		# O modelo do civil é girado 180° dentro do visual: a frente dele (+Z) é o -Z do visual.
		if front.length_squared() > 0.0001: facing_yaw = atan2(-front.x, -front.z)
		var ground := pelvis.global_position
		ground.y = actor.global_position.y
		var world_shift := ground - (actor.global_transform * base).origin
		world_shift.y = 0.0
		actor.global_position += world_shift
	visual.transform = Transform3D(Basis(Vector3.UP, facing_yaw - actor.global_rotation.y).scaled(base.basis.get_scale()), base.origin)
	return facing_yaw

## Devolve o `_process` de quem foi parado (morto continua parado: a queda da morte é dona das juntas).
func release() -> void:
	var dead: bool = is_instance_valid(actor) and actor.get("dead") == true
	for model in _processing:
		if is_instance_valid(model) and not dead: (model as Node).set_process(bool(_processing[model]))
	_processing.clear()
