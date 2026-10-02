extends SceneTree
## Ambulância, caminhão de bombeiros e carro do legista chegando dirigindo,
## estacionando, desembarcando a equipe original (Responder) e partindo.
## O atendimento é do Responder/EmergencyManager reais: aqui só se observa se
## a equipe esteve fisicamente no local quando a ocorrência terminou.

const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
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
	if "--wreck-only" in OS.get_cmdline_user_args():
		await _mortician_wreck()
		report("DISPATCH_MORTICIAN_WRECK", ["mortician_wreck"], 10)
		return
	if "--mortician-only" in OS.get_cmdline_user_args():
		await _service("mortician")
		await _mortician_policy()
		await _mortician_wreck()
		report("DISPATCH_MORTICIAN", ["service_mortician", "mortician_policy", "mortician_wreck"], 38)
		return
	await _service("medic")
	await _service("fire")
	await _service("mortician")
	await _crew_limit_and_cooldown()
	await _mortician_policy()
	await _mortician_wreck()
	report("DISPATCH_EMERGENCY", ["service_medic", "service_fire", "service_mortician", "crew_limit_and_cooldown", "mortician_policy", "mortician_wreck"], 58)

func _frames(count: int) -> void:
	for index in count: await physics_frame

func _open_incident(bundle: Dictionary, role: String) -> Dictionary:
	var scene: Node3D = bundle.scene
	var gameplay: Node3D = bundle.gameplay
	var emergency: Node3D = gameplay.emergency
	var point := Vector3(34, 0, 14)
	var actor: Node3D = null
	if role == "fire":
		actor = emergency.ignite(point, bundle.player, 1.0)
	else:
		actor = KIT.add_patient(scene, point)
		emergency.report_injury(actor, role == "mortician")
	return {"actor": actor, "key": emergency.serial}

