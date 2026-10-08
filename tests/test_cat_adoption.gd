extends SceneTree
const CATS := preload("res://runtime/cats/CatAdoption.gd")
const RESIDENCE := preload("res://activities/Residence.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_progression_and_move()
	_furniture_and_wallet()
	_restore_contract()
	print("CAT_ADOPTION ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CAT_ADOPTION " + title)

func _session(economy, player: Node3D) -> Dictionary:
	return {
		"state":{"economy":economy, "region_id":"harbor", "place_id":"", "checkpoint_id":""},
		"world":{"player":player, "gameplay":{"health":100}, "driving":{"occupied":false}},
	}

func _progression_and_move() -> void:
	var home := RESIDENCE.new()
	var economy := ECONOMY.new()
	var player := Node3D.new()
	home.session = _session(economy, player)
	economy.grant_reward("cats_progression_fixture", 50000)
	check(not home.cats_unlocked() and not home.adopt_cat("cat_01"), "sem casa não libera nem adota gato")
	check(not home.buy_cat_furniture("bed") and economy.balance == 50000, "sem casa não compra nem cobra caminha")
	player.position = home.entry("westgate_garden")
	check(home.buy("westgate_garden") and home.cats_unlocked(), "compra real da primeira casa libera adoção")
	check(not home.adopt_cat("cat_11") and home.cat_count() == 0, "identidade desconhecida não é coletável")
	var unique := {}
	for id in CATS.CAT_IDS:
		unique[id] = true
		check(home.adopt_cat(id), "adota identidade " + id)
		check(not home.adopt_cat(id), "mesmo gato não pode ser adotado duas vezes: " + id)
	check(unique.size() == 10 and home.cat_count() == 10, "coleção termina exatamente em 10 gatos distintos")
	var external: Array[String] = home.adopted_cats()
	external.clear()
	check(home.cat_count() == 10, "consulta de gatos não permite apagar a coleção")
	home.session.state.place_id = "westgate_garden"
	check(home.buy_cat_furniture("bed") and home.buy_cat_furniture("ball"), "caminha e brinquedo adquiridos na casa")
	var before: Dictionary = home.snapshot().cats
	home.session.state.place_id = ""
	player.position = home.entry("quayside_house")
	check(home.buy("quayside_house"), "troca real de residência concluída")
	check(home.data.active_home == "quayside_house" and home.snapshot().cats == before, "todos os gatos e itens acompanham a mudança sem novo pagamento")
	check(not home.can_enter("westgate_garden"), "casa anterior deixa de ser destino ativo")
	var restored := RESIDENCE.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(home.snapshot()))), "save JSON restaura a coleção da casa nova")
	check(restored.cat_count() == 10 and restored.cat_furniture() == home.cat_furniture(), "restauração mantém todos os gatos e compras")
	check(not restored.adopt_cat("cat_01"), "recarregar não recria adoção")
	player.free()

func _furniture_and_wallet() -> void:
	var home := RESIDENCE.new()
	var economy := ECONOMY.new()
	var player := Node3D.new()
	home.session = _session(economy, player)
	home.data.active_home = "westgate_garden"
	home.data.purchases = 1
	home.session.state.place_id = "westgate_garden"
	check(not home.buy_cat_furniture("ball") and home.cat_furniture().ball == 0, "saldo insuficiente não cria brinquedo")
	economy.grant_reward("cats_furniture_fixture", 5000)
	var before := int(economy.balance)
	home.session.state.place_id = ""
	check(not home.buy_cat_furniture("bed"), "compra fora da casa é rejeitada")
	home.session.state.place_id = "quayside_house"
	check(not home.buy_cat_furniture("bed"), "compra em casa não possuída é rejeitada")
	home.session.state.place_id = "westgate_garden"
	home.session.world.gameplay.health = 0
	check(not home.buy_cat_furniture("bed"), "jogador morto não compra")
	home.session.world.gameplay.health = 100
	home.session.world.driving.occupied = true
	check(not home.buy_cat_furniture("bed"), "jogador no carro não compra")
	home.session.world.driving.occupied = false
	check(not home.buy_cat_furniture("unknown") and economy.balance == before, "recusas não debitam a carteira")
	var expected_spend := 0
	for id in CATS.FURNITURE:
		var item: Dictionary = CATS.FURNITURE[id]
		for i in int(item.limit):
			check(home.buy_cat_furniture(id), "compra de %s %d aceita dentro da capacidade" % [id, i + 1])
			expected_spend += int(item.price)
		check(not home.buy_cat_furniture(id), "limite de " + id + " impede cobrança extra")
	check(economy.balance == before - expected_spend, "cada item cobra o preço exato uma única vez")
	var furniture: Dictionary = home.cat_furniture()
	furniture.bed = 0
	check(home.cat_furniture().bed == int(CATS.FURNITURE.bed.limit), "consulta de móveis não altera o estado")
	var loaded := RESIDENCE.new()
	var loaded_wallet := ECONOMY.new()
	check(loaded.restore_snapshot(JSON.parse_string(JSON.stringify(home.snapshot()))), "móveis sobrevivem a save JSON")
	check(loaded_wallet.restore_snapshot(JSON.parse_string(JSON.stringify(economy.snapshot()))), "carteira e recibos sobrevivem a save JSON")
	loaded.session = _session(loaded_wallet, player)
	loaded.session.state.place_id = "westgate_garden"
	check(not loaded.buy_cat_furniture("bed") and loaded_wallet.balance == economy.balance, "recarregar não reinicia capacidade nem debita novamente")
	player.free()

func _restore_contract() -> void:
	var home := RESIDENCE.new()
	var legacy := home.snapshot()
	legacy.erase("cats")
	check(home.restore_snapshot(legacy) and home.cat_count() == 0, "save antigo sem gatos migra vazio")
	home.data.active_home = "westgate_garden"
	home.data.purchases = 1
	home.adopt_cat("cat_01")
	var baseline := home.snapshot()
	for patch in [null, {}, {"adopted":["cat_01", "cat_01"], "furniture":{"bed":0,"ball":0,"scratcher":0}}, {"adopted":["unknown"], "furniture":{"bed":0,"ball":0,"scratcher":0}}, {"adopted":[1], "furniture":{"bed":0,"ball":0,"scratcher":0}}]:
		var corrupt := baseline.duplicate(true)
		corrupt.cats = patch
		check(not home.restore_snapshot(corrupt) and home.snapshot() == baseline, "estado malformado rejeitado sem apagar progresso")
	for amount in [-1, int(CATS.FURNITURE.bed.limit) + 1, 1.5, NAN, INF, "2", null]:
		var corrupt := baseline.duplicate(true)
		corrupt.cats.furniture.bed = amount
		check(not RESIDENCE.validate_snapshot(corrupt), "quantidade inválida de caminhas rejeitada: " + str(amount))
	var homeless := baseline.duplicate(true)
	homeless.active_home = ""
	check(not RESIDENCE.validate_snapshot(homeless), "save não aceita gatos sem casa")
	homeless.cats.adopted = []
	homeless.cats.furniture.ball = 1
	check(not RESIDENCE.validate_snapshot(homeless), "save não aceita brinquedos comprados sem casa")
	var unknown := baseline.duplicate(true)
	unknown.cats.furniture.unknown = 1
	check(not RESIDENCE.validate_snapshot(unknown), "móvel desconhecido não é aceito no save")
	var old_home := baseline.duplicate(true)
	old_home.erase("cats")
	check(home.restore_snapshot(old_home) and home.cat_count() == 0 and home.cat_furniture().bed == 0, "restaurar save antigo em instância reutilizada limpa coleção anterior")
