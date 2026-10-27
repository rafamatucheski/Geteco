extends RefCounted
## One-shot cleanup, owned by the destroyed node and paused with gameplay.
const DELAY := 4.0
const DURATION := 1.2

## Destroço de adereço que encolhe em vez de ficar transparente (25/10, sem ganho provado). `transparency` > 0 leva cada material ×
## formato do adereço ao passe alfa, e essas pipelines (`draw`) compilam na hora do desenho: a sonda de
## assinatura pegou a placa da 3ª onda (wave3_sinal.glb) derrubada no estresse num quadro de 864 ms (9ª rodada,
## doc §14). Corpos seguem com transparência (pré-aquecidos em SpawnVisualPrewarm). DESLIGADO por padrão
## (GETECO_DEBRIS_SHRINK=1 liga): no A/B da 10ª rodada o quadro de ~0,9 s apareceu igual nos dois lados (1 de 2
## frios cada, 902 × 900 ms), então o destroço não é a causa provada.
static var shrink_enabled := OS.get_environment("GETECO_DEBRIS_SHRINK") == "1"

static func schedule(body: Node3D, delay := DELAY, by_scale := false) -> void:
	if not is_instance_valid(body) or body.has_meta("destroyed_cleanup"): return
	body.set_meta("destroyed_cleanup", true)
	var timer := body.create_tween()
	timer.tween_interval(delay)
	timer.tween_callback(func(): fade(body, by_scale))

static func fade(body: Node3D, by_scale := false) -> void:
	if not is_instance_valid(body) or body.has_meta("destroyed_fading"): return
	body.set_meta("destroyed_fading", true)
	preload("res://runtime/PipelineProbe.gd").note("fade_scale" if by_scale and shrink_enabled else "fade_transparency", body)
	var meshes: Array[GeometryInstance3D] = []
	var initial: Array[float] = []
	var pending: Array[Node] = [body]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is GeometryInstance3D:
			meshes.append(node)
			initial.append(node.transparency)
		if node is CollisionObject3D:
			node.collision_layer = 0
			node.collision_mask = 0
		if node is RigidBody3D: node.freeze = true
		for child in node.get_children(): pending.append(child)
	var tween := body.create_tween()
	if by_scale and shrink_enabled:
		var scales: Array[Vector3] = []
		for mesh in meshes: scales.append(mesh.scale)
		# Até 1 %, não zero: base singular gera erro em quem ainda ler a transformação no último quadro.
		tween.tween_method(func(amount: float):
			for i in meshes.size():
				if is_instance_valid(meshes[i]): meshes[i].scale = scales[i] * lerpf(1.0, 0.01, amount)
		, 0.0, 1.0, DURATION)
		tween.tween_callback(body.queue_free)
		return
	tween.tween_method(func(amount: float):
		for i in meshes.size():
			if is_instance_valid(meshes[i]): meshes[i].transparency = lerpf(initial[i], 1.0, amount)
	, 0.0, 1.0, DURATION)
	tween.tween_callback(body.queue_free)
