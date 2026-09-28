extends SceneTree
## Reação ao tiro do civil: o tronco inclina no sentido do projétil, soma a rajada
## sem reiniciar (sem tremer), respeita o teto e volta ao repouso.
const CIVILIAN := preload("res://assets/CivilianModel.gd")
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var model := CIVILIAN.new()
	model.lod_enabled = false
	root.add_child(model)
	for i in 5: await process_frame
	var rest: float = model.spine.rotation.x
	# Tiro vindo de trás do civil (projétil viaja na frente dele, +Z do modelo).
	var travel: Vector3 = model.global_basis * Vector3(0, 0, 1)
	var samples: Array[float] = []
	var direction_changes := 0
	var last_delta := 0.0
	var swing_from := 0.0
	for frame in 150:
		if frame % 6 == 0 and frame < 36: model.take_hit(travel, 0.8)
		model._process(1.0 / 60.0)
		var lean: float = model._hit.x
		samples.append(lean)
		if frame > 0:
			var d := lean - samples[frame - 1]
			# Conta só inversões visíveis: recuo de mais de 0,5° depois de um avanço.
			if signf(d) != signf(last_delta) and absf(lean - swing_from) > 0.009: direction_changes += 1; swing_from = lean; last_delta = d
			elif signf(d) == signf(last_delta): swing_from = lean if absf(lean) > absf(swing_from) or signf(d) < 0 else swing_from
			if last_delta == 0.0: last_delta = d
	var peak := 0.0
	for value in samples: peak = maxf(peak, value)
	print("HIT_REACTION peak=%.3f rad inversões=%d final=%.4f" % [peak, direction_changes, samples[-1]])
	check(peak > 0.15, "Tronco inclina de forma visível com a rajada")
	check(peak <= model.HIT_MAX + 0.001, "Inclinação respeita o teto")
	check(samples[5] > 0.0, "Inclina para o lado do projétil")
	# A rajada de 6 tiros a 10/s não pode virar vibração: poucas inversões de sentido.
	check(direction_changes <= 2, "Rajada não vibra (inversões: %d)" % direction_changes)
	check(absf(samples[-1]) < 0.01, "Volta ao repouso")
	check(absf(model.spine.rotation.x - rest) < 0.05, "Pose do tronco volta à original")
	# Tiro lateral: rolagem, não inclinação frontal.
	model.take_hit(model.global_basis * Vector3(1, 0, 0), 1.0)
	for i in 6: model._process(1.0 / 60.0)
	check(absf(model._hit.y) > absf(model._hit.x) * 3.0, "Tiro lateral inclina para o lado")
	print("HIT_REACTION failures=", failures)
	quit(0 if failures.is_empty() else 1)
