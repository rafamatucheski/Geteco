extends SceneTree
const PROGRESS := preload("res://activities/motocross/MotocrossProgress.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const STATE := preload("res://runtime/GameState.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	var progress := PROGRESS.new()
	var wallet := ECONOMY.new()
	check(not progress.begin(wallet,0),"sem dinheiro não entra")
	check(not progress.begin(wallet,-1) and not progress.begin(wallet,4),"nível inválido rejeitado")
	wallet.grant_reward("fixture",2000)
	check(not progress.begin(wallet,1),"nível superior bloqueado")
	check(progress.begin(wallet,0) and wallet.balance==1900,"inscrição debitada na largada")
	check(not progress.begin(wallet,0) and wallet.balance==1900,"não cobra duas inscrições simultâneas")
	check(PROGRESS.validate_wallet(progress.snapshot(),wallet.snapshot()),"inscrição pendente consistente com carteira")
	check(progress.settle(wallet,false)==0 and wallet.balance==1900,"derrota perde a inscrição")
	check(progress.settle(wallet,true)==0 and wallet.balance==1900,"derrota não pode virar pagamento posterior")
	check(progress.begin(wallet,0),"nova tentativa tem recibo próprio")
	check(progress.settle(wallet,true)==140 and wallet.balance==1940,"vitória devolve100 e lucro40")
	check(progress.settle(wallet,true)==0 and wallet.balance==1940,"prêmio não duplica")
	check(progress.data.unlocked==1 and not progress.data.owned,"iniciante desbloqueia intermediário")
	check(progress.begin(wallet,1) and progress.settle(wallet,true)==280,"intermediário paga entrada mais lucro")
	check(progress.data.owned and progress.data.unlocked==2,"vitória intermediária dá moto e avançado")
	check(PROGRESS.validate_wallet(progress.snapshot(),wallet.snapshot()),"vitórias conferem com recibos")
	var restored := PROGRESS.new()
	check(restored.restore_snapshot(progress.snapshot()) and restored.data.owned,"propriedade da moto persiste")
	check(restored.begin(wallet,2),"avançado liberado")
	var pending := restored.snapshot()
	var loaded := PROGRESS.new()
	loaded.restore_snapshot(pending)
	var balance := wallet.balance
	loaded.settle(wallet,false)
	check(wallet.balance==balance and loaded.data.active==-1,"recarregar tentativa interrompida não reembolsa")
	var bad := loaded.snapshot()
	bad.wins[0] = -1
	check(not loaded.restore_snapshot(bad),"snapshot corrupto rejeitado sem mutação")
	bad = loaded.snapshot()
	bad.serial = 50
	check(not PROGRESS.validate_wallet(bad,wallet.snapshot()),"serial sem recibos rejeitado")
	var state := STATE.new()
	state.economy = wallet
	state.world_state.motocross = loaded.snapshot()
	check(STATE.new().restore_snapshot(state.snapshot()),"save real restaura carteira e motocross juntos")
	check(STATE.new().restore_snapshot(JSON.parse_string(JSON.stringify(state.snapshot()))),"save JSON preserva contagens numéricas do motocross")
	var corrupt := state.snapshot()
	corrupt.world.motocross.owned = false
	check(not STATE.new().restore_snapshot(corrupt),"save real rejeita propriedade adulterada")
	var rental_balance := wallet.balance
	check(loaded.rent(wallet) and wallet.balance==rental_balance-35,"aluguel cobra35 por sessão")
	check(PROGRESS.validate_wallet(loaded.snapshot(),wallet.snapshot()),"recibo de aluguel validado no save")
	check(loaded.rent(wallet) and wallet.balance==rental_balance-70,"segundo aluguel usa recibo novo")
	var invalid_rental := loaded.snapshot()
	invalid_rental.rental_serial = 20
	check(not PROGRESS.validate_wallet(invalid_rental,wallet.snapshot()),"aluguel sem recibo rejeitado")
	print("MOTOCROSS_PROGRESS ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)
