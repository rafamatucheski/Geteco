extends SceneTree
## Aviso central de dinheiro: crédito mostra "+R$", créditos em sequência somam no mesmo aviso
## (som uma vez), e débito/restauração de save não avisam.
const ECONOMY := preload("res://systems/economy/Economy.gd")
const NOTICE := preload("res://ui/hud/MoneyReceivedNotice.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("MONEY_NOTICE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	var notice := NOTICE.new()
	root.add_child(notice)
	var economy := ECONOMY.new()
	var opened: Array[bool] = []
	var clock := [10000]
	# Mesmo caminho do FullSession: o sinal da carteira alimenta o aviso com a origem do crédito.
	economy.money_gained.connect(func(a): opened.append(notice.receive(a, economy.gain_label, clock[0])))
	var paid: Dictionary = economy.grant_world_reward({"id":"notice_test_cava","kind":"cash","amount":1800,"label":"Limpeza da cava"})
	check(paid.get("ok", false), "recompensa paga")
	check(notice.visible and notice.message.text == "+R$ 1.800", "crédito mostra +R$ 1.800 (%s)" % notice.message.text)
	check(notice.heading.text == "RECEBIDO · Limpeza da cava", "origem aparece no título (%s)" % notice.heading.text)
	check(opened == [true], "primeiro crédito abre aviso (toca som)")
	clock[0] += 400
	economy.collect_loose_cash(200)
	check(notice.message.text == "+R$ 2.000", "segundo crédito em <1 s soma (%s)" % notice.message.text)
	check(opened == [true, false], "crédito somado não repete o som")
	clock[0] += 1500
	economy.grant_reward("notice_test_late", 50)
	check(notice.message.text == "+R$ 50" and opened.back() == true, "crédito depois de 1 s abre aviso novo")
	# Débitos e restauração não emitem.
	var before := opened.size()
	var saved := economy.snapshot()
	check(economy.spend(30, "notice_test_spend"), "débito aceito")
	economy.charge_fee(10)
	var restored := ECONOMY.new()
	restored.money_gained.connect(func(a): opened.append(notice.receive(a, "", clock[0])))
	check(restored.restore_snapshot(saved), "save restaurado")
	check(economy.restore_snapshot(saved), "snapshot restaurado na mesma carteira")
	check(opened.size() == before, "débito, multa e restauração não avisam")
	check(not notice.receive(0) and not notice.receive(-5), "valor zero/negativo não abre aviso")
	print("MONEY_NOTICE ", "PASS" if failures == 0 else "FAIL", " falhas=", failures)
	quit(0 if failures == 0 else 1)
