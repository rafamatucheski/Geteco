extends SceneTree
## Contrato da cadeia da Helena no ato 1 (HelenaAct1State), sem carregar o mundo (segundos):
## missões principais intocadas, etapas em ordem, recibos únicos, save antigo válido, save forjado
## recusado, serviço de guincho de M02-B no contrato do MissionWorld e falas em JSON bem formadas.
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tests/test_helena_act1_contract.gd
const STATE := preload("res://runtime/GameState.gd")
const ACT1 := preload("res://systems/campaign/HelenaAct1State.gd")
const LINES := preload("res://systems/campaign/HelenaAct1Lines.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const MISSION_WORLD := preload("res://runtime/MissionWorld.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	main_missions_untouched()
	stages_and_receipts()
	save_contract()
	tow_contract()
	dialogue_file()
	for message in failures: push_error(message)
	print("%s helena act1 contract: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> bool:
	checks += 1
	if not value: failures.append(message)
	return value

## O save valida recibos contra a ordem, os ids e os valores das missões principais.
func main_missions_untouched() -> void:
	check(MISSIONS.ORDER == ["primeiro_giro", "cobra_contact", "cobra_race", "cobra_collection", "jessica_bank", "cobra_supply", "cobra_finale"], "ORDER das missões principais não mudou")
	var rewards := {}
	for id in MISSIONS.ORDER: rewards[id] = int(MISSIONS.MISSIONS[id].reward)
	check(rewards == {"primeiro_giro": 150, "cobra_contact": 120, "cobra_race": 200, "cobra_collection": 250, "jessica_bank": 500, "cobra_supply": 350, "cobra_finale": 600}, "recompensas base das missões principais não mudaram")
	var keys := {}
	for id in ACT1.ORDER:
		keys[ACT1.CHAIN[id].key] = true
		check(MISSIONS.ORDER.has(ACT1.CHAIN[id].after), "%s abre depois de uma missão principal" % id)
	check(keys.size() == ACT1.ORDER.size() and ACT1.ORDER.size() == ACT1.CHAIN.size(), "cada missão nova tem a própria chave")
	check(ACT1.CHAIN.debt.amount == 300 and ACT1.CHAIN.wash.amount == 600, "valores gravados em recibo (debt 300, wash 600)")

func _campaign(completed: Array, call_complete := false) -> Dictionary:
	return {"completed": completed, "legacy_skipped": [], "aftermath": {"call_complete": call_complete}}

func stages_and_receipts() -> void:
	var world := {}
	var economy = preload("res://systems/economy/Economy.gd").new()
	var none := _campaign([])
	var m2 := _campaign(MISSIONS.ORDER.slice(0, 2))
	check(not ACT1.advance(world, none, "debt", "neco"), "M02-B não abre antes de Dentro do território")
	check(ACT1.validate(world, economy.snapshot(), none), "save sem nenhuma chave nova é válido")
	check(not ACT1.advance(world, m2, "debt", "tow1"), "não pula etapa")
	check(ACT1.advance(world, m2, "debt", "neco") and ACT1.stage(world, "debt") == "neco", "Helena -> Neco")
	check(not ACT1.advance(world, m2, "debt", "done"), "conclusão só por finish (com o recibo)")
	check(not ACT1.finish(world, m2, economy, "debt").ok, "não conclui no meio")
	for to in ["tow1", "tow2", "tow3"]:
		check(ACT1.advance(world, m2, "debt", to), "guincho: %s" % to)
		check(ACT1.debt_tow_index(world) == ["tow1", "tow2", "tow3"].find(to), "índice do carro em %s" % to)
	check(not ACT1.advance(world, m2, "debt", "tow1"), "não volta etapa")
	check(ACT1.validate(world, economy.snapshot(), m2), "etapa aberta sem recibo é válida")
	var before: int = economy.balance
	check(ACT1.finish(world, m2, economy, "debt").ok and economy.balance == before + 300 and ACT1.complete(world, "debt"), "M02-B paga R$ 300 uma vez")
	check(not ACT1.finish(world, m2, economy, "debt").ok and economy.balance == before + 300, "não paga duas vezes")
	check(ACT1.validate(world, economy.snapshot(), m2), "concluída com recibo é válida")
	check(not ACT1.validate(world, economy.snapshot(), none), "etapa sem a missão principal anterior é recusada")
	# M04-B: escolha gravada.
	var m4 := _campaign(MISSIONS.ORDER.slice(0, 4))
	check(not ACT1.advance(world, m2, "press", "press"), "M04-B espera A conta chega")
	check(ACT1.advance(world, m4, "press", "return") and ACT1.choice(world) == "return", "escolha: devolver")
	check(not ACT1.advance(world, m4, "press", "press"), "escolha não troca depois de feita")
	check(ACT1.finish(world, m4, economy, "press").ok and ACT1.choice(world) == "return", "conclusão guarda a escolha")
	# Cadeia: M05-B precisa de M02-B; M06-B de M05-B; despedida de M06-B e da ligação do Maciota.
	var m5 := _campaign(MISSIONS.ORDER.slice(0, 5))
	var gap := {}
	check(not ACT1.advance(gap, m5, "wash", "station"), "M05-B espera M02-B")
	check(ACT1.advance(world, m5, "wash", "station") and ACT1.advance(world, m5, "wash", "escape") and ACT1.advance(world, m5, "wash", "envelopes"), "M05-B: cais -> cofre -> fuga -> envelopes")
	before = economy.balance
	check(ACT1.finish(world, m5, economy, "wash").ok and economy.balance == before + 600, "M05-B paga R$ 600")
	var all := _campaign(MISSIONS.ORDER)
	check(not ACT1.advance(world, m5, "folder", "night"), "M06-B espera Cortar o abastecimento")
	check(ACT1.advance(world, all, "folder", "night") and ACT1.advance(world, all, "folder", "handoff") and ACT1.finish(world, all, economy, "folder").ok, "M06-B completa, sem pagamento")
	check(not ACT1.finish(world, all, economy, "farewell").ok, "despedida espera a ligação do Maciota")
	var called := _campaign(MISSIONS.ORDER, true)
	check(ACT1.finish(world, called, economy, "farewell").ok, "despedida depois da ligação")
	check(ACT1.finish(world, m2, economy, "ride").ok, "carona opcional depois de M02")
	check(ACT1.validate(world, economy.snapshot(), called), "cadeia inteira concluída é válida")
	check(ACT1.journal_line(world, called).is_empty(), "nada pendente no diário")
	check(not ACT1.journal_line({}, m2).is_empty(), "diário mostra M02-B disponível")

func save_contract() -> void:
	var saved: Dictionary = FIXTURE.full_snapshot(Vector3.ZERO, true)
	var state = STATE.new()
	if not check(state.restore_snapshot(saved), "fixture: Harbor concluído"): return
	check(STATE.new().restore_snapshot(state.snapshot()), "save antigo (sem chave nova) continua válido")
	var campaign: Dictionary = state.campaign.snapshot()
	check(ACT1.advance(state.world_state, campaign, "debt", "neco"), "etapa no save real")
	check(STATE.new().restore_snapshot(state.snapshot()), "etapa aberta passa no GameState")
	for to in ["tow1", "tow2", "tow3"]: ACT1.advance(state.world_state, campaign, "debt", to)
	check(ACT1.finish(state.world_state, campaign, state.economy, "debt").ok, "conclusão no save real")
	var good: Dictionary = state.snapshot()
	check(STATE.new().restore_snapshot(good), "concluída com recibo passa no GameState")
	var forged: Dictionary = good.duplicate(true)
	forged.world.harbor_act1_debt = {"version": 1, "stage": "tow2"}
	check(not STATE.new().restore_snapshot(forged), "recibo sem missão concluída é recusado")
	forged = good.duplicate(true)
	forged.economy.transactions.erase("reward:harbor_act1_debt")
	check(RECEIPTS.lookup(forged.economy, "reward", "harbor_act1_debt").is_empty() and not STATE.new().restore_snapshot(forged), "missão concluída sem recibo é recusada")
	forged = good.duplicate(true)
	forged.world.harbor_act1_debt = {"version": 1, "stage": "done", "extra": 1}
	check(not STATE.new().restore_snapshot(forged), "chave com campo a mais é recusada")
	forged = good.duplicate(true)
	forged.world.harbor_act1_press = {"version": 1, "stage": "press", "choice": "return"}
	check(not STATE.new().restore_snapshot(forged), "escolha diferente da etapa é recusada")
	forged = good.duplicate(true)
	forged.world.harbor_act1_folder = {"version": 1, "stage": "night"}
	check(not STATE.new().restore_snapshot(forged), "M06-B sem M05-B é recusada")

func tow_contract() -> void:
	var data := {"version": 1, "job": {"chain": "debt", "index": 1}, "loaded": false, "unloaded_at_bay": false,
		"truck": {"archetype": "towmaster", "position": [-37.0, .1, 61.0], "yaw": PI, "health": 100, "paint": "ffffffff"},
		"cargo": {"archetype": ACT1.DEBT_CARS[1].model, "position": [404.0, .1, 90.7], "yaw": 0.0, "health": 60, "paint": "983f43ff"}}
	check(MISSION_WORLD.validate_snapshot(data), "serviço de M02-B tem forma válida")
	check(MISSION_WORLD._tow_identity(data.job) == "chain:debt:1", "identidade do serviço de M02-B")
	check(MISSION_WORLD.validate_ownership(data, "", {}, 1), "serviço do carro 2 na etapa tow2")
	check(not MISSION_WORLD.validate_ownership(data, "", {}, 0), "carro errado para a etapa é recusado")
	check(not MISSION_WORLD.validate_ownership(data, "", {}, -1), "serviço sem a missão aberta é recusado")
	check(not MISSION_WORLD.validate_ownership(data, "", {"token": "tow_1"}, 1), "não divide o guincho com um contrato do quadro")
	for bad in [{"chain": "debt", "index": 3}, {"chain": "debt", "index": 1.5}, {"chain": "x", "index": 0}, {"chain": "debt", "index": 0, "story": true}]:
		check(MISSION_WORLD._tow_identity(bad).is_empty(), "serviço forjado recusado: %s" % [bad])
	# Contrato antigo continua igual (três argumentos).
	data.job = {"story": true, "kind": "local"}
	check(MISSION_WORLD.validate_ownership(data, "cobra_contact", {}), "guincho da história de M02 continua válido")

func dialogue_file() -> void:
	var source: Dictionary = LINES.source()
	check(not source.is_empty() and source.get("voice_status") == "subtitles_only", "falas carregam do JSON")
	var speakers := ["Helena", "Helena · telefone", "Dante", "Neco", "Ferrugem"]
	var sections := 0
	for section in source:
		var rows: Variant = source[section]
		if not rows is Array: continue
		sections += 1
		for row in rows:
			check(row is Dictionary and row.size() == 3 and row.get("speaker") in speakers and str(row.get("pt", "")).length() > 0 and row.get("en") is String, "fala bem formada em %s: %s" % [section, row])
			# "Fala curta": uma ideia por fala; nada de parágrafo.
			check(str(row.get("pt", "")).length() <= 130, "fala curta em %s: %s" % [section, row.get("pt", "")])
	for needed in ["m01_armed", "m01_name", "m02_chassis", "ride", "debt_bank", "debt_neco", "press_yard", "wash_dock", "wash_manager", "wash_drawer", "wash_police", "wash_clear", "folder_dock", "folder_handoff", "farewell"]:
		check(source.get(needed) is Array and not LINES.lines(needed).is_empty(), "seção %s existe" % needed)
	check(sections >= 20, "seções de fala (%d)" % sections)
