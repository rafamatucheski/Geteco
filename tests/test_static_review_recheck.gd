extends SceneTree
## Contratos das correções da releitura das revisões estáticas (docs/reviews/static-review-recheck-20261031.md).
## Não mede custo: só confere que os guardas novos recusam/recuam como planejado.

const ARRIVAL := preload("res://runtime/Arrival.gd")
const HEAT := preload("res://runtime/cold/HeatPresentation.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# LIFE-04: o desembarque antigo não pode retomar depois que a chegada saiu da árvore
	# ou teve a geração trocada.
	var arrival = ARRIVAL.new()
	arrival.active = true
	arrival.phase = "disembark"
	var generation: int = arrival._generation
	check(not arrival._disembark_current(generation), "desembarque fora da árvore é descartado")
	root.add_child(arrival)
	arrival._generation += 1
	check(not arrival._disembark_current(generation), "desembarque de geração antiga é descartado")
	arrival.phase = "terminal_meeting"
	check(not arrival._disembark_current(arrival._generation), "desembarque fora da fase é descartado")
	arrival.free()

	# Custo: apresentação térmica desabilitada não monta nada (e não consulta o grupo).
	var heat = HEAT.new()
	root.add_child(heat)
	var provider := Node3D.new()
	provider.add_to_group("native_heat_source")
	root.add_child(provider)
	heat.update_sources(1.0, Vector3.ZERO, false)
	check(heat.visuals.is_empty(), "fontes térmicas desabilitadas ficam vazias")
	heat.free()
	provider.free()

	print("static_review_recheck: %s" % ("OK" if failures == 0 else "%d falhas" % failures))
	quit(0 if failures == 0 else 1)
