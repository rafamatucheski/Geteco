extends SceneTree

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("=================================================================")
	print("=== TESTE: PASSAGEM LIVRE SOB OS PREDIOS E FADE DE TRANSPARENCIA =")
	print("=================================================================")

	var b_script = load("res://geodata/ProceduralBuilding.gd")
	var building: ProceduralBuilding = b_script.new()
	building.footprint = Vector2(180, 254)
	building.position = Vector2(1380, 1035)
	building.arcade_depth = 74.0
	building.building_kind = "brownstone"
	root.add_child(building)
	await process_frame

	# 1. Testar se a colisão foi recuada para liberar a calçada/pista
	var col_rect = building.get_collision_rect()
	print("[PASSO 1] Testando colisao do predio com arcade_depth...")
	print("  Tamanho da colisao: ", col_rect.size)
	print("  Fim em Y da colisao: ", col_rect.end.y)
	assert(col_rect.size.y <= (254.0 - 74.0 + 2.0), "A colisao deve ser menor que a footprint pelo arcade_depth")
	assert(col_rect.end.y <= 1090.0, "A colisao do predio nao pode invadir a pista/calcada em Y > 1090")
	print("  ✓ Colisao liberou 100% da calcada e da pista (Y=1090..1162 livre!)")

	# 2. Testar deteccao e fade de transparencia quando o Player passa por baixo
	print("[PASSO 2] Testando passagem do Player por baixo do predio...")
	var player = CharacterBody2D.new()
	player.set_script(load("res://Player.gd"))
	player.position = Vector2(1380, 1130) # Exatamente embaixo do predio na calcada/rua
	root.add_child(player)
	await process_frame
	await process_frame
	
	# Simular deteccao na Area2D do predio
	var pass_area = building.get_node_or_null("PassThroughArea") as Area2D
	assert(pass_area != null, "Predio deve ter PassThroughArea")
	building._on_pass_through_body_entered(player)
	
	# Aguardar tween
	var timer = create_timer(0.25)
	await timer.timeout
	print("  ✓ Modulate alfa do predio com player embaixo: %.2f" % building.modulate.a)
	assert(building.modulate.a < 0.50, "Predio deve ficar translucido (alfa ~0.35) quando o jogador passa por baixo")

	# 3. Testar restauracao do alfa ao sair de baixo do predio
	print("[PASSO 3] Testando saida do Player de baixo do predio...")
	building._on_pass_through_body_exited(player)
	var timer2 = create_timer(0.25)
	await timer2.timeout
	print("  ✓ Modulate alfa do predio apos saida do player: %.2f" % building.modulate.a)
	assert(building.modulate.a > 0.95, "Predio deve voltar a 1.0 quando o jogador sai de baixo")

	print("=================================================================")
	print("=== SUCESSO: TESTE DE PASSAGEM SOB PREDIOS APROVADO! (EXIT 0) ===")
	print("=================================================================")
	quit(0)
