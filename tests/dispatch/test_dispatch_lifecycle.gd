extends SceneTree
## Cancelamento, incidente inválido, suspensão distante, retomada, caminho
## bloqueado com e sem alternativa, equipe abatida e acesso inexistente.
## Nenhum cenário conclui atendimento por cronômetro.

const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const OFFICER := preload("res://gameplay/PoliceAgent.gd")
const RESPONDER := preload("res://gameplay/emergency/Responder.gd")
var failures: Array[String] = []
var checks := 0
var groups_done: Array[String] = []

func done(group: String) -> void:
	groups_done.append(group)
	print("GROUP_OK " + group)

## Um erro de script aborta a função no meio e o teste seguiria adiante: só
## vale se todos os grupos esperados chegaram ao fim e houve verificações demais.
func report(tag: String, expected: Array, minimum_checks: int) -> void:
	var missing: Array[String] = []
	for group in expected:
		if not groups_done.has(group): missing.append(group)
	if not missing.is_empty(): failures.append("grupos não concluídos: " + str(missing))
	if checks < minimum_checks: failures.append("poucas verificações: %d < %d" % [checks, minimum_checks])
	print("%s groups=%d/%d checks=%d failures=%d" % [tag, expected.size() - missing.size(), expected.size(), checks, failures.size()])
	for failure in failures: print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--only=detour":
			await _detour_around_wall()
			report("DISPATCH_LIFECYCLE", ["detour_around_wall"], 5)
			return
		if argument == "--only=suspension_people":
			await _suspension_of_people()
			report("DISPATCH_LIFECYCLE", ["suspension_of_people"], 7)
			return
	await _incident_removed_while_enroute()
	await _incident_removed_while_working()
	await _cancel_api()
	await _suspension_and_resume()
	await _suspension_recycles()
	await _detour_around_wall()
	await _no_road_access()
	await _crew_killed()
	await _vehicle_wrecked()
	await _patient_dies_during_care()
	await _suspension_of_people()
	await _dismiss_and_wrecks()
	await _controller_leaves_tree()
	await _no_crime_from_dispatch_vehicle()
	report("DISPATCH_LIFECYCLE", ["incident_removed_while_enroute", "incident_removed_while_working", "cancel_api", "suspension_and_resume", "suspension_recycles", "detour_around_wall", "no_road_access", "crew_killed", "vehicle_wrecked", "patient_dies_during_care", "suspension_of_people", "dismiss_and_wrecks", "controller_leaves_tree", "no_crime_from_dispatch_vehicle"], 40)

func _frames(count: int) -> void:
	for index in count: await physics_frame

func _medic_world(depot: Vector3 = Vector3(4, 0, 2)) -> Dictionary:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	bundle.controller.set_depots("medic", [depot])
	await _frames(3)
	var patient := KIT.add_patient(bundle.scene, Vector3(34, 0, 14))
	bundle.gameplay.emergency.report_injury(patient, false)
	bundle["patient"] = patient
	bundle["key"] = bundle.gameplay.emergency.serial
	return bundle

func _wait_unit(bundle: Dictionary, limit: int = 300) -> RefCounted:
	for tick in limit:
		await physics_frame
		if not bundle.controller.units.is_empty(): return bundle.controller.units[0]
	return null

func _wait_state(unit: RefCounted, state: String, limit: int) -> bool:
	for tick in limit:
		await physics_frame
		if unit.state == state or unit.finished: break
	return unit.state == state

func _finish(unit: RefCounted, limit: int) -> bool:
	for tick in limit:
		await physics_frame
		if unit.finished: return true
	return unit.finished

func _incident_removed_while_enroute() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var emergency: Node3D = bundle.gameplay.emergency
	var unit: RefCounted = await _wait_unit(bundle)
	check(unit != null, "despacho para incidente que será anulado")
	if unit == null:
		KIT.teardown(bundle)
		return
	await _frames(20)
	check(unit.state == "enroute", "a viatura ainda está a caminho")
	# O paciente some (removido por outro sistema): o incidente fica inválido.
	bundle.patient.queue_free()
	var finished: bool = await _finish(unit, 3600)
	check(not controller.events_named("incident_invalid").is_empty(), "viatura notou que o incidente ficou inválido")
	check(unit.crew == null and controller.events_named("crew_boarded").is_empty(), "nenhuma equipe foi enviada a um incidente inexistente")
	check(finished and unit.end_reason == "left", "a viatura saiu dirigindo (%s)" % unit.end_reason)
	check(not emergency.incidents.has(bundle.key), "gerente real limpou o registro")
	KIT.teardown(bundle)
	done("incident_removed_while_enroute")

