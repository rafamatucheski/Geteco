extends SceneTree

const MODEL_PATHS := {
	"union_sedan": "res://prototypes/living_cast/models/UnionSedanModel.gd",
	"metro_hatch": "res://prototypes/living_cast/models/MetroHatchModel.gd",
	"courier_van": "res://prototypes/living_cast/models/CourierVanModel.gd",
	"ranch_single": "res://prototypes/living_cast/models/RanchSingleModel.gd",
	"route_city": "res://prototypes/living_cast/models/RouteCityModel.gd",
	"rescue_pumper": "res://prototypes/living_cast/models/RescuePumperModel.gd",
	"medic_box": "res://prototypes/living_cast/models/MedicBoxModel.gd",
	"towmaster": "res://prototypes/living_cast/models/TowmasterModel.gd",
	"boxrunner": "res://prototypes/living_cast/models/BoxrunnerModel.gd"
}

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		push_error("FAIL: " + msg)
		print("  [FALHA] ", msg)
	else:
		print("  [OK] ", msg)

func _run() -> void:
	print("=================================================================")
	print("=== TESTE DE VALIDAÇÃO: FASE 2 DA FROTA 3D (9 MODELOS) ===")
	print("=================================================================")

	var root_node := Node3D.new()
	root.add_child(root_node)

	for id in MODEL_PATHS:
		print("\n--- Testando modelo: ", id, " ---")
		var path: String = MODEL_PATHS[id]
		_check(ResourceLoader.exists(path), "Arquivo de script deve existir: " + path)

		var script_res = load(path)
		_check(script_res != null, "Script deve carregar com sucesso")
		if not script_res: continue

		var model = script_res.new() as Node3D
		root_node.add_child(model)

		# 1. Quantidade de malhas
		var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
		print("  Total de MeshInstance3D geradas: ", meshes.size())
		_check(meshes.size() >= 15, id + " deve ter geometria rica (>= 15 malhas, obteve " + str(meshes.size()) + ")")

		# 2. Rodas com metadados de esterçamento
		var wheels_found := 0
		for m in meshes:
			if m.has_meta("wheel_center"):
				wheels_found += 1
		print("  Peças de roda com metadados wheel_center: ", wheels_found)
		_check(wheels_found >= 4, id + " deve possuir rodas com metadados configurados (obteve " + str(wheels_found) + ")")

		# 3. Teste de dano / impacto / reparo
		model.apply_impact(Vector3(0.0, 0.5, -2.0), Vector3(0, 0, 1), 8.0)
		_check(model.impact_count > 0, id + " deve registrar impacto de colisão")
		model.repair()
		_check(model.impact_count == 0, id + " deve restaurar lataria após reparo")

		model.queue_free()

	root_node.queue_free()

	print("\n=================================================================")
	if failures.size() == 0:
		print(">>> TODOS OS 9 MODELOS 3D DA FASE 2 FORAM APROVADOS COM SUCESSO! <<<")
		quit(0)
	else:
		print(">>> ENCONTRADAS ", failures.size(), " FALHAS: <<<")
		for f in failures:
			print(" - ", f)
		quit(1)
