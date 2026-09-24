extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	create_timer(120.0).timeout.connect(func():
		printerr("FAIL: mountain ski 3D and loop test timed out")
		quit(2)
	)

	var packed := load("res://world/mountain_pass/MountainPass.tscn") as PackedScene
	expect(packed != null, "MountainPass scene loads")
	if packed == null:
		quit(1)
		return

	var mountain := packed.instantiate()
	root.add_child(mountain)
	current_scene = mountain
	while not mountain.region_ready:
		await process_frame

	var ski_area := mountain.get_node_or_null("MountainSkiArea")
	expect(ski_area != null, "MountainSkiArea exists")
	if not ski_area:
		quit(1)
		return

	# -------------------------------------------------------------
	# 1. VALIDAÇÃO DE MODELOS 100% 3D
	# -------------------------------------------------------------
	# A. Torres de Teleférico em 3D
	var tower1 = ski_area.get_node_or_null("LiftTower1")
	var tower2 = ski_area.get_node_or_null("LiftTower2")
	expect(tower1 != null and tower1.get("model") is MountainChairliftTower3D, "LiftTower1 is rendered from MountainChairliftTower3D")
	expect(tower2 != null and tower2.get("model") is MountainChairliftTower3D, "LiftTower2 is rendered from MountainChairliftTower3D")
	if tower1 and tower1.get("model"):
		var t_model: Node3D = tower1.model
		expect(t_model.find_child("CrossarmMain", true, false) != null, "chairlift tower has 3D crossarm")
		expect(t_model.find_child("PylonBase", true, false) != null, "chairlift tower has tubular steel pylon")
		expect(t_model.find_child("TopBeacon", true, false) != null, "chairlift tower has night warning beacon")

	# B. Cadeirinhas 3D móveis com passageiros
	var chairs := ski_area.find_children("ChairliftChair*", "Node2D", true, false)
	expect(chairs.size() >= 4, "circulating 3D chairlift chairs are installed along cable")
	var has_rider_chair := false
	for ch in chairs:
		expect(ch.get("model") is MountainChairliftChair3D, "chairlift chair uses 3D model MountainChairliftChair3D")
		if ch.get("model"):
			var c_model: Node3D = ch.model
			expect(c_model.find_child("SeatBench", true, false) != null, "chair has 3D bench seat")
			expect(c_model.find_child("SafetyBarFront", true, false) != null, "chair has 3D safety bar")
			if c_model.find_child("SeatedSkier", true, false) != null:
				has_rider_chair = true
	expect(has_rider_chair, "chairlift includes chairs with seated 3D skier riders")

	# C. Estações de teleférico com Bullwheel 3D
	var summit_station = ski_area.get_node_or_null("SummitLiftStation")
	var base_station = ski_area.get_node_or_null("BaseLiftStation")
	expect(summit_station != null and summit_station.get("model") is MountainSkiLift3D, "summit station uses 3D model")
	expect(base_station != null and base_station.get("model") is MountainSkiLift3D, "base station uses 3D model")
	if summit_station and summit_station.get("model"):
		expect(summit_station.model.find_child("DriveBullwheel", true, false) != null, "station has 3D cable drive bullwheel")
		expect(summit_station.model.find_child("ControlCabin", true, false) != null, "station has 3D operator cabin")
		expect(summit_station.model.find_child("Turnstile", true, false) != null, "station has 3D queue turnstile")

	# D. Pórticos 3D de Largada e Chegada nas provas
	var races := ski_area.get_tree().get_nodes_in_group("ski_race")
	expect(races.size() == 3, "three ski races registered")
	for r in races:
		var start_arch = r.find_child("StartArch3D", true, false)
		var finish_arch = r.find_child("FinishArch3D", true, false)
		expect(start_arch != null and start_arch.get("model") is MountainSkiStartArch3D, "race has 3D start arch MountainSkiStartArch3D")
		expect(finish_arch != null and finish_arch.get("model") is MountainSkiFinishArch3D, "race has 3D finish arch MountainSkiFinishArch3D")

	# -------------------------------------------------------------
	# 2. HORÁRIO DE FUNCIONAMENTO (MountainSkiSchedule)
	# -------------------------------------------------------------
	var schedule_script := preload("res://world/mountain_pass/MountainSkiSchedule.gd")
	expect(schedule_script != null, "MountainSkiSchedule script exists")

	# Teste do relógio de dia/noite
	var dummy_clock := preload("res://systems/DayNightWeatherManager.gd").new()
	dummy_clock.name = "DummyClock"
	dummy_clock.set("time_of_day", 0.50) # 12:00 meio-dia
	mountain.add_child(dummy_clock)
	# MountainSkiSchedule lê o primeiro nó de "day_night_manager"; com o mundo
	# carregado é o relógio real, não este. Ajusta o relógio que o horário lê.
	var clock: Node = mountain.get_tree().get_first_node_in_group("day_night_manager")
	if clock == null: clock = dummy_clock
	clock.set("time_of_day", 0.50)

	expect(schedule_script.is_open(mountain), "resort is open at 12:00 (midday)")
	expect(schedule_script.get_time_formatted(mountain) == "12:00", "time formats correctly to 12:00")

	# Altera para 22:00 (noite)
	clock.set("time_of_day", 22.0 / 24.0)
	expect(not schedule_script.is_open(mountain), "resort is closed at 22:00 (night)")
	expect(schedule_script.get_closed_notice(mountain, "Teleférico").contains("08:00 ÀS 18:00"), "closed notice explains operating hours")

	# Retorna para dia normal (10:00)
	clock.set("time_of_day", 10.0 / 24.0)
	expect(schedule_script.is_open(mountain), "resort re-opens at 10:00")

	# -------------------------------------------------------------
	# 3. NPCS E AMBIENTAÇÃO ("Gente fazendo a parada")
	# -------------------------------------------------------------
	# A. No Chalé (Interior)
	var manager: Node = mountain.interior_manager
	var lodge_room: Node = manager._interiors.get(&"ski_lodge")
	expect(lodge_room != null, "ski lodge interior loaded")
	if lodge_room:
		var clerk = lodge_room.find_child("SkiClerk", true, false)
		var guest1 = lodge_room.find_child("LodgeGuestFireplace", true, false)
		var guest2 = lodge_room.find_child("LodgeGuestLounge", true, false)
		expect(clerk != null, "rental counter has attendant SkiClerk")
		expect(guest1 != null, "lodge has guest warming up at fireplace")
		expect(guest2 != null, "lodge has guest relaxing in lounge")

	# B. Na Base e no Cume (Área Externa)
	var base_op = ski_area.find_child("BaseLiftOperator", true, false)
	var summit_op = ski_area.find_child("SummitLiftOperator", true, false)
	expect(base_op != null, "base station has operator BaseLiftOperator")
	expect(summit_op != null, "summit station has operator SummitLiftOperator")

	# C. Esquiadores Ambientes
	var skiers = ski_area.find_children("AmbientSkier*", "CharacterBody2D", true, false)
	expect(skiers.size() >= 6, "ambient skiers active on slopes")

	# -------------------------------------------------------------
	# 4. LOOP DE GAMEPLAY COMPLETO DO JOGADOR
	# -------------------------------------------------------------
	var player: CharacterBody2D = mountain.player_instance
	expect(player != null, "player exists in mountain")
	if player and lodge_room:
		player.money = 1500
		var money_start: int = player.money

		# Passo 1: Aluguel da roupa de ski no balcão
		expect(player.begin_ski_rental(250), "player rents ski suit at counter")
		expect(player.money == money_start - 250, "rental deducted correctly")
		expect(player.current_outfit_id == "dante_ski", "ski suit equipped")

		# Passo 2: Retirada de skis e bastões no rack
		player.take_ski_equipment()
		expect(player.ski_equipment_ready, "skis and poles ready")

		# Passo 3: atravessa as duas portas físicas do chalé.
		player.set_physics_process(false)
		var front: BuildingEntrance = lodge_room.inline_facade.entrance
		var rear: BuildingEntrance = lodge_room.inline_facade.slope_entrance
		player.global_position = front.global_position + Vector2(0, 22)
		for _i in 8: await process_frame
		expect(await _walk(player, lodge_room.to_global(lodge_room.project_floor(Vector2(0, 3.75)))), "player enters lodge on foot")
		expect(await _walk(player, rear.global_position + Vector2(0, -22)), "player crosses lodge to slopes on foot")
		for _i in 5: await process_frame
		expect(player.is_skiing and not player.has_meta("mountain_interior"), "rear door starts skiing without teleport")

		# Passo 4: Conclusão de prova de corrida
		var race: SkiRaceController = races[0]
		expect(race != null, "first race exists")
		player.global_position = ski_area.to_global(race.start_pos)
		race._start(player)
		expect(race._state == SkiRaceController.State.COUNTDOWN, "race countdown initiated")
		race._countdown = 0.0
		race._process(0.01)
		expect(race._state == SkiRaceController.State.RUNNING, "race running after countdown")

		# Simula passagem por todos os checkpoints até a linha de chegada
		var money_before_prize: int = player.money
		for cp in race.checkpoints:
			player.global_position = ski_area.to_global(cp)
			race._process(0.02)
		expect(race._state == SkiRaceController.State.RESULT, "race finishes at final checkpoint")
		expect(player.money > money_before_prize, "player received cash prize upon completion")

		# Passo 5: Retorno ao Cume pelo Teleférico da Base
		player.global_position = base_station.global_position
		expect(base_station._can_board(player), "player can board chairlift at base station")

		# Dispara a subida do teleférico
		base_station._return_to_summit(player, true)
		await process_frame
		await process_frame
		var layout_script := preload("res://world/mountain_pass/MountainSkiLayout.gd")
		var expected_summit: Vector2 = ski_area.to_global(layout_script.LIFT_SUMMIT)
		expect(player.global_position.distance_to(expected_summit) < 80.0, "chairlift brings player back to summit station")
		expect(player.is_skiing, "player disembarks ready to ski again on the summit")

		# Passo 6: Devolução do aluguel restaura roupa original
		player.stop_skiing()
		player.return_ski_rental()
		expect(not player.ski_rental_active and not player.ski_equipment_ready, "rental returned")
		expect(player.current_outfit_id == "dante_classic", "classic costume restored")

	dummy_clock.queue_free()

	if failures.is_empty():
		print("PASS: 100% 3D models, complete ski gameplay loop, operating schedule, and lively resort NPCs")
	else:
		print("TEST FAILED WITH %d ERRORS" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _walk(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 420:
		var motion := target - actor.global_position
		if motion.length() < 2.0: return true
		if actor.move_and_collide(motion.limit_length(2.5)) != null: return false
		await physics_frame
	return false