func _incident_removed_while_working() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para cancelamento com equipe a pé")
		KIT.teardown(bundle)
		return
	var working: bool = await _wait_state(unit, "working", 2400)
	check(working, "equipe desembarcou (%s)" % unit.state)
	var crew: CharacterBody3D = unit.crew
	# Anula quando a equipe acabou de sair: nada é dado como atendido.
	bundle.patient.queue_free()
	var finished: bool = await _finish(unit, 5400)
	check(is_instance_valid(crew) == false, "a equipe foi liberada")
	check(not controller.events_named("crew_boarded").is_empty(), "a equipe voltou e embarcou antes de a viatura partir")
	check(finished and unit.end_reason == "left", "a viatura só partiu depois do embarque (%s)" % unit.end_reason)
	check(not controller.bridge.roles.has(bundle.key), "papel da ocorrência removida não fica retido na ponte")
	KIT.teardown(bundle)
	done("incident_removed_while_working")

func _cancel_api() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var emergency: Node3D = bundle.gameplay.emergency
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para cancelamento explícito")
		KIT.teardown(bundle)
		return
	await _frames(30)
	check(controller.cancel_incident(bundle.key), "cancel_incident aceita a ocorrência em andamento")
	check(unit.state == "departing", "unidade passou a partir")
	check(emergency.incidents.has(bundle.key) and not emergency.incidents[bundle.key].assigned, "ocorrência devolvida ao gerente real, sem dono")
	check(not controller.cancel_incident(9999), "cancelar ocorrência desconhecida é recusado")
	var finished: bool = await _finish(unit, 3600)
	check(finished, "viatura cancelada deixou a cena")
	KIT.teardown(bundle)
	done("cancel_api")

func _suspension_and_resume() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para suspensão")
		KIT.teardown(bundle)
		return
	var vehicle: CharacterBody3D = unit.vehicle
	await _frames(30)
	bundle.player.global_position = Vector3(30, 0, 200)
	await _frames(5)
	check(unit.suspended and not vehicle.visible and not vehicle.is_physics_processing(), "distante do jogador a viatura é suspensa e escondida")
	check(vehicle.collision_layer == 0 and vehicle.collision_mask == 0, "suspensa sem colisão para não virar obstáculo invisível")
	var frozen: Vector3 = vehicle.global_position
	await _frames(120)
	check(vehicle.global_position.distance_to(frozen) < 0.01, "suspensa não se move")
	bundle.player.global_position = Vector3(30, 0, 10)
	await _frames(10)
	check(not unit.suspended and vehicle.visible and vehicle.is_physics_processing() and vehicle.collision_layer == 4, "ao voltar, a viatura é retomada com a colisão original")
	check(not controller.events_named("unit_resumed").is_empty(), "evento de retomada")
	KIT.teardown(bundle)
	done("suspension_and_resume")

func _suspension_recycles() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var emergency: Node3D = bundle.gameplay.emergency
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para reciclagem")
		KIT.teardown(bundle)
		return
	bundle.player.global_position = Vector3(30, 0, 200)
	var finished: bool = await _finish(unit, int((RULES.SUSPEND_RECYCLE_SECONDS + 5.0) * 60.0))
	check(finished and unit.end_reason == "suspended_too_long", "suspensa por tempo demais, a unidade é liberada (%s)" % unit.end_reason)
	check(controller.units.is_empty(), "controlador não guarda unidade morta")
	check(not emergency.incidents.has(bundle.key) or not emergency.incidents[bundle.key].assigned, "a ocorrência não fica presa a uma unidade que sumiu")
	KIT.teardown(bundle)
	done("suspension_recycles")

