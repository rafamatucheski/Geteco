extends Node
## Apresentação do bueiro do porto: Dante anda até a borda, a tampa desliza, ele entra no poço e
## desce a escada (e o caminho inverso na saída). O jogo só fazia a tampa fechar e o véu preto;
## a descida existia no V1. Não decide nada de jogo: `FullSession` espera o fim e segue com a troca de lugar.
##
## Pelo mesmo motivo do `VehicleBoardingPresentation`, o corpo é posto à mão a cada quadro e o
## processamento de física do Actor fica parado enquanto dura (sem gravidade no poço sem piso).

const WALK_SECONDS := 0.55
const OPEN_SECONDS := 0.70
const STEP_SECONDS := 0.30
const GRAB_SECONDS := 0.35
## Profundidade percorrida pela escada (`HarborManholeExterior3D`: 17 degraus de 0,10 m) e velocidade.
const DEPTH := 1.55
const LADDER_SPEED := 0.80
## Ladrilho da escada fica em z = 0; o corpo se apoia a este recuo para encarar os degraus (-Z).
const LADDER_STAND := 0.25
const EDGE_STAND := 0.95
const DESCEND_CLIP := "ladder/Ladder_Descend"
const CLIMB_CLIP := "Fast_Ladder_Climb"

var actor: CharacterBody3D
var hatch: Node3D
var _still_valid: Callable
var _start_yaw := 0.0

func setup(player: CharacterBody3D, sewer_hatch: Node3D, still_valid: Callable) -> void:
	actor = player
	hatch = sewer_hatch
	_still_valid = still_valid

func _center() -> Vector3: return hatch.global_position

## A estrutura pode ter sido girada no editor do mundo: tudo (borda, escada, sentido de entrada) segue a base dela.
func _yaw() -> float: return hatch.global_rotation.y

func _at(center: Vector3, y: float, offset: Vector3) -> Vector3:
	var point := center + Basis(Vector3.UP, _yaw()) * offset
	point.y = y
	return point

func _hold(point: Vector3, yaw: float) -> void:
	actor.global_position = point
	actor.visual.rotation.y = yaw

func _approach(point: Vector3, yaw: float) -> bool:
	var motion := point - actor.global_position
	motion.y = 0
	actor.move_and_collide(motion)
	actor.visual.rotation.y = yaw
	return Vector2(actor.global_position.x-point.x, actor.global_position.z-point.z).length() < .08

func _stand(center: Vector3, y: float) -> Vector3:
	return _at(center, y, _info().get("ladder_stand", Vector3(0, 0, LADDER_STAND)))

func _idle() -> void:
	actor._apply_pose(actor._idle_pose)

## O ciclo do clipe de escada não fecha (o último quadro difere do primeiro em ~20°, medido em
## `tools/capture_ladder_stage.gd`): nos últimos `SEAM_BLEND` segundos mistura com o início para
## a repetição não dar um tranco a cada 0,83 s.
const SEAM_BLEND := 0.18
func _ladder_pose(clip: String, seconds: float) -> void:
	var length: float = actor.animation.get_animation(clip).length
	var t := fposmod(seconds, length)
	actor._pose_clip(clip, t)
	if t > length - SEAM_BLEND:
		var current: Array = actor._capture_pose()
		actor._pose_clip(clip, 0.0)
		actor._apply_blend(current, actor._capture_pose(), smoothstep(length - SEAM_BLEND, length, t))
	if is_instance_valid(hatch) and hatch.has_method("ladder_handhold"):
		for side in ["Left", "Right"]:
			var grip: Vector3 = hatch.ladder_handhold(actor._clip_palm(side))
			actor._solve_combat_arm(side, actor.visual.to_local(grip), actor.combat_realized_palm_basis(side), true, 1.0 if side == "Right" else -1.0)

## Estilo da entrada, lido da tampa/porta: "ladder" (padrão, bueiros e poços: escada vertical) ou "walk"
## (galeria de estrada e adega: anda para dentro, descendo `drop` ao longo de `length`). Vem de `hatch.descent`.
func _info() -> Dictionary:
	var info: Variant = hatch.get("descent") if is_instance_valid(hatch) else null
	return info if info is Dictionary else {}

func _walks() -> bool:
	return str(_info().get("style", "ladder")) == "walk"

