extends SceneTree
const RULES := preload("res://activities/fishing/FishingRules.gd")
const STATE := preload("res://activities/fishing/FishingState.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_species_and_fight()
	_economy_and_save()
	_wallet_full()
	print("FISHING_RULES ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FISHING_RULES " + title)

func _species_and_fight() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919
	var found := {}
	var valid := true
	for i in 700:
		var fish := RULES.roll(rng, float(i % 11) / 10.0)
		valid = valid and RULES.valid_catch(fish)
		found[fish.id] = true
	check(valid and found.size() == RULES.SPECIES.size(), "todas as espécies sorteáveis mantêm peso dentro dos limites físicos")
	check(not RULES.valid_catch({"id":"tubarao", "grams":1000}) and not RULES.valid_catch({"id":"tilapia", "grams":NAN}), "espécie desconhecida e peso não finito rejeitados")
	check(not RULES.valid_catch({"id":"pintado", "grams":14000.5}), "peso fracionário em gramas rejeitado")
	check(RULES.winner(5001, [{"grams":5000}]), "peixe mais pesado ganha por um grama")
	check(not RULES.winner(5000, [{"grams":5000}]) and not RULES.winner(0, []), "empate e nenhuma captura não premiam")
	var ranking := RULES.ranking(8000, [{"name":"Lia", "grams":9500}, {"name":"Rui", "grams":1000}])
	check(ranking[0].name == "Lia" and ranking[1].player, "placar ordena peso e identifica Dante")
	for strength in [.22, .64, 1.0]:
		var fight := RULES.Fight.new()
		fight.begin(strength)
		var reeling := true
		for i in 2400:
			if fight.tension > .72: reeling = false
			elif fight.tension < .3: reeling = true
			if not fight.update(1.0 / 60.0, reeling).is_empty(): break
		check(fight.outcome == "caught", "manejo de tensão captura peixe de força %.2f" % strength)
	var broken := RULES.Fight.new()
	broken.begin(.7)
	for i in 600:
		if not broken.update(1.0 / 60.0, true).is_empty(): break
	check(broken.outcome == "line_broke" and broken.progress < 1.0, "recolher sem aliviar rompe a linha antes da captura")
	var slack := RULES.Fight.new()
	slack.begin(.5)
	for i in 600:
		if not slack.update(1.0 / 60.0, false).is_empty(): break
	check(slack.outcome == "escaped", "deixar linha frouxa perde o peixe")
	var previous := broken.progress
	broken.update(10, true)
	check(broken.progress == previous and broken.outcome == "line_broke", "resultado de luta é terminal e não vira captura")

func _economy_and_save() -> void:
	var world := {}
	var economy := ECONOMY.new()
	check(STATE.validate_world(world, economy.snapshot()), "save antigo sem pesca é compatível")
	check(not STATE.validate_world(world, {"transactions":0}), "carteira malformada falha sem chamar métodos de dicionário")
	check(not STATE.validate_world(world, {"transactions":{"reward:fishing:prize:1":0}}), "recibo malformado é rejeitado antes de consultar prêmio")
	check(STATE.begin(world, economy, -1) == 0 and world.is_empty(), "falta de saldo não inicia nem modifica estado")
	economy.grant_reward("fixture_fishing", 1000)
	check(STATE.begin(world, economy, 9) == 0 and economy.balance == 1000, "modalidade inválida não cobra")
	var serial := STATE.begin(world, economy, -1)
	check(serial == 1 and economy.balance == 990, "entrada cobra dez uma vez")
	check(STATE.begin(world, economy, 0) == 0 and economy.balance == 990, "duas inscrições simultâneas são rejeitadas")
	check(STATE.record_catch(world, serial, {"id":"tilapia", "grams":1400}), "pesca livre registra captura legítima")
	check(not STATE.record_catch(world, serial, {"id":"tilapia", "grams":9000}), "peixe adulterado não altera recorde")
	check(STATE.finish(world, serial, false) and STATE.claim(world, economy) == 0, "sair preserva captura sem prêmio nem reembolso")
	check(STATE.data(world).best == 1400 and STATE.data(world).catches == 1, "recorde e quantidade persistem ao encerrar")
	for tier in 3:
		serial = STATE.begin(world, economy, tier)
		check(serial > 0 and STATE.record_catch(world, serial, {"id":"pintado", "grams":14000}), "campeonato aceita captura para modalidade %d" % tier)
		check(STATE.finish(world, serial, true, [{"name":"Lia", "grams":13999}]), "resultado válido encerra campeonato")
		var before := int(economy.balance)
		var paid := STATE.claim(world, economy)
		check(paid == (tier + 1) * 100 and economy.balance == before + paid, "vitória paga o prêmio exato de %d" % ((tier + 1) * 100))
		check(STATE.claim(world, economy) == 0 and not STATE.finish(world, serial, true, []), "prêmio e conclusão são idempotentes")
	check(STATE.validate_world(world, economy.snapshot()), "recibos de entrada e prêmios conferem com o estado")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(world))
	check(STATE.validate_world(loaded, JSON.parse_string(JSON.stringify(economy.snapshot()))), "round-trip JSON conserva pesos, recibos e campeonatos")
	var balance := int(economy.balance)
	check(STATE.claim(loaded, economy) == 0 and economy.balance == balance, "recarregar save não duplica prêmio")
	serial = STATE.begin(world, economy, 2)
	check(STATE.finish(world, serial, false) and STATE.claim(world, economy) == 0, "campeonato interrompido nunca premia")
	var corrupt := world.duplicate(true)
	corrupt.fishing.serial += 1
	check(not STATE.validate_world(corrupt, economy.snapshot()), "serial inventado sem entrada é rejeitado")
	corrupt = world.duplicate(true)
	corrupt.fishing.rewards.erase("2")
	check(not STATE.validate_world(corrupt, economy.snapshot()), "recibo pago sem vitória correspondente rejeitado")
	corrupt = world.duplicate(true)
	corrupt.fishing.species.pintado = 999999
	check(not STATE.valid(corrupt.fishing), "recorde impossível rejeitado")

func _wallet_full() -> void:
	var world := {}
	var economy := ECONOMY.new()
	economy.grant_reward("fixture_pending", 100)
	var serial := STATE.begin(world, economy, 0)
	STATE.record_catch(world, serial, {"id":"pintado", "grams":13000})
	STATE.finish(world, serial, true, [{"name":"Lia", "grams":12999}])
	economy.grant_reward("fixture_fill", ECONOMY.LIMIT - economy.balance)
	check(STATE.claim(world, economy) == 0 and STATE.validate_world(world, economy.snapshot()), "carteira cheia conserva prêmio pendente válido")
	economy.spend(200, "fixture_space")
	check(STATE.claim(world, economy) == 100 and STATE.claim(world, economy) == 0, "prêmio pendente paga uma vez após liberar saldo")