func _detour_around_wall() -> void:
	# Avenida cortada por uma parede, mas com o anel como alternativa: ré, novo
	# plano pelo anel, retorno de verdade e chegada. Nunca atravessa a parede.
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	KIT.add_wall(bundle.scene, Vector3(-25, 1.5, 0), Vector3(1.0, 3.0, 14.0))
	controller.set_depots("police", [Vector3(-50, 0, 2)])
	await _frames(3)
	gameplay.register_crime(60, bundle.player.global_position)
	var unit: RefCounted = await _wait_unit(bundle, 900)
	check(unit != null, "despacho com obstáculo na rota")
	if unit == null:
		KIT.teardown(bundle)
		return
	var crossed := false
	var worst := 0.0
	var last: Vector3 = unit.vehicle.global_position
	var arrived := false
	for tick in 7200:
		await physics_frame
		gameplay.health = 100.0
		# Este caso mede o desvio físico, não a expiração da procura durante uma
		# aproximação longa: há observação contínua do crime neste cenário.
		gameplay.report_contact(bundle.player.global_position)
		if not is_instance_valid(unit.vehicle): break
		worst = maxf(worst, unit.vehicle.global_position.distance_to(last))
		last = unit.vehicle.global_position
		if last.x > -24.0 and last.x < -8.0 and absf(last.z) < 6.0: crossed = true
		if unit.state == "working" and not unit.officers.is_empty():
			arrived = true
			break
	check(not crossed, "nunca passou pelo trecho murado da avenida")
	check(worst < 0.6, "nenhum salto de posição no desvio: %.2f m" % worst)
	var replans: Array[Dictionary] = controller.events_named("replanned")
	check(not replans.is_empty() and replans[0].ok == true, "o novo plano pelo anel foi encontrado")
	var safe_give_up: bool = not controller.events_named("route_blocked").is_empty() and (unit.finished or unit.state == "departing")
	check(arrived or safe_give_up, "desvio chega ou respeita o limite de recuperação e parte sem atravessar (%s; fim=%s)" % [unit.state, unit.end_reason])
	KIT.teardown(bundle)
	done("detour_around_wall")

func _no_road_access() -> void:
	# Ocorrência longe de qualquer rua: sem acesso, não há viatura nem equipe.
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var emergency: Node3D = gameplay.emergency
	controller.set_depots("medic", [Vector3(4, 0, 2)])
	await _frames(3)
	var patient := KIT.add_patient(bundle.scene, Vector3(30, 0, 29))
	emergency.report_injury(patient, false)
	var key: int = emergency.serial
	await _frames(300)
	check(controller.units.is_empty(), "sem rua a menos de %.0f m do paciente, nenhuma viatura sai" % RULES.FOOT_RANGE)
	check(not controller.events_named("spawn_failed").is_empty(), "a falha de despacho é registrada")
	check(not emergency.incidents[key].assigned, "ocorrência continua livre para expirar pelo prazo do gerente")
	KIT.teardown(bundle)
	done("no_road_access")

func _crew_killed() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var emergency: Node3D = bundle.gameplay.emergency
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para equipe abatida")
		KIT.teardown(bundle)
		return
	await _wait_state(unit, "working", 2400)
	var crew: CharacterBody3D = unit.crew
	if not is_instance_valid(crew):
		check(false, "equipe existia para ser abatida")
		KIT.teardown(bundle)
		return
	crew.receive_damage(1000.0, null)
	await _frames(5)
	check(not controller.events_named("crew_lost").is_empty(), "morte da equipe percebida")
	check(not emergency.incidents.has(bundle.key) or not emergency.incidents[bundle.key].assigned or emergency.incidents[bundle.key].get("crew") != crew, "ocorrência não continua presa à equipe morta")
	KIT.teardown(bundle)
	done("crew_killed")

func _vehicle_wrecked() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para viatura destruída")
		KIT.teardown(bundle)
		return
	await _frames(30)
	var vehicle: CharacterBody3D = unit.vehicle
	vehicle.receive_damage(vehicle.max_health + 1.0)
	await _frames(5)
	check(unit.wrecked, "viatura destruída é reconhecida")
	check(not controller.events_named("unit_wrecked").is_empty(), "evento de destruição")
	check(vehicle.controlled == false, "a viatura destruída deixa de ser conduzida")
	KIT.teardown(bundle)
	done("vehicle_wrecked")


