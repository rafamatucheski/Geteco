extends SceneTree

## Galpão logístico VÉRTICE e anexo de escritório com fachada pintada (PortDepotBuilding, ligado por padrão). Confere que a pintura troca só o VISUAL: a colisão é a
## mesma do prédio de caixas, os portões 3D e a porta deslizante continuam, os vãos
## pintados coincidem com os portões, não sobra porta duplicada nem corredor escuro, e o
## cutaway esconde a pintura junto com o telhado/paredes de cima.

const BUILDING := preload("res://gameplay/urban_v1/PortDepotBuilding.gd")

var failures: Array[String] = []
var checks := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func _initialize() -> void: run.call_deferred()

func solid_ids(depot: Node3D) -> Array:
	var ids: Array = []
	for solid in depot.solids:
		ids.append("%s|%s|%s" % [solid.get_meta("interior_solid_id", ""), solid.position.snapped(Vector3.ONE * .001), solid.get_child(0).shape.size.snapped(Vector3.ONE * .001)])
	ids.sort()
	return ids

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	# Referência: prédio de caixas (GETECO_PAINTED_VERTICE=0).
	OS.set_environment("GETECO_PAINTED_VERTICE", "0")
	var plain := BUILDING.new()
	scene.add_child(plain)
	OS.set_environment("GETECO_PAINTED_VERTICE", "")
	var depot := BUILDING.new()
	depot.position = Vector3(500, 0, 0)
	scene.add_child(depot)
	for frame in 3: await physics_frame
	check(BUILDING.painted_enabled(), "ligado por padrão (sem variável)")
	check(depot._painted and not plain._painted, "GETECO_PAINTED_VERTICE=0 volta às caixas; o padrão usa a pintura")

	# Kits: um do galpão e um do anexo, no grupo que o cutaway esconde.
	var warehouse_kits := depot.find_children("PaintedFacade_galpao-vertice", "Node3D", true, false)
	var annex_kits := depot.find_children("PaintedFacade_anexo-vertice", "Node3D", true, false)
	check(warehouse_kits.size() == 1 and annex_kits.size() == 1, "um kit de galpão e um de anexo")
	check(plain.find_children("PaintedFacade_*", "Node3D", true, false).is_empty(), "prédio de caixas não monta kit")
	if warehouse_kits.size() != 1 or annex_kits.size() != 1:
		finish()
		return
	var warehouse: Node3D = warehouse_kits[0]
	var annex: Node3D = annex_kits[0]
	check(depot.facade_parts[0].is_ancestor_of(warehouse) and depot.facade_parts[0].is_ancestor_of(annex), "pintura dentro de FacadeCutaway")

	# Colisão idêntica à do prédio de caixas.
	check(solid_ids(depot) == solid_ids(plain), "mesmas colisões de arquitetura (%d x %d)" % [depot.solids.size(), plain.solids.size()])
	check(warehouse.find_children("*", "StaticBody3D", true, false).is_empty() and annex.find_children("*", "StaticBody3D", true, false).is_empty(), "kit sem colisão própria")

	# Vãos pintados = portões 3D: três baias de 8 m centradas nos portões, sem corredor.
	check(warehouse.find_children("Corridor", "MeshInstance3D", true, false).is_empty() and annex.find_children("Corridor", "MeshInstance3D", true, false).is_empty(), "sem corredor escuro do kit")
	var openings: Array = PaintedFacadeKit.openings("galpao-vertice", "front")
	check(openings.size() == 3, "três baias na frente do galpão")
	var width := 56.4 + BUILDING.PAINTED_OUT * 2.0
	for index in openings.size():
		var rect: Array = openings[index].rect
		check(not bool(openings[index].leaf), "baia %d sem folha pintada (o portão 3D é a folha)" % index)
		var center := -width * .5 + width * (float(rect[0]) + float(rect[2])) * .5
		var span := width * (float(rect[2]) - float(rect[0]))
		var dock_x: float = depot.dock_doors[index].closed_position.x
		check(absf(center - dock_x) < .06, "baia %d centrada no portão (%.3f x %.3f)" % [index, center, dock_x])
		check(absf(span - 8.0) < .1, "baia %d com 8 m (%.3f)" % [index, span])
		var height := 9.0 * (1.0 - float(rect[1]))
		check(absf(height - 5.4) < .05, "baia %d com 5,4 m de altura (%.3f)" % [index, height])
	# Sem porta pintada na frente (sem duplicata do portão); uma só porta de serviço nos fundos.
	check(warehouse.find_children("Doorway_front*", "Node3D", false, false).size() == 3, "frente: só os 3 vãos (sem folha)")
	check(warehouse.find_children("Door", "Node3D", true, false).size() == 1, "galpão: uma folha (porta de serviço dos fundos)")
	check(annex.find_children("Door", "Node3D", true, false).is_empty() and annex.find_children("Door2", "Node3D", true, false).is_empty(), "anexo: nenhuma folha pintada (a porta deslizante 3D é a porta)")
	# Porta deslizante do anexo: vão pintado de 2,4 m sobre ela.
	var office_open: Array = PaintedFacadeKit.openings("anexo-vertice", "front")
	var annex_w := 14.3 + BUILDING.PAINTED_OUT * 2.0
	check(office_open.size() == 1, "anexo: um vão de porta")
	if office_open.size() == 1:
		var r: Array = office_open[0].rect
		var c := 35.0 - annex_w * .5 + annex_w * (float(r[0]) + float(r[2])) * .5
		check(absf(c - depot.office_door.closed_position.x) < .06 and absf(annex_w * (float(r[2]) - float(r[0])) - 2.4) < .1, "vão do anexo coincide com a porta deslizante (%.3f)" % c)

	# Visual 3D antigo: sem letreiro/faixa/gavetas de telhado; marquise e canopy ficam.
	check(depot.find_children("CompanyName", "Label3D", true, false).is_empty(), "letreiro 3D escondido (a pintura já traz)")
	var roof_batches := depot.roof_parts[0].get_children().filter(func(n): return n is MeshInstance3D)
	check(roof_batches.size() <= 1, "telhado 3D sem visual (só a marquise do anexo): %d lotes" % roof_batches.size())
	var plain_roof := plain.roof_parts[0].get_children().filter(func(n): return n is MeshInstance3D)
	check(plain_roof.size() > roof_batches.size(), "prédio de caixas mantém o telhado 3D")
	check(not depot.find_children("GableCladding", "MeshInstance3D", true, false).size() > 0, "empena 3D escondida")
	check(depot.rooftop_obstacle_bounds.size() == plain.rooftop_obstacle_bounds.size(), "obstáculos do telhado de serviço iguais")

	# Portões e porta continuam animados.
	check(depot.dock_doors.size() == 3 and is_instance_valid(depot.office_door), "3 portões e a porta deslizante")
	depot.set_dock_open(1, 1.0)
	depot.set_office_open(1.0)
	check(absf(depot.dock_doors[1].position.y - 5.6) < .01, "portão sobe")
	check(absf(depot.office_door.position.x - (35.0 + 2.8)) < .01, "porta deslizante abre")
	depot.set_dock_open(1, 0.0)
	depot.set_office_open(0.0)

	# Pintura por fora das paredes 3D: galpão x +-28,2 / z -20,2..18,2 mais 5 cm de cada lado.
	var out: float = BUILDING.PAINTED_OUT
	check(absf(warehouse.position.x) < .001 and absf(warehouse.position.z + 1.0) < .001, "galpão centrado em (0,-1)")
	check(absf(annex.position.x - 35.0) < .001 and absf(annex.position.z - 15.0) < .001, "anexo centrado em (35,15)")
	check(width > 56.4 and absf(width - (56.4 + out * 2.0)) < .001, "largura do galpão = paredes + 2 x folga")
	check(absf(warehouse.position.y) < .001 and absf(annex.position.y) < .001, "pintura rente ao chão (sem afundar nem flutuar)")

	# Cutaway: a pintura some com o telhado e as paredes de cima; volta ao sair.
	depot.set_cutaway(true)
	check(not depot.facade_parts[0].visible and not depot.roof_parts[0].visible, "cutaway esconde a pintura")
	depot.set_cutaway(false)
	check(depot.facade_parts[0].visible and depot.roof_parts[0].visible, "sem cutaway a pintura aparece")

	# Interruptor geral do kit desliga.
	OS.set_environment("GETECO_PAINTED_FACADES", "0")
	check(not BUILDING.painted_enabled(), "GETECO_PAINTED_FACADES=0 desliga a pintura")
	OS.set_environment("GETECO_PAINTED_FACADES", "")
	OS.set_environment("GETECO_PAINTED_VERTICE", "")
	finish()

func finish() -> void:
	print("painted vertice: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