## Anda até a borda, abre a tampa e desce. Devolve falso se a transição deixou de ser dona do jogador.
func descend() -> bool:
	if _walks(): return await _walk_descend()
	return await _ladder_descend()

func _ladder_descend() -> bool:
	if not _prepare(): return false
	var c := _center()
	var p0: Vector3 = actor.global_position
	var edge := _at(c, p0.y, Vector3(0, 0, EDGE_STAND))
	var yaw_walk := atan2(-(edge.x - p0.x), -(edge.z - p0.z)) if Vector2(edge.x - p0.x, edge.z - p0.z).length() > 0.05 else 0.0
	var clock := 0.0
	while clock < WALK_SECONDS:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, clampf(clock / WALK_SECONDS, 0.0, 1.0))
		if not _approach(p0.lerp(edge, k), lerp_angle(yaw_walk, _yaw(), smoothstep(0.6, 1.0, k))): return _abort()
		actor._pose_cycle("Walking", fposmod(k * 0.9, 1.0), actor.WALK_START)
	clock = 0.0
	while clock < OPEN_SECONDS:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		hatch.set_open_amount(clampf(clock / OPEN_SECONDS, 0.0, 1.0))
		_hold(edge, _yaw())
		_idle()
	var stand := _stand(c, p0.y)
	clock = 0.0
	while clock < STEP_SECONDS:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, clampf(clock / STEP_SECONDS, 0.0, 1.0))
		if not _approach(edge.lerp(stand, k), _yaw()): return _abort()
		actor._pose_cycle("Walking", fposmod(k * 0.5, 1.0), actor.WALK_START)
	# Reach the authored ladder, take hold, then lower the body vertically.
	var walking_pose: Array = actor._capture_pose()
	_ladder_pose(DESCEND_CLIP, 0.0)
	var gripping_pose: Array = actor._capture_pose()
	clock = 0.0
	while clock < GRAB_SECONDS:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		_hold(stand, _yaw())
		actor._apply_blend(walking_pose, gripping_pose, smoothstep(0.0, GRAB_SECONDS, clock))
	var seconds := DEPTH / LADDER_SPEED
	clock = 0.0
	while clock < seconds:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		var depth := DEPTH * clampf(clock / seconds, 0.0, 1.0)
		_hold(stand + Vector3.DOWN * depth, _yaw())
		_ladder_pose(DESCEND_CLIP, clock)
	_finish()
	return true

## Põe Dante no fundo do poço com a tampa aberta, antes do véu abrir (a saída revela o poço, não a rua).
func prepare_exit() -> void:
	if _walks():
		_prepare_walk_exit()
		return
	if not _prepare(): return
	var c := _center()
	hatch.set_open_amount(1.0)
	_hold(_stand(c, c.y - DEPTH), _yaw())
	_ladder_pose(CLIMB_CLIP, 0.0)

## Sobe a escada, sai do poço até `landing` e devolve o controle.
func ascend(landing: Vector3) -> bool:
	if _walks(): return await _walk_ascend(landing)
	var c := _center()
	var bottom := _stand(c, c.y - DEPTH)
	var seconds := DEPTH / LADDER_SPEED
	var clock := 0.0
	while clock < seconds:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		_hold(bottom + Vector3.UP * (DEPTH * clampf(clock / seconds, 0.0, 1.0)), _yaw())
		_ladder_pose(CLIMB_CLIP, clock)
	var top := _stand(c, c.y)
	var out := Vector3(landing.x, c.y, landing.z) if Vector2(landing.x - c.x, landing.z - c.z).length() < 4.0 else _at(c, c.y, Vector3(0, 0, EDGE_STAND))
	var yaw := atan2(-(out.x - top.x), -(out.z - top.z))
	clock = 0.0
	while clock < WALK_SECONDS:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, clampf(clock / WALK_SECONDS, 0.0, 1.0))
		_hold(top.lerp(out, k), yaw)
		actor._pose_cycle("Walking", fposmod(k * 0.9, 1.0), actor.WALK_START)
	_finish()
	return true

func can_run() -> bool:
	if not (is_instance_valid(actor) and is_instance_valid(hatch) and "animation" in actor and actor.animation != null): return false
	if _walks(): return actor.animation.has_animation("Walking")
	return actor.animation.has_animation(DESCEND_CLIP) and actor.animation.has_animation(CLIMB_CLIP)