func _patient_dies_during_care() -> void:
	# O paciente morre com o paramédico já trabalhando: o paramédico não pode
	# concluir (nem remover o corpo, nem reviver o morto); a ocorrência vira
	# legista e só a viatura do legista a encerra.
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var gameplay: Node3D = bundle.gameplay
	var emergency: Node3D = gameplay.emergency
	controller.set_depots("mortician", [Vector3(4, 0, 2)])
	var patient: CharacterBody3D = bundle.patient
	var medic: RefCounted = await _wait_unit(bundle)
	if medic == null:
		check(false, "despacho médico para o paciente que vai morrer")
		KIT.teardown(bundle)
		return
	var working: bool = await _wait_state(medic, "working", 2400)
	check(working, "paramédico desembarcou")
	patient.receive_damage(1000.0, null)
	await _frames(2)
	check(patient.dead and emergency.incidents[bundle.key].role == "mortician", "a morte reclassificou a ocorrência para legista")
	var corpse_kept := true
	var revived := false
	var medic_left := false
	var wagon: RefCounted = null
	for tick in 9000:
		await physics_frame
		if not medic_left and (not is_instance_valid(patient) or patient.is_queued_for_deletion()): corpse_kept = false
		if is_instance_valid(patient) and not patient.dead: revived = true
		if medic.finished: medic_left = true
		for unit in controller.units:
			if unit.service == "mortician": wagon = unit
		if medic_left and wagon != null and wagon.finished: break
	check(not revived, "o paramédico não reviveu o morto")
	check(corpse_kept, "o paramédico não removeu o corpo")
	check(not controller.events_named("patient_died").is_empty() or medic.retasked, "o paramédico foi reencaminhado")
	check(medic.finished and medic.end_reason == "left", "a viatura médica partiu (%s)" % medic.end_reason)
	check(wagon != null, "a ocorrência foi entregue à viatura do legista")
	if wagon != null: check(wagon.finished and wagon.end_reason == "left", "viatura do legista concluiu o fluxo e partiu (%s)" % wagon.end_reason)
	check(not is_instance_valid(patient) or patient.is_queued_for_deletion(), "o corpo saiu de cena pelo legista")
	KIT.teardown(bundle)
	done("patient_dies_during_care")

func _suspension_of_people() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para suspender a equipe")
		KIT.teardown(bundle)
		return
	var working: bool = await _wait_state(unit, "working", 2400)
	check(working and is_instance_valid(unit.crew), "equipe a pé antes da suspensão")
	var crew: CharacterBody3D = unit.crew
	var crew_layer := crew.collision_layer
	var crew_mask := crew.collision_mask
	bundle.player.global_position = Vector3(30, 0, 200)
	await _frames(5)
	check(unit.suspended, "unidade suspensa")
	check(crew.collision_layer == 0 and crew.collision_mask == 0 and not crew.visible and not crew.is_physics_processing(), "a equipe a pé também sai da física e da vista")
	# Um sólido novo surge onde o socorrista ficou: a unidade não retoma por cima dele.
	var blocker := KIT.add_wall(bundle.scene, crew.global_position + Vector3.UP, Vector3(0.8, 2.0, 0.8))
	var exclusions: Array[RID] = [unit.vehicle.get_rid(), crew.get_rid()]
	bundle.player.global_position = Vector3(30, 0, 10)
	await _frames(2)
	check(not controller.capsule_clear(crew.global_position, exclusions), "o sólido novo entrou na física e ocupa a cápsula da equipe")
	await _frames(58)
	check(unit.suspended and crew.collision_layer == 0, "cápsula bloqueada impede a retomada")
	blocker.queue_free()
	await _frames(30)
	check(not unit.suspended, "com o local livre a unidade retoma")
	check(crew.collision_layer == crew_layer and crew.collision_mask == crew_mask and crew.visible and crew.is_physics_processing(), "a equipe recupera colisão, máscara, vista e física")
	KIT.teardown(bundle)
	done("suspension_of_people")

