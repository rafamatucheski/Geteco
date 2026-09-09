extends SceneTree

## Contrato de composição da V2. Não exige os módulos de Claude/Antigravity
## para que possam ser entregues em paralelo; valida a raiz, o porto preservado
## e o registro de gameplay que já existem nesta frente.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load("res://legacy/district/bairro1_v2/Bairro1V2.tscn") as PackedScene
	assert(packed_scene != null, "Bairro1V2 scene must load")
	var district := packed_scene.instantiate()
	root.add_child(district)
	for _frame in range(3):
		await process_frame

	assert(district.get_node_or_null("PortMarkedCarSet") != null, "Bairro1V2 must preserve the port")
	assert(district.get_node_or_null("GameplayV2") != null, "Bairro1V2 must load GameplayV2")
	var gameplay := district.get_node("GameplayV2")
	assert(gameplay != null, "GameplayV2 must have Bairro1V2Gameplay")
	assert(gameplay.call("get_activity_count") == 3, "Vertical slice must expose three activities")
	assert(gameplay.call("get_clue_count") == 10, "Vertical slice must expose ten clues")
	assert(gameplay.start_activity(&"market_delivery"), "Known activity must start")
	assert(gameplay.discover_clue(&"market_missing_goods"), "Known clue must be discoverable")
	assert(not gameplay.discover_clue(&"market_missing_goods"), "Clue may only be discovered once")

	print("Bairro1V2 contract passed")
	quit(0)
