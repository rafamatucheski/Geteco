extends SceneTree

const PROGRESSION := preload("res://runtime/SecretNetworkProgression.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run()


func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print(("SECRET_NETWORK PASS " if ok else "SECRET_NETWORK FAIL ") + label + ((" | " + detail) if not detail.is_empty() else ""))
	if not ok:
		failures.append(label)
		push_error(label + ((" | " + detail) if not detail.is_empty() else ""))


func equivalent(left: Variant, right: Variant) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _run() -> void:
	var progression = PROGRESSION.new()
	check(PROGRESSION.validate_snapshot(progression.snapshot()), "estado inicial satisfaz o contrato")
	check(not progression.unlock_keypad(), "keypad recusa desbloqueio sem casa e pistas")
	check(not progression.discover_headquarters(), "QG recusa descoberta antes do keypad")
	check(not progression.activate_power_node("power_main"), "energia recusa ativacao antes do QG")
	check(not progression.activate_route("route_village_house"), "rota recusa ativacao antes do QG")
	check(not progression.discover_sealed_sector(), "setor selado recusa descoberta antes do QG")
	check(not progression.unlock_final_door(), "porta final recusa desbloqueio precoce")
	check(not progression.collect_fragment("map_unknown"), "fragmento desconhecido e rejeitado")

	check(progression.receive_dossier(), "Maciota entrega a pasta uma unica vez")
	check(not progression.receive_dossier(), "entrega duplicada da pasta e idempotente")
	for id in PROGRESSION.FRAGMENT_IDS:
		check(progression.collect_fragment(id), "fragmento registrado: " + id)
	check(progression.all_fragments_found(), "mapa completo e reconhecido")
	check(not progression.collect_fragment(PROGRESSION.FRAGMENT_IDS[0]), "fragmento duplicado e rejeitado")

	for id in PROGRESSION.KEYPAD_CLUE_IDS:
		check(progression.discover_keypad_clue(id), "pista do keypad registrada: " + id)
	check(not progression.can_unlock_keypad(), "pistas sem descoberta fisica da casa nao liberam keypad")
	check(progression.discover_house(), "casa secreta descoberta")
	check(progression.can_unlock_keypad(), "casa e todas as pistas habilitam tentativa correta")
	check(progression.unlock_keypad(), "keypad desbloqueado")
	check(progression.discover_headquarters(), "QG descoberto depois da passagem")

	check(not progression.activate_power_node("power_drainage"), "ramal de drenagem exige energia principal")
	check(not progression.activate_route("route_village_house"), "rota exige seu no de energia")
	check(progression.activate_power_node("power_main"), "energia principal ativada")
	check(progression.activate_route("route_village_house"), "rota da casa ativada")
	check(not progression.activate_route("route_harbor_sewer"), "rota de esgoto aguarda energia da drenagem")
	check(progression.activate_power_node("power_drainage"), "energia da drenagem ativada")
	check(progression.activate_route("route_harbor_sewer"), "rota do esgoto ativada")
	check(progression.activate_route("route_south_port_drain"), "rota do porto ativada")
	check(progression.activate_route("route_mountain_outfall"), "rota da serra ativada")
	check(progression.can_travel("route_village_house", "route_harbor_sewer"), "viagem exige duas rotas ativas distintas")
	check(not progression.can_travel("route_village_house", "route_village_house"), "viagem recusa origem igual ao destino")
	check(not progression.can_travel("route_village_house", "route_unknown"), "viagem recusa destino desconhecido")

	for id in PROGRESSION.AUDIO_IDS:
		check(progression.discover_audio_log(id), "audio registrado: " + id)
	check(progression.discover_sealed_sector(), "setor selado descoberto apos o QG")
	check(progression.discover_lab_clue(PROGRESSION.LAB_CLUE_IDS[0]), "primeira pista do laboratorio registrada")
	check(progression.discover_lab_clue(PROGRESSION.LAB_CLUE_IDS[1]), "segunda pista do laboratorio registrada")
	check(progression.activate_power_node("power_sealed_sector"), "energia do setor selado ativada")
	check(not progression.can_unlock_final_door(), "porta final exige todas as pistas do laboratorio")
	check(progression.discover_lab_clue(PROGRESSION.LAB_CLUE_IDS[2]), "ultima pista do laboratorio registrada")
	check(progression.can_unlock_final_door(), "setor, energia e pistas habilitam porta final")
	check(progression.unlock_final_door(), "porta final desbloqueada sem definir seu conteudo")

	var summary: Dictionary = progression.progress_summary()
	check(summary.fragments_found == PROGRESSION.FRAGMENT_IDS.size(), "resumo informa todos os fragmentos")
	check(summary.routes_active == PROGRESSION.ROUTE_IDS.size(), "resumo informa todas as rotas")
	check(summary.audio_logs_found == PROGRESSION.AUDIO_IDS.size(), "resumo informa todos os audios")
	check(summary.final_door_unlocked, "resumo informa porta final liberada")

	var detached: Dictionary = progression.snapshot()
	detached.fragments.clear()
	check(progression.snapshot().fragments.size() == PROGRESSION.FRAGMENT_IDS.size(), "snapshot retornado nao expoe estado interno")

	var valid_snapshot: Dictionary = progression.snapshot()
	var restored = PROGRESSION.new()
	check(restored.restore_snapshot(valid_snapshot), "snapshot valido restaura em nova instancia")
	check(equivalent(restored.snapshot(), valid_snapshot), "restore preserva o estado integral")

	var stable_before: Dictionary = restored.snapshot()
	var unknown_route: Dictionary = stable_before.duplicate(true)
	unknown_route.routes.append("route_unknown")
	check(not restored.restore_snapshot(unknown_route), "restore rejeita rota desconhecida")
	check(equivalent(restored.snapshot(), stable_before), "rejeicao de rota desconhecida e atomica")

	var duplicate_fragment: Dictionary = stable_before.duplicate(true)
	duplicate_fragment.fragments.append(PROGRESSION.FRAGMENT_IDS[0])
	check(not restored.restore_snapshot(duplicate_fragment), "restore rejeita IDs duplicados")
	check(equivalent(restored.snapshot(), stable_before), "rejeicao de duplicata preserva estado vivo")

	var impossible_power: Dictionary = stable_before.duplicate(true)
	impossible_power.power_nodes.erase("power_main")
	check(not restored.restore_snapshot(impossible_power), "restore rejeita dependencias de energia impossiveis")
	check(equivalent(restored.snapshot(), stable_before), "rejeicao causal preserva estado vivo")

	var missing_lab_clue: Dictionary = stable_before.duplicate(true)
	missing_lab_clue.lab_clues.erase(PROGRESSION.LAB_CLUE_IDS[0])
	check(not restored.restore_snapshot(missing_lab_clue), "restore rejeita porta final sem todas as pistas")
	check(equivalent(restored.snapshot(), stable_before), "rejeicao da porta final e atomica")

	var missing_tape: Dictionary = stable_before.duplicate(true)
	missing_tape.audio_logs.erase("audio_sealed_sector")
	check(not restored.restore_snapshot(missing_tape), "restore rejeita porta final sem a fita do setor lacrado")
	check(equivalent(restored.snapshot(), stable_before), "rejeicao da fita ausente e atomica")

	var unknown_field: Dictionary = stable_before.duplicate(true)
	unknown_field.unexpected = true
	check(not restored.restore_snapshot(unknown_field), "restore rejeita campo fora do schema V1")
	check(equivalent(restored.snapshot(), stable_before), "rejeicao de schema preserva estado vivo")

	print("SECRET_NETWORK_PROGRESSION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
