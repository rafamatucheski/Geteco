extends SceneTree
## Fitas do piloto (31/10/2026): contrato de carteira, sem mundo. Coleta as dez numa ordem
## embaralhada, salva e restaura no meio (snapshot/restore_snapshot, o mesmo caminho do save),
## confere que fita repetida não conta nem paga duas vezes e que o galpão só abre na décima.
## Não prova que cada pickup é alcançável a pé no mundo: isso pede a sessão real (como em
## test_vicente_letters.gd) e ficou como pendência em docs/fitas-piloto-20261031.md.
## Uso: "$GODOT" --headless --path . --script res://tests/test_pilot_tapes.gd
const Economy := preload("res://systems/economy/Economy.gd")
const TAPES := preload("res://data/catalogs/PilotTapes.gd")
const CATALOG := preload("res://data/catalogs/CollectibleCatalog.gd")
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
const LETTERS := preload("res://data/catalogs/VicenteLetters.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var points := TAPES.points()
	check(points.size() == 10, "dez pontos de fita")
	var regions := {}
	for entry in points:
		regions[entry.region] = int(regions.get(entry.region, 0)) + 1
		check(CATALOG.ENTRIES.has(entry.id) and TAPES.PLACES.has(entry.id), "%s no catálogo e com lugar" % entry.id)
		check(entry.point is Vector3 and is_finite(entry.point.x) and is_finite(entry.point.z), "%s com ponto finito" % entry.id)
	check(regions.get("harbor", 0) == 4 and regions.get("mountain", 0) == 3 and regions.get("desert", 0) == 3, "4 Harbor, 3 serra, 3 deserto")
	# Espalhadas: nenhuma fita a menos de 30 m de outra nem de uma carta de Vicente.
	var others := DEFINITIONS.vicente_letters()
	for a in points:
		for b in points + others:
			if a.id == b.id or a.region != b.region: continue
			var d := Vector2(a.point.x, a.point.z).distance_to(Vector2(b.point.x, b.point.z))
			if d < 30.0: check(false, "%s a %.1f m de %s" % [a.id, d, b.id])
	var ids := DEFINITIONS.collectibles().map(func(entry): return entry.id)
	for id in TAPES.IDS: check(ids.count(id) == 1, "%s entra uma vez nos pickups" % id)

	# Dicas (parte 2): uma por fita, aviso aponta a mais perto que falta, diário lista as que faltam.
	for id in TAPES.IDS: check(str(TAPES.HINTS.get(id, "")).length() > 4, "%s com dica" % id)
	check(TAPES.journal_lines([]).is_empty(), "diário calado antes da primeira fita")
	var near_04: Vector3 = points.filter(func(entry): return entry.id == "pilot_tape_04")[0].point
	check(TAPES.next_missing(["pilot_tape_01"], "harbor", near_04).id == "pilot_tape_04", "próxima é a mais perto na região")
	check(TAPES.found_message(["pilot_tape_01"], "harbor", near_04) == "Fitas 1/10. Próxima: \"%s\"" % TAPES.HINTS.pilot_tape_04, "aviso traz a dica da próxima")
	check(TAPES.next_missing(["pilot_tape_01", "pilot_tape_02", "pilot_tape_03", "pilot_tape_04"], "harbor", near_04).id == "pilot_tape_05", "sem fita na região, a primeira que falta")
	var journal := TAPES.journal_lines(["pilot_tape_03", "pilot_tape_07"])
	check(journal.size() == 9 and journal[0] == "Fitas do piloto 2/10", "diário conta e lista oito dicas")
	check(not journal.has("· " + TAPES.HINTS.pilot_tape_03) and journal.has("· " + TAPES.HINTS.pilot_tape_10), "diário só lista as que faltam")
	check(TAPES.next_missing(TAPES.IDS.duplicate(), "harbor", Vector3.ZERO).is_empty(), "sem próxima com as dez")
	# Portão fora da pista do drift do pátio: a barreira fechada no centro do drift cortava a área.
	# O drift não tem traçado fixo (Motorsport.begin_drift): a "rota" é o círculo de raio radius/16
	# em volta do centro, então a folga é medida da borda do círculo e de pontos amostrados nele.
	var gate := Vector2(TAPES.HIDEOUT_POINT.x, TAPES.HIDEOUT_POINT.z)
	for drift in DEFINITIONS.drifts("harbor").values():
		var center := DEFINITIONS.at(drift.pos)
		var radius := float(drift.radius) / 16.0
		var edge := gate.distance_to(Vector2(center.x, center.z)) - radius
		check(edge >= TAPES.HIDEOUT_DRIFT_CLEARANCE, "portão a %.1f m (>= 12) da área do drift %s" % [edge, drift.id])
		var nearest := INF
		for step in 32:
			var angle := TAU * float(step) / 32.0
			for ring in [0.0, .5, 1.0]:
				var sample := Vector2(center.x, center.z) + Vector2(cos(angle), sin(angle)) * radius * float(ring)
				nearest = minf(nearest, gate.distance_to(sample))
		check(nearest >= TAPES.HIDEOUT_DRIFT_CLEARANCE, "portão a %.1f m de todos os pontos do drift %s" % [nearest, drift.id])
	check(absf(TAPES.HIDEOUT_GROUND_PROBE.x - TAPES.HIDEOUT_POINT.x) < .01 and TAPES.HIDEOUT_GROUND_PROBE.z < TAPES.HIDEOUT_POINT.z, "raio do chão sai para a rua, fora da parede")
	check(TAPES.LOCKED_MESSAGE == "Fechado. Algo aqui espera dez fitas.", "texto do portão trancado")

	var economy := Economy.new()
	var order := [7, 2, 9, 0, 5, 3, 8, 1, 6, 4]
	for step in 5:
		check(economy.collect(TAPES.IDS[order[step]]), "fita %d coletada" % (order[step] + 1))
	check(not economy.collect(TAPES.IDS[order[0]]), "fita repetida recusada")
	check(not TAPES.try_unlock(economy) and not TAPES.hideout_open(economy), "galpão fechado com 5")
	var balance_mid := economy.balance
	var saved := economy.snapshot()
	var restored := Economy.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(saved))), "save do meio restaura")
	check(TAPES.found(restored.snapshot().collectibles) == 5 and restored.balance == balance_mid, "restaurado com 5 fitas e o mesmo saldo")
	for step in 5: check(not restored.collect(TAPES.IDS[order[step]]), "fita %d não conta de novo depois do load" % (order[step] + 1))
	check(restored.balance == balance_mid, "sem pagar duas vezes")
	for step in range(5, 9):
		check(restored.collect(TAPES.IDS[order[step]]), "fita %d coletada depois do load" % (order[step] + 1))
		check(not TAPES.try_unlock(restored), "galpão fechado com %d" % (step + 1))
	check(restored.collect(TAPES.IDS[order[9]]) and TAPES.complete(restored.snapshot().collectibles), "décima fita completa a coleção")
	check(TAPES.try_unlock(restored) and TAPES.hideout_open(restored), "galpão abre na décima")
	var after := restored.balance
	check(not TAPES.try_unlock(restored) and restored.balance == after, "galpão abre uma vez só")
	var reloaded := Economy.new()
	check(reloaded.restore_snapshot(JSON.parse_string(JSON.stringify(restored.snapshot()))) and TAPES.hideout_open(reloaded), "galpão aberto sobrevive ao save")
	check(TAPES.journal_lines(reloaded.snapshot().collectibles)[0] == "Fitas do piloto 10/10", "diário com as dez depois do load")
	check(not LETTERS.complete(reloaded.snapshot().collectibles), "fitas não contam como cartas de Vicente")
	print("PILOT_TAPES failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)

func check(value: bool, label: String) -> void:
	print("PILOT_TAPES ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
