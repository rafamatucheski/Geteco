extends "res://tests/test_bank_heist_flow.gd"

const EVIDENCE := "res://docs/measurements/bank-loot-0910/"

func capture(label: String) -> void:
	var room=current_scene.get_node("Interiors/InteriorSpaces/BankInterior")
	var player=current_scene.get_node("Player")
	if label=="01_entrada":
		check(room.remaining_loot()==10000,"Cofre começa com dez mil disponíveis")
		var labels=room.view.find_children("*","Label3D",true,false)
		check(labels.all(func(item): return not "CAIXA" in item.text),"Placas numeradas de caixa removidas")
		for clerk in room.civilians:
			var meshes=clerk.model.find_children("*","MeshInstance3D",true,false)
			check(meshes.all(func(item): return not item.material_override is ShaderMaterial),"Atendente inteiro sem corte de pernas por shader")
			check(absf(clerk.position.x)<absf(room.project_floor(Vector2(3.2,-1.9)).x)-10,"Atendente na lateral livre do balcão")
		var wallet: int=player.money
		var origin: Vector2=player.global_position
		player.global_position=room.to_global(room.loot_positions[0])
		room._tick_vault(2,true)
		check(player.money==wallet and room.remaining_loot()==10000,"Não recolhe dinheiro com cofre fechado")
		player.global_position=origin
	if label in ["01_entrada","02_advertencia"]:
		var guard=room.guards[1]
		var rig=guard.get_node("NPCCombatRig")
		for i in 8: await physics_frame
		var grip: Vector3=rig.weapon_mount_node.to_global(Vector3(-.055,-.01,.018))
		check(guard.left_lower_arm.get_node("Palm").global_position.distance_to(grip)<.012,"Mão de apoio do segundo guarda toca a pistola: "+label)
		check(guard.right_lower_arm.get_node("Palm").global_position.distance_to(rig.weapon_mount_node.global_position)<.001,"Mão direita segura a empunhadura: "+label)
	if label=="03b_cofre_aberto":
		check(room.loot_meshes.all(func(pile): return pile.visible and pile.get_child_count()>10),"Cofre aberto revela três conjuntos de notas e ouro")
		var origin: Vector2=player.global_position
		var wallet: int=player.money
		player.global_position=room.to_global(room.project_floor(Vector2(-3,-3.0)))
		room._tick_vault(2,true)
		check(player.money==wallet,"Coleta exige entrar no cofre, sem atravessar a divisória")
		player.global_position=origin
		room._process(.01)
		player.set_physics_process(true)
		Input.action_press("move_up")
		for i in 100:
			await physics_frame
			if player.global_position.y<room.to_global(room.project_floor(Vector2(0,-3.8))).y: break
		Input.action_release("move_up")
		check(player.global_position.y<room.to_global(room.project_floor(Vector2(0,-3.8))).y,"Caminhada real atravessa a porta aberta até o dinheiro")
		Input.action_press("move_left")
		for i in 100:
			await physics_frame
			if player.global_position.distance_to(room.to_global(room.loot_positions[0]))<28: break
		Input.action_release("move_left")
		check(player.global_position.distance_to(room.to_global(room.loot_positions[0]))<28,"Caminhada alcança a pilha lateral dentro do cofre")
		player.set_physics_process(false)
		player.global_position=origin
	if label=="04_coleta":
		check(not room.loot_meshes[0].visible and room.remaining_loot()==6000,"Primeira coleta remove o conjunto e deixa seis mil")
		var wallet: int=player.money
		for i in [1,2]:
			player.global_position=room.to_global(room.loot_positions[i])
			room._tick_vault(1.3,true)
		check(player.money==wallet+6000 and room.remaining_loot()==0,"As três coletas totalizam exatamente dez mil")
		for point in room.loot_positions:
			player.global_position=room.to_global(point)
			room._tick_vault(2,true)
		check(player.money==wallet+6000,"Voltar às pilhas vazias não duplica o pagamento")
		check(room.loot_meshes.all(func(pile): return not pile.visible),"Notas e ouro desaparecem após a coleta")
		room._process(.1)
		check(room.phase==room.HeistPhase.ESCAPE,"Cofre vazio avança para fuga")
	if DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(EVIDENCE+label+".png")
	if label=="01_entrada":
		for i in room.civilians.size(): room.civilians[i].viewport.get_texture().get_image().save_png(EVIDENCE+"atendente%d.png"%i)
	if label in ["01_entrada","02_advertencia"]:
		room.guards[1].viewport_3d.get_texture().get_image().save_png(EVIDENCE+"guarda_"+label+".png")
	if label=="03b_cofre_aberto":
		room.view.get_texture().get_image().save_png(EVIDENCE+"cofre_detalhes.png")