func _dismiss_and_wrecks() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var emergency: Node3D = bundle.gameplay.emergency
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para recolher tudo")
		KIT.teardown(bundle)
		return
	var working: bool = await _wait_state(unit, "working", 2400)
	var vehicle: CharacterBody3D = unit.vehicle
	var crew: CharacterBody3D = unit.crew
	check(working and is_instance_valid(crew), "equipe a pé antes do recolhimento")
	controller.dismiss_all("travel")
	await _frames(3)
	check(not is_instance_valid(vehicle) and not is_instance_valid(crew), "troca de região recolhe viatura e equipe")
	check(controller.units.is_empty(), "nenhuma unidade registrada")
	check(not emergency.incidents.has(bundle.key) or not emergency.incidents[bundle.key].assigned, "ocorrência devolvida")
	# Destroço registrado também é recolhido.
	var second: RefCounted = null
	controller._service_clock = 0.0
	for tick in 900:
		await physics_frame
		if not controller.units.is_empty():
			second = controller.units[0]
			break
	if second == null:
		check(false, "nova viatura para virar destroço")
		KIT.teardown(bundle)
		return
	var wreck: CharacterBody3D = second.vehicle
	wreck.receive_damage(wreck.max_health + 1.0)
	await _frames(10)
	check(controller.wrecks.has(wreck), "destroço adotado pelo controlador")
	# Pessoas já destacadas da lista da unidade (cadáver em decaimento ou equipe
	# sem unidade) também pertencem ao contexto do despacho e não atravessam travel/load.
	var detached_officer := OFFICER.new()
	detached_officer.controller = bundle.gameplay
	controller.add_child(detached_officer)
	detached_officer.set_physics_process(false)
	detached_officer.receive_damage(1000.0, null)
	var detached_responder := RESPONDER.new()
	detached_responder.manager = controller.bridge
	controller.add_child(detached_responder)
	detached_responder.set_physics_process(false)
	controller.dismiss_all("cleanup")
	await _frames(3)
	check(not is_instance_valid(wreck) and controller.wrecks.is_empty(), "dismiss_all também recolhe destroços")
	check(not is_instance_valid(detached_officer) and not is_instance_valid(detached_responder), "dismiss_all recolhe pessoas destacadas sem deixar equipe órfã")
	KIT.teardown(bundle)
	done("dismiss_and_wrecks")

func _controller_leaves_tree() -> void:
	var bundle: Dictionary = await _medic_world()
	var controller: Node3D = bundle.controller
	var gameplay: Node3D = bundle.gameplay
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para remover o controlador")
		KIT.teardown(bundle)
		return
	var working: bool = await _wait_state(unit, "working", 2400)
	var vehicle: CharacterBody3D = unit.vehicle
	var crew: CharacterBody3D = unit.crew
	check(working and is_instance_valid(crew), "equipe a pé antes de remover o controlador")
	bundle.scene.remove_child(controller)
	controller.queue_free()
	await _frames(3)
	check(not is_instance_valid(vehicle), "os carros, filhos do mundo, não ficam órfãos")
	check(not is_instance_valid(crew), "a equipe não fica órfã")
	check(gameplay.dispatch_timer < 1.0e8 and gameplay.emergency.dispatch_clock < 1.0e8, "o despacho legado foi devolvido")
	check(not gameplay.emergency.incidents[bundle.key].assigned, "a ocorrência voltou a ficar livre")
	KIT.teardown(bundle)
	done("controller_leaves_tree")

func _no_crime_from_dispatch_vehicle() -> void:
	# A viatura atropela um civil: o dano é do carro, não do jogador.
	var bundle: Dictionary = await _medic_world()
	var gameplay: Node3D = bundle.gameplay
	var unit: RefCounted = await _wait_unit(bundle)
	if unit == null:
		check(false, "despacho para atropelamento")
		KIT.teardown(bundle)
		return
	# Actor.receive_damage procura `gameplay` no pai: sem isto o caminho que
	# atribui crime ao jogador nem seria exercitado.
	var wiring := GDScript.new()
	wiring.source_code = "extends Node3D
var gameplay
"
	wiring.reload()
	bundle.scene.set_script(wiring)
	bundle.scene.gameplay = gameplay
	var civilian := KIT.add_patient(bundle.scene, Vector3(12, 0, 2), 100.0)
	var hit := false
	for tick in 240:
		unit.vehicle.speed = 10.0
		await physics_frame
		if civilian.health < 100.0:
			hit = true
			break
	check(hit, "houve colisão com o civil")
	check(gameplay.crime_points == 0 and gameplay.stars == 0, "atropelar com viatura de despacho não gera procura contra o jogador (%d)" % gameplay.crime_points)
	check(unit.vehicle.get_script().resource_path.ends_with("DispatchVehicle.gd"), "veículo é o DispatchVehicle")
	KIT.teardown(bundle)
	done("no_crime_from_dispatch_vehicle")
