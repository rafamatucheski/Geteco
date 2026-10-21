extends SceneTree
## Contrato do prólogo (BlitzScene) sem mundo: a marca "prologue_seen" no checkpoint da chegada,
## save antigo pulando o prólogo, interruptores de ambiente e o JSON das falas.
const ARRIVAL := preload("res://runtime/Arrival.gd")
const BLITZ := preload("res://runtime/prologue/BlitzScene.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	var fresh := ARRIVAL.new()
	check(not fresh.prologue_seen, "jogo novo começa com o prólogo pendente")
	var snapshot := fresh.snapshot()
	check(snapshot.get("prologue_seen") == false and ARRIVAL.validate_snapshot(snapshot), "checkpoint grava a marca pendente e continua válido")
	var disk: Variant = JSON.parse_string(JSON.stringify(snapshot))
	var reloaded := ARRIVAL.new()
	check(reloaded.restore_state(disk) and not reloaded.prologue_seen, "fechar no meio do prólogo volta para o prólogo")
	fresh.prologue_seen = true
	check(reloaded.restore_state(JSON.parse_string(JSON.stringify(fresh.snapshot()))) and reloaded.prologue_seen, "prólogo visto não repete depois de carregar")
	# Save de antes do prólogo: sem a chave, inclusive parado no filme da balsa.
	var old := {"version":2, "phase":"opening", "flags":{}, "caption":-1, "opening_completed":false}
	var legacy := ARRIVAL.new()
	check(ARRIVAL.validate_snapshot(old) and legacy.restore_state(old) and legacy.prologue_seen, "save antigo sem a marca pula o prólogo")
	var v1 := {"version":1, "phase":"phone", "flags":{"harbor_arrival_seen":true, "harbor_police_briefed":true}, "caption":-1, "opening_completed":true}
	var migrated := ARRIVAL.new()
	check(migrated.restore_state(v1) and migrated.prologue_seen, "checkpoint da V1 também pula o prólogo")
	for bad in ["sim", 1, null]:
		var corrupted := fresh.snapshot()
		corrupted.prologue_seen = bad
		check(not ARRIVAL.validate_snapshot(corrupted), "marca do prólogo só aceita booleano: %s" % str(bad))
	var rejected := ARRIVAL.new()
	rejected.prologue_seen = true
	var tampered := fresh.snapshot()
	tampered.prologue_seen = "x"
	check(not rejected.restore_state(tampered) and rejected.prologue_seen, "save recusado não mexe na marca viva")
	for node in [fresh, reloaded, legacy, migrated, rejected]: node.free()
	# Interruptores: o runner pula filme e prólogo; os testes do filme pulam só o prólogo.
	var previous_opening := OS.get_environment("GETECO_SKIP_OPENING")
	var previous_prologue := OS.get_environment("GETECO_SKIP_PROLOGUE")
	OS.set_environment("GETECO_SKIP_OPENING", "1")
	OS.set_environment("GETECO_SKIP_PROLOGUE", "")
	check(ARRIVAL.skip_opening() and ARRIVAL.skip_prologue(), "GETECO_SKIP_OPENING=1 pula o prólogo também")
	OS.set_environment("GETECO_SKIP_OPENING", "0")
	check(not ARRIVAL.skip_prologue(), "abertura ligada mostra o prólogo")
	OS.set_environment("GETECO_SKIP_PROLOGUE", "1")
	check(not ARRIVAL.skip_opening() and ARRIVAL.skip_prologue(), "GETECO_SKIP_PROLOGUE=1 pula só o prólogo")
	OS.set_environment("GETECO_SKIP_OPENING", previous_opening)
	OS.set_environment("GETECO_SKIP_PROLOGUE", previous_prologue)
	# Falas: só legenda, cada uma com quem fala e o português; inglês existe e fica vazio.
	var data: Dictionary = BLITZ.lines()
	check(data.get("version") == 1.0, "JSON das falas do prólogo carrega")
	var groups := {"dante":["radio_open", "colleagues", "stopped", "approach", "ask", "door", "order_out", "ambush", "shooter_down", "flee", "order"], "vicente":["radio_open", "radio_warning", "lights", "stop"]}
	for pov in groups:
		for key in groups[pov]:
			var source: Array = data.get(pov, {}).get(key, [])
			check(not source.is_empty(), "falas %s.%s existem" % [pov, key])
			for line in source:
				check(not str(line.get("speaker", "")).is_empty() and not str(line.get("pt", "")).is_empty() and line.has("en"), "fala %s tem quem fala, PT e EN" % str(line.get("id")))
	var prado: Array = data.dante.radio_open
	check(prado.any(func(line): return line.pt == "Procedimento, Ferraz." and line.speaker == "Prado" and line.radio), "Prado no rádio: \"Procedimento, Ferraz.\"")
	check(data.dante.door[0].pt == "Dante?" and data.dante.order[0].pt == "Ferraz. Procedimento.", "a porta e a ordem seguem o roteiro")
	check(BLITZ.text(data.get("title")) == "Oito anos depois.", "título do corte para preto")
	for key in ["signal", "cuff", "skip"]:
		check(not BLITZ.text(data.prompts.get(key)).is_empty(), "comando %s tem texto" % key)
	print("PROLOGUE SAVE CONTRACT checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
