extends SceneTree

## Teste de Integração Automatizado: MountainPass
## Valida a cena de montanha, ponte do porto, SUV 3D, túnel cutaway, parallax de altitude, tempestade de gelo e sobrevivência ao frio.

var _has_run: bool = false

func _init() -> void:
	call_deferred("run")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if _has_run:
		return
	_has_run = true
	print("--- INICIANDO TESTE DE INTEGRAÇÃO: MOUNTAIN PASS ---")
	var log_lines: Array[String] = []
	var log_msg = func(msg: String):
		print(msg)
		log_lines.append(msg)
	var failures: int = 0
	
	# 1. Instanciação da Cena
	var scene_resource = load("res://world/mountain_pass/MountainPass.tscn")
	if scene_resource == null:
		print("FALHA: Não foi possível carregar MountainPass.tscn")
		quit(1)
		return
	
	var mountain_pass = scene_resource.instantiate()
	mountain_pass.spawn_player_on_ready = false
	mountain_pass.spawn_suv_on_ready = false
	root.add_child(mountain_pass)
	current_scene = mountain_pass
	for i in 6: await process_frame
	
	# 2. Validação da Conexão com a Ponte do Porto (HarborBridge)
	var bridge = mountain_pass.get_node_or_null("HarborBridgeCrossing")
	if bridge == null:
		log_msg.call("FALHA: HarborBridgeCrossing não encontrado na cena")
		failures += 1
	else:
		log_msg.call("SUCESSO: Conexão com HarborBridge integrada na entrada da montanha!")
	
	# 3. Validação do Parallax de Altitude
	var parallax = mountain_pass.get_node_or_null("MountainAltitudeParallax")
	if parallax == null:
		log_msg.call("FALHA: MountainAltitudeParallax não encontrado na cena")
		failures += 1
	else:
		if parallax.get("_clouds").size() < 5:
			log_msg.call("FALHA: Nuvens de altitude não foram geradas no Parallax")
			failures += 1
		else:
			log_msg.call("SUCESSO: Parallax de altitude ativo com %d nuvens volumétricas" % parallax.get("_clouds").size())
	
	# 4. Validação do Túnel e Mecânica Cutaway
	var tunnel = mountain_pass.get_node_or_null("MountainTunnel")
	if tunnel == null:
		log_msg.call("FALHA: MountainTunnel não encontrado")
		failures += 1
	else:
		var roof = tunnel.get("roof_canvas")
		if roof == null or roof.modulate.a < 0.99:
			log_msg.call("FALHA: Teto do túnel não inicializou opaco")
			failures += 1
		else:
			log_msg.call("SUCESSO: Teto do túnel inicializado opaco (alpha = 1.0)")
		
		# Simula entrada de um corpo (veículo/jogador)
		var dummy_body = Node2D.new()
		dummy_body.add_to_group("player")
		tunnel.add_child(dummy_body)
		tunnel._on_body_entered(dummy_body)
		
		# Força o tween a completar para teste imediato e determinístico
		var tw = tunnel.get("_tween") as Tween
		if tw and tw.is_valid():
			tw.custom_step(1.0)
		
		if roof.modulate.a > 0.05:
			log_msg.call("FALHA: Mecânica cutaway não abriu o teto do túnel (alpha = %f)" % roof.modulate.a)
			failures += 1
		else:
			log_msg.call("SUCESSO: Mecânica cutaway revelou o interior do túnel (alpha = %f)" % roof.modulate.a)
		
		# Simula saída
		tunnel._on_body_exited(dummy_body)
		var tw_out = tunnel.get("_tween") as Tween
		if tw_out and tw_out.is_valid():
			tw_out.custom_step(1.0)
		
		if roof.modulate.a < 0.95:
			log_msg.call("FALHA: Teto do túnel não fechou após saída (alpha = %f)" % roof.modulate.a)
			failures += 1
		else:
			log_msg.call("SUCESSO: Teto do túnel fechou com sucesso após saída")
		dummy_body.remove_from_group("player")
		dummy_body.queue_free()

	# 5. Validação do Gerenciador de Clima (Chuva de Gelo & Granizo)
	var storm = mountain_pass.get_node_or_null("IceStormManager")
	if storm == null:
		log_msg.call("FALHA: IceStormManager não encontrado")
		failures += 1
	else:
		storm.set_storm_state(3) # ICE_RAIN_HAIL
		var hail = storm.get("hail_particles") as CPUParticles2D
		var snow = storm.get("snow_blizzard_particles") as CPUParticles2D
		
		if hail == null or not hail.emitting:
			log_msg.call("FALHA: Partículas de granizo/chuva de gelo não estão emitindo no estado ICE_RAIN_HAIL")
			failures += 1
		else:
			log_msg.call("SUCESSO: Chuva de gelo (granizo) ativa com %d partículas" % hail.amount)
		
		if snow == null or not snow.emitting:
			log_msg.call("FALHA: Partículas de nevasca não estão emitindo")
			failures += 1
		else:
			log_msg.call("SUCESSO: Nevasca polar ativa com %d partículas" % snow.amount)

	# 6. Validação do Sistema de Sobrevivência ao Frio
	var cold = mountain_pass.get_node_or_null("ColdSurvivalController")
	if cold == null:
		log_msg.call("FALHA: ColdSurvivalController não encontrado")
		failures += 1
	else:
		cold.set("force_cold_active", true)
		cold.set("current_temperature", 100.0)
		cold._update_temperature(1.0)
		
		var cur_temp: float = cold.get("current_temperature")
		if cur_temp >= 100.0:
			log_msg.call("FALHA: Temperatura corporal não caiu sob exposição ao frio")
			failures += 1
		else:
			log_msg.call("SUCESSO: Frio polar drenou temperatura corporal para %.1f%%" % cur_temp)
		
		# Testa proteção dentro de veículo
		var temp_before_car: float = cur_temp
		cold.set("is_in_vehicle", true)
		cold._update_temperature(1.0)
		var temp_after_car: float = cold.get("current_temperature")
		if temp_after_car <= temp_before_car:
			log_msg.call("FALHA: Veículo não aqueceu o jogador")
			failures += 1
		else:
			log_msg.call("SUCESSO: Aquecedor veicular recuperou temperatura para %.1f%%" % temp_after_car)
		cold.set("is_in_vehicle", false)

		# Testa proteção perto de fogueira
		cold.set("current_temperature", 50.0)
		var temp_before_fire: float = 50.0
		cold.set("is_near_heat_source", true)
		cold._update_temperature(1.0)
		var temp_after_fire: float = cold.get("current_temperature")
		if temp_after_fire <= temp_before_fire:
			log_msg.call("FALHA: Fogueira não aqueceu o jogador")
			failures += 1
		else:
			log_msg.call("SUCESSO: Fogueira da madeireira aqueceu rapidamente para %.1f%%" % temp_after_fire)
		cold.set("is_near_heat_source", false)

		# Testa traje térmico
		cold.equip_thermal_suit(true)
		var temp_with_suit: float = cold.get("current_temperature")
		cold._update_temperature(2.0)
		var temp_after_suit: float = cold.get("current_temperature")
		if not is_equal_approx(temp_with_suit - temp_after_suit, cold.cold_drain_rate * 0.2 * 2.0):
			log_msg.call("FALHA: Traje térmico não reduziu a perda em 80%")
			failures += 1
		else:
			log_msg.call("SUCESSO: Traje térmico reduziu a perda de calor (%.1f%%)" % temp_after_suit)

	# 7. Validação do Veículo 3D Summit SUV
	var suv_script = load("res://world/mountain_pass/MountainSUV.gd")
	if suv_script == null:
		log_msg.call("FALHA: Não foi possível carregar MountainSUV.gd")
		failures += 1
	else:
		var test_suv = suv_script.new()
		mountain_pass.add_child(test_suv)
		for i in 3: await process_frame
		if test_suv.body_model == null:
			log_msg.call("FALHA: Modelo 3D não instanciado no MountainSUV")
			failures += 1
		else:
			log_msg.call("SUCESSO: MountainSUV 3D instanciado e renderizado com sucesso!")
		test_suv.queue_free()

	# 8. Validação dos Setpieces
	var setpieces = mountain_pass.get_node_or_null("Setpieces")
	if setpieces == null:
		log_msg.call("FALHA: Nó Setpieces não encontrado")
		failures += 1
	else:
		var logging = setpieces.get_node_or_null("LoggingCamp")
		var footbridge = setpieces.get_node_or_null("GorgeneckFootbridge")
		var cave = setpieces.get_node_or_null("CaveCache")
		var bunker = setpieces.get_node_or_null("AltitudeOutpostBunker")
		var overlook = setpieces.get_node_or_null("ScenicOverlookArea")
		
		if logging == null or footbridge == null or cave == null or bunker == null or overlook == null:
			log_msg.call("FALHA: Um ou mais setpieces essenciais estão ausentes")
			failures += 1
		else:
			log_msg.call("SUCESSO: Todos os setpieces (Madeireira, Ponte Pedestre, Caverna, Mirante e Bunker) validados!")

	# 9. Validação da Expansão da Área Verde: Estradas de Terra, Chalés, Ammu-Nation e Interiores
	var scenery = mountain_pass.get_node_or_null("MountainSceneryDetailed")
	if scenery == null:
		log_msg.call("FALHA: MountainSceneryDetailed não encontrado")
		failures += 1
	else:
		var dirt_roads = scenery.get_node_or_null("BackcountryDirtRoads")
		var chalets = scenery.get_node_or_null("MountainChalets")
		var ammu = scenery.get_node_or_null("MountainAmmuNation")
		
		if dirt_roads == null:
			log_msg.call("FALHA: BackcountryDirtRoads não encontrado no cenário")
			failures += 1
		else:
			log_msg.call("SUCESSO: Rede de estradinhas de terra da serra validada!")

		if chalets == null or chalets.get_child_count() < 2:
			log_msg.call("FALHA: Chalés alpinos residenciais não encontrados no cenário")
			failures += 1
		else:
			log_msg.call("SUCESSO: Chalés alpinos com varandas e lareiras validados (%d chalés)!" % chalets.get_child_count())

		if ammu == null:
			log_msg.call("FALHA: MountainAmmuNation não encontrada no cenário")
			failures += 1
		else:
			var door = ammu.get_node_or_null("AmmuNationEntrance")
			if door == null:
				log_msg.call("FALHA: Porta de entrada da Ammu-Nation ausente")
				failures += 1
			else:
				log_msg.call("SUCESSO: Ammu-Nation da montanha com estande de tiro e porta interativa validada!")

		var secret_lake = scenery.get_node_or_null("SecretMountainLake")
		if secret_lake == null:
			log_msg.call("FALHA: SecretMountainLake não encontrado no cenário")
			failures += 1
		else:
			var plane = secret_lake.get_node_or_null("SmugglerPlaneWreck")
			var island = secret_lake.get_node_or_null("SecretCacheIsland")
			if plane == null or island == null:
				log_msg.call("FALHA: Elementos de segredo do lago (avião submerso ou ilha do cofre) ausentes")
				failures += 1
			else:
				log_msg.call("SUCESSO: Lago Secreto validado com avião dos contrabandistas e cofre da ilha!")

	# 10. Validação do Gerenciador de Interiores da Montanha
	var int_mgr = mountain_pass.get_node_or_null("MountainInteriorManager")
	if int_mgr == null:
		log_msg.call("FALHA: MountainInteriorManager não encontrado na cena")
		failures += 1
	else:
		var spaces = int_mgr.get_node_or_null("MountainInteriorSpaces")
		var cabin_int = spaces.get_node_or_null("MountainCabinInterior") if spaces else null
		var ammu_int = spaces.get_node_or_null("MountainAmmunationInterior") if spaces else null
		if cabin_int == null or ammu_int == null:
			log_msg.call("FALHA: Espaços interiores de Chalé ou Ammu-Nation ausentes")
			failures += 1
		else:
			log_msg.call("SUCESSO: Interiores jogáveis de Chalé (lareira) e Ammu-Nation (Vance) ativos e roteados!")

	log_msg.call("--- RESULTADO DO TESTE MOUNTAIN PASS: %d FALHAS ---" % failures)
	log_lines.append("--- RESULTADO DO TESTE MOUNTAIN PASS: %d FALHAS ---" % failures)
	var f = FileAccess.open("d:/geteco/game/tests/test_mountain_pass_result.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
		f.close()
	mountain_pass.queue_free()
	for i in 2: await process_frame
	quit(0 if failures == 0 else 1)