func _service(role: String) -> void:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var emergency: Node3D = gameplay.emergency
	# Garagem do serviço sobre a faixa da avenida, a ~30 m do local.
	controller.set_depots(role, [Vector3(4, 0, 2)])
	await _frames(3)
	var opened := _open_incident(bundle, role)
	var actor: Node3D = opened.actor
	var key: int = opened.key
	check(is_instance_valid(actor) and emergency.incidents.has(key), "ocorrência registrada (%s)" % role)
	var expected_role: String = role
	check(emergency.incidents[key].role == expected_role, "papel da ocorrência (%s)" % role)
	var unit: RefCounted = null
	# Bombeiro espera 10-15 s; IML aguarda 20-35 s; médico sai sem atraso próprio.
	var wait_ticks := 2400 if role == "mortician" else (1200 if role == "fire" else 300)
	for tick in wait_ticks:
		await physics_frame
		if not controller.units.is_empty():
			unit = controller.units[0]
			break
	check(unit != null, "viatura despachada no prazo (%s)" % role)
	if unit == null:
		KIT.teardown(bundle)
		return
	var archetype: String = RULES.archetype_for(role)
	check(unit.vehicle.archetype == archetype, "veículo original %s" % archetype)
	check(emergency.incidents[key].assigned and emergency.crews.is_empty(), "ocorrência reservada e nenhuma equipe teletransportada pelo gerente legado")
	check(emergency.dispatch_owned, "despacho legado do EmergencyManager suspenso")
	var start: Vector3 = unit.vehicle.global_position
	var worst_step := 0.0
	var last := start
	var parked := false
	var crew_seen: CharacterBody3D = null
	var crew_created := false
	var crew_script := ""
	var crew_near_when_done := false
	var crew_role_meta := ""
	var crew_position := Vector3.ZERO
	var incident_closed := false
	var boarded := false
	# Contador em Dictionary: a lambda captura variáveis locais por valor.
	var notices := {"incident_invalid": 0}
	controller.dispatch_event.connect(func(event_name: String, data: Dictionary):
		if event_name == "incident_invalid" and data.get("unit") == unit: notices.incident_invalid += 1)
	for tick in 7200:
		await physics_frame
		if is_instance_valid(unit.vehicle):
			worst_step = maxf(worst_step, unit.vehicle.global_position.distance_to(last))
			last = unit.vehicle.global_position
		if unit.state == "parked": parked = true
		if is_instance_valid(unit.crew):
			crew_seen = unit.crew
			crew_created = true
			crew_script = unit.crew.get_script().resource_path
			crew_position = unit.crew.global_position
			# Capturado com a equipe viva: depois do embarque o nó já foi liberado.
			crew_role_meta = str(unit.crew.get_meta("gameplay_role", ""))
		if not incident_closed and not emergency.incidents.has(key):
			incident_closed = true
			# Quem concluiu esteve no local: o Responder estava a poucos metros do alvo.
			var target_point: Vector3 = actor.global_position if is_instance_valid(actor) else Vector3(34, 0, 14)
			crew_near_when_done = crew_seen != null and crew_position.distance_to(target_point) < 3.5
		if not controller.events_named("crew_boarded").is_empty(): boarded = true
		if unit.finished: break
	check(unit.state != "enroute", "a viatura saiu do estado de deslocamento")
	check(worst_step < 0.6, "nenhum salto de posição: %.2f m por quadro" % worst_step)
	check(last.distance_to(start) > 5.0 or parked, "percorreu a rua até a ocorrência")
	check(parked, "estacionou antes do desembarque (%s)" % role)
	check(crew_created and crew_role_meta == "emergency" and crew_script.ends_with("gameplay/emergency/Responder.gd"), "equipe é o Responder original")
	check(incident_closed, "ocorrência encerrada pelo atendimento (%s)" % role)
	check(crew_near_when_done, "a equipe estava junto do alvo quando a ocorrência terminou, não só por tempo (%s)" % role)
	if role == "medic": check(is_instance_valid(actor) and actor.health >= 60.0, "paciente estabilizado")
	if role == "mortician": check(not is_instance_valid(actor) or actor.is_queued_for_deletion(), "corpo removido pelo legista")
	if role == "fire": check(not is_instance_valid(actor) or actor.is_queued_for_deletion() or actor.intensity <= 0.0, "fogo extinto")
	check(boarded, "equipe embarcou de volta na viatura")
	# Fogo extinto e corpo removido tiram a fonte da ocorrência com a equipe ainda a pé; o
	# aviso era repetido a cada quadro físico durante todo o retorno.
	check(notices.incident_invalid <= 1, "fonte da ocorrência perdida é notificada uma vez, não a cada quadro (%s: %d)" % [role, notices.incident_invalid])
	check(unit.finished and unit.end_reason == "left", "viatura partiu dirigindo (%s)" % unit.end_reason)
	check(controller.units.is_empty(), "controlador liberou a unidade")
	check(not is_instance_valid(unit.crew), "nenhum socorrista fica na cena")
	check(not is_instance_valid(crew_seen), "o Responder foi liberado depois do embarque")
	KIT.teardown(bundle)
	done("service_" + role)

func _crew_limit_and_cooldown() -> void:
	# Cinco pacientes: no máximo três equipes ao mesmo tempo e 10 s entre despachos.
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var gameplay: Node3D = bundle.gameplay
	var controller: Node3D = bundle.controller
	var emergency: Node3D = gameplay.emergency
	controller.set_depots("medic", [Vector3(4, 0, 2)])
	await _frames(3)
	for index in 5:
		var patient := KIT.add_patient(bundle.scene, Vector3(20 + index * 3, 0, 16))
		emergency.report_injury(patient, false)
	var dispatch_frames: Array[int] = []
	var peak := 0
	for tick in 2400:
		await physics_frame
		gameplay.emergency.dispatch_clock = 1.0e9
		peak = maxi(peak, controller._active_services().size())
		var count: int = controller.events_named("dispatched").size()
		while dispatch_frames.size() < count: dispatch_frames.append(tick)
	check(dispatch_frames.size() >= 2, "mais de uma equipe atendeu a fila (%d)" % dispatch_frames.size())
	check(peak <= RULES.MAX_CREWS, "no máximo %d equipes ao mesmo tempo (%d)" % [RULES.MAX_CREWS, peak])
	if dispatch_frames.size() >= 2:
		check(dispatch_frames[1] - dispatch_frames[0] >= int(RULES.DISPATCH_COOLDOWN * 60.0) - 90, "intervalo de 10 s entre despachos (%d quadros)" % (dispatch_frames[1] - dispatch_frames[0]))
	KIT.teardown(bundle)
	done("crew_limit_and_cooldown")

