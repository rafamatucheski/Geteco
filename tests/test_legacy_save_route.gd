extends SceneTree

## Guarda de regressão da compatibilidade com saves antigos.
##
## HarborSceneRoute.for_save() escolhe entre o jogo atual e a geração anterior
## conforme o save: quem não tem a flag "harbor_campaign_active" vai para
## Main.tscn, que continua sendo carregado em runtime. Quando Main.tscn e os
## distritos antigos foram para legacy/ (2026-09-09), nada garantia que essa
## rota ainda funcionasse -- este teste passa a garantir.
##
## Não basta checar a string do caminho: o teste instancia a cena legada de
## verdade, porque caminho certo com cena que não carrega quebra igual.
##
## Uso: Godot..._console.exe --path . --script res://tests/test_legacy_save_route.gd

const ROUTE := preload("res://world/harbor/HarborSceneRoute.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []

	# 1. Save antigo (sem a flag) tem que ser roteado para a geração anterior.
	var old_save := {"campaign": {"campaign_flags": {}}}
	var old_route: String = ROUTE.for_save(old_save)
	if old_route != "res://legacy/Main.tscn":
		failures.append("Save antigo deveria ir para res://legacy/Main.tscn, foi para '%s'" % old_route)

	# 2. Save novo (com a flag) tem que ir para o jogo atual.
	var new_save := {"campaign": {"campaign_flags": {"harbor_campaign_active": true}}}
	var new_route: String = ROUTE.for_save(new_save)
	if new_route != "res://world/harbor/HarborGame.tscn":
		failures.append("Save novo deveria ir para res://world/harbor/HarborGame.tscn, foi para '%s'" % new_route)

	# 3. Save na montanha vai para o jogo atual mesmo sem a flag de campanha.
	var mountain_save := {"world": {"region": "mountain"}, "campaign": {"campaign_flags": {}}}
	var mountain_route: String = ROUTE.for_save(mountain_save)
	if mountain_route != "res://world/harbor/HarborGame.tscn":
		failures.append("Save na montanha deveria ir para o jogo atual, foi para '%s'" % mountain_route)

	# 4. A cena legada tem que carregar de verdade, não só existir o caminho.
	if not ResourceLoader.exists(old_route):
		failures.append("A cena legada '%s' não existe" % old_route)
	else:
		var packed := load(old_route) as PackedScene
		if packed == null:
			failures.append("load('%s') devolveu null" % old_route)
		else:
			var scene := packed.instantiate()
			if scene == null:
				failures.append("instantiate() da cena legada devolveu null")
			else:
				root.add_child(scene)
				# current_scene precisa ser definido: vários scripts do mundo
				# fazem get_tree().current_scene.add_child(...) para efeitos
				# (Puddle, ChopShopZone) e estouram com ele nulo.
				current_scene = scene
				for i in 30:
					await process_frame
				var children := scene.get_child_count()
				if children == 0:
					failures.append("A cena legada instanciou vazia (0 filhos)")
				print("LEGACY_SAVE_ROUTE cena legada carregada com %d filhos diretos" % children)
				scene.queue_free()
				await process_frame

	if failures.is_empty():
		print("LEGACY_SAVE_ROUTE_RESULT failures=0; rota legada e rota atual OK")
		quit(0)
	else:
		for f in failures:
			print("  FALHA: " + f)
		print("LEGACY_SAVE_ROUTE_RESULT failures=%d" % failures.size())
		quit(1)