func _prepare() -> bool:
	if not can_run(): return false
	_start_yaw = actor.visual.rotation.y
	actor.set_physics_process(false)
	return true

func _alive() -> bool:
	return is_instance_valid(actor) and is_instance_valid(hatch) and _still_valid.call()

func _abort() -> bool:
	_finish()
	return false

func _finish() -> void:
	if is_instance_valid(actor): actor.set_physics_process(true)

# --- Estilo "walk": a entrada é um caminho para dentro (galeria, adega), não uma escada. ---
const WALK_SPEED := 1.7

func _walk_inner(c: Vector3, y: float) -> Vector3:
	var info := _info()
	return _at(c, y - float(info.get("drop", 0.0)), Vector3(0, 0, -float(info.get("length", 3.0))))

func _walk_descend() -> bool:
	if not _prepare(): return false
	var c := _center()
	var info := _info()
	var p0: Vector3 = actor.global_position
	var approach := _at(c, p0.y, Vector3(0, 0, float(info.get("approach", 1.8))))
	# A pushed culvert gate is already open and the player has crossed it.
	# Continue from that threshold instead of walking backwards and reopening.
	var pushed_culvert := str(hatch.get("site_id")) == "desert_under_culvert" and float(hatch.get("open_amount")) >= .85
	if pushed_culvert: approach = p0
	var yaw_walk := atan2(-(approach.x - p0.x), -(approach.z - p0.z)) if Vector2(approach.x - p0.x, approach.z - p0.z).length() > 0.05 else _yaw()
	var clock := 0.0
	while clock < WALK_SECONDS:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, clampf(clock / WALK_SECONDS, 0.0, 1.0))
		_hold(p0.lerp(approach, k), lerp_angle(yaw_walk, _yaw(), smoothstep(0.6, 1.0, k)))
		actor._pose_cycle("Walking", fposmod(k * 0.9, 1.0), actor.WALK_START)
	if hatch.has_method("set_open_amount") and bool(info.get("doors", true)) and not pushed_culvert:
		clock = 0.0
		while clock < OPEN_SECONDS:
			await get_tree().process_frame
			if not _alive(): return _abort()
			clock += get_process_delta_time()
			hatch.set_open_amount(clampf(clock / OPEN_SECONDS, 0.0, 1.0))
			_hold(approach, _yaw())
			_idle()
	var inner := _walk_inner(c, p0.y)
	var seconds := approach.distance_to(inner) / WALK_SPEED
	clock = 0.0
	while clock < seconds:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		var k := clampf(clock / seconds, 0.0, 1.0)
		_hold(approach.lerp(inner, k), _yaw())
		actor._pose_cycle("Walking", fposmod(clock * 1.1, 1.0), actor.WALK_START)
	_finish()
	return true

func _prepare_walk_exit() -> void:
	if not _prepare(): return
	var c := _center()
	if hatch.has_method("set_open_amount"): hatch.set_open_amount(1.0)
	_hold(_walk_inner(c, c.y), _yaw() + PI)
	_idle()

func _walk_ascend(landing: Vector3) -> bool:
	var c := _center()
	var info := _info()
	var inner := _walk_inner(c, c.y)
	var out := _at(c, c.y, Vector3(0, 0, float(info.get("approach", 1.8))))
	var seconds := inner.distance_to(out) / WALK_SPEED
	var clock := 0.0
	while clock < seconds:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		_hold(inner.lerp(out, clampf(clock / seconds, 0.0, 1.0)), _yaw() + PI)
		actor._pose_cycle("Walking", fposmod(clock * 1.1, 1.0), actor.WALK_START)
	var target := Vector3(landing.x, c.y, landing.z) if Vector2(landing.x - c.x, landing.z - c.z).length() < 4.0 else out
	var yaw := atan2(-(target.x - out.x), -(target.z - out.z)) if Vector2(target.x - out.x, target.z - out.z).length() > 0.05 else PI
	clock = 0.0
	while clock < 0.4:
		await get_tree().process_frame
		if not _alive(): return _abort()
		clock += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, clampf(clock / 0.4, 0.0, 1.0))
		_hold(out.lerp(target, k), yaw)
		actor._pose_cycle("Walking", fposmod(k * 0.9, 1.0), actor.WALK_START)
	_finish()
	return true