func _mortician_policy() -> void:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var controller: Node3D = bundle.controller
	var emergency: Node3D = bundle.gameplay.emergency
	controller.set_physics_process(false)
	emergency.set_physics_process(false)
	await _frames(3)
	var opened := _open_incident(bundle, "mortician")
	var key: int = opened.key
	var record: Dictionary = emergency.incidents[key]
	check(not emergency.mortician_dispatch_allowed(key), "IML aguarda antes de atender")
	record.age = 40.0
	for stars in range(3, 7):
		bundle.gameplay.stars = stars
		controller._scan_clock = 0.0
		controller._dispatch_emergency(0.5)
		check(controller.units.is_empty() and not record.has("search"), "IML não planeja nem despacha com %d estrelas" % stars)
	bundle.gameplay.stars = 2
	check(emergency.mortician_dispatch_allowed(key), "IML pode atender com duas estrelas")
	controller._scan_clock = 0.0
	controller._dispatch_emergency(0.5)
	check(record.has("search"), "IML retoma a busca quando a situação acalma")
	bundle.gameplay.stars = 3
	controller._scan_clock = 0.0
	controller._dispatch_emergency(0.5)
	check(not record.has("search"), "subida de estrelas cancela busca incompleta")
	bundle.gameplay.stars = 0
	emergency.mortician_clock = 60.0
	check(not emergency.mortician_dispatch_allowed(key), "pausa própria do IML bloqueia nova saída")
	emergency._physics_process(60.0)
	check(emergency.mortician_dispatch_allowed(key), "IML volta a ficar disponível após a pausa")
	check(emergency.incidents.has(key) and not record.assigned, "ocorrência adiada permanece na fila")
	KIT.teardown(bundle)
	done("mortician_policy")

func _mortician_wreck() -> void:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(30, 0, 10))
	var controller: Node3D = bundle.controller
	var emergency: Node3D = bundle.gameplay.emergency
	controller.set_depots("mortician", [Vector3(4, 0, 2)])
	await _frames(3)
	var opened := _open_incident(bundle, "mortician")
	emergency.incidents[opened.key].age = 40.0
	var unit: RefCounted = null
	for tick in 3000:
		await physics_frame
		for candidate in controller.units:
			if candidate.incident_id == opened.key: unit = candidate
		if unit != null and is_instance_valid(unit.crew) and unit.crew.mode == "service": break
	var ready: bool = unit != null and is_instance_valid(unit.crew) and unit.crew.mode == "service"
	check(ready, "legista chegou fisicamente ao corpo antes da interrupção")
	if not ready:
		KIT.teardown(bundle)
		return
	var crew: CharacterBody3D = unit.crew
	var origin := crew.global_position
	unit.vehicle.receive_damage(100000.0)
	await _frames(3)
	check(unit.wrecked and unit.vehicle.health <= 0.0, "dano destruiu a viatura do IML")
	check(not crew.dead and crew.mode == "flee", "legista sobrevivente foge da viatura destruída")
	check(not crew.visual.stretcher_mesh.visible and not crew.visual.body_bag_mesh.visible, "coleta e apresentação da maca foram interrompidas")
	check(emergency.incidents.has(opened.key) and not emergency.incidents[opened.key].assigned, "corpo não coletado volta à fila")
	for tick in 600:
		await physics_frame
		if not is_instance_valid(crew): break
	await _frames(3) # O controlador remove unidades concluídas no próximo tick.
	if is_instance_valid(crew):
		print("FLEE_DIAGNOSTIC origin=", origin, " position=", crew.global_position, " goal=", crew.destination, " path=", crew.path, " waypoint=", crew.waypoint, " velocity=", crew.velocity)
	check(not is_instance_valid(crew) or crew.global_position.distance_to(origin) > 3.0, "fuga usa movimento físico")
	check(controller.events_named("crew_fled").size() == 1, "fuga concluída é registrada uma vez")
	check(controller.events_named("crew_boarded").is_empty(), "legista não embarca na carcaça")
	check(is_instance_valid(opened.actor) and not opened.actor.is_queued_for_deletion(), "corpo permanece após coleta interrompida")
	check(unit.finished and not controller.units.has(unit), "fuga libera a unidade destruída")
	KIT.teardown(bundle)
	done("mortician_wreck")
