extends SceneTree

## PROPOSTA DE CORREÇÃO (não aplicada) para tests/test_harbor_mountain_drive.gd
## ================================================================
## Este arquivo NÃO faz parte da suíte de auditoria em si — é uma proposta,
## isolada em tests/claude_gameplay_audit/, para integração posterior no
## arquivo real (que continua intocado). Ver AUDIT_REPORT.md, achado
## "tests/test_harbor_mountain_drive.gd está desatualizado".
##
## O QUE MUDOU EM RELAÇÃO AO ORIGINAL (diff conceitual, linha a linha):
##   1. Nenhuma mudança na condução física real: mesmas waypoints de
##      district/harbor_preview/HarborMountainConnector.gd, mesmo
##      car.move_and_collide() físico, mesma detecção de colisão real contra
##      o sensor/geometria da ponte — exatamente como o teste original.
##   2. A ÚNICA mudança são as duas condições de sucesso da travessia, que no
##      original checavam `current_scene.scene_file_path` — um contrato que a
##      arquitetura de streaming contínuo (district/harbor_preview/ContinuousWorld.gd)
##      já não usa: as duas regiões coexistem como irmãs na mesma cena
##      HarborGame, e current_scene NUNCA muda. Aqui essas duas checagens
##      passam a usar ContinuousWorld.current_region (o contrato real e atual,
##      já usado por tests/claude_gameplay_audit/test_audit_09_port_mountain_transition.gd).
##   3. Adicionado um pequeno wait real após cada travessia para dar tempo de
##      ContinuousWorld._process() (tick de 0.2s) reavaliar a região —
##      necessário porque current_region não muda no mesmo frame da colisão
##      física, só no próximo tick do temporizador real.
##
## Resultado desta proposta rodada de verdade neste ambiente: aprovado.
## (ver tests/claude_gameplay_audit/logs/proposed_fix_harbor_mountain_drive.log)

var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	# Watchdog generoso (ver AUDIT_REPORT.md): a preparação streamed da região
	# da montanha sozinha já observou ~74s neste ambiente headless/sem GPU.
	create_timer(240).timeout.connect(func(): quit(2))
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	for i in 12: await physics_frame
	var harbor := current_scene
	var stream := harbor.get_node("ContinuousWorld")
	for vehicle in get_nodes_in_group("modern_traffic"):
		vehicle.collision_layer = 0
		vehicle.set_physics_process(false)
	var car := preload("res://district/mountain_pass/MountainSUV.gd").new()
	car.position = Vector2(6120,-4100)
	harbor.add_child(car)
	car.enter_vehicle(harbor.get_node("Player"))
	car.set_physics_process(false)
	var points: PackedVector2Array = preload("res://district/harbor_preview/HarborMountainConnector.gd").road_definitions()[0].points
	for destination in points:
		while car.global_position.distance_to(destination)>4 and current_scene==harbor:
			var direction: Vector2 = car.global_position.direction_to(destination)
			car.rotation = direction.angle()
			car.velocity = direction*100
			var collision := car.move_and_collide(direction*minf(14,car.global_position.distance_to(destination)))
			if collision:
				failures.append("Road blocked at %s by %s" %[car.global_position,collision.get_collider().get_path()])
				break
			await physics_frame
		if not failures.is_empty() or current_scene!=harbor: break
	for i in 15: await physics_frame
	# PROPOSTA: contrato real (ContinuousWorld.current_region), não mais
	# current_scene.scene_file_path — a travessia física não troca de cena.
	await _settle_region(stream)
	if String(stream.current_region) != "mountain": failures.append("Physical bridge sensor did not transfer to Mountain region (current_region=%s)" % stream.current_region)
	if root.get_node("RegionTravel").controlled_car()!=car: failures.append("Driver lost the car at the physical crossing")
	if failures.is_empty():
		var mountain: Node2D = stream.mountain
		for vehicle in get_nodes_in_group("modern_traffic"):
			if vehicle == car: continue
			vehicle.collision_layer = 0
			vehicle.set_physics_process(false)
		root.get_node("RegionTravel").cooldown = 0
		while String(stream.current_region) == "mountain" and car.global_position.x>2920:
			car.rotation = PI
			car.velocity = Vector2(-100,0)
			var return_collision := car.move_and_collide(Vector2(-12,0))
			if return_collision:
				failures.append("Mountain return blocked by "+str(return_collision.get_collider().get_path()))
				break
			await physics_frame
		for i in 15: await physics_frame
		await _settle_region(stream)
		# PROPOSTA: mesmo contrato real para o retorno.
		if String(stream.current_region) != "harbor":
			failures.append("Physical return sensor did not return to Harbor region (current_region=%s)" % stream.current_region)
		else:
			for vehicle in get_nodes_in_group("modern_traffic"):
				if vehicle == car: continue
				vehicle.collision_layer = 0
				vehicle.set_physics_process(false)
			var inbound: PackedVector2Array = preload("res://district/harbor_preview/HarborMountainConnector.gd").road_definitions()[1].points
			inbound.remove_at(0)
			inbound.append(Vector2(5880,-4000))
			for target in inbound:
				while car.global_position.distance_to(target)>4:
					var direction: Vector2 = car.global_position.direction_to(target)
					car.rotation = direction.angle()
					car.velocity = direction*100
					var collision := car.move_and_collide(direction*minf(14,car.global_position.distance_to(target)))
					if collision:
						failures.append("Inbound bridge blocked by "+str(collision.get_collider().get_path()))
						break
					await physics_frame
				if not failures.is_empty(): break
	print("HARBOR MOUNTAIN DRIVE (proposta): ", failures)
	current_scene.queue_free()
	for i in 4: await process_frame
	quit(0 if failures.is_empty() else 1)

## ContinuousWorld._update_region() só roda depois de ready_for_crossing==true
## (ver ContinuousWorld._process(): "if not ready_for_crossing: return"), e a
## preparação da região streamed pode levar dezenas de segundos reais (ver
## AUDIT_REPORT.md, "Preparação da região da montanha é muito lenta em
## headless" — medido em ~74s numa execução limpa neste ambiente). O teste
## original não esperava por isso — dirigia até o destino físico e checava a
## cena na sequência, o que só "funcionava" (sob a arquitetura antiga) porque
## a troca de cena em si era instantânea. Sob o contrato atual, é preciso
## esperar current_region de verdade refletir a posição física do carro.
func _settle_region(stream: Node) -> void:
	var deadline := Time.get_ticks_msec() + 150000
	while not bool(stream.get("ready_for_crossing")) and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(0.5).timeout
