extends SceneTree
## Bilhete do trem (RailwayFares): tarifa por zona, destinos, débito na carteira real, recusa
## sem saldo e a garantia de não cobrar duas vezes o mesmo embarque. Lógica pura, sem mundo.
const FARES := preload("res://runtime/railway/RailwayFares.gd")
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("RAILWAY_FARES ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)


func run() -> void:
	check(FARES.fare("harbor_central", "harbor_north") == 15, "Central-Northgate is same-zone R$ 15")
	check(FARES.fare("harbor_north", "mountain_pines") == 25, "Harbor-Pinhais R$ 25")
	check(FARES.fare("mountain_pines", "harbor_central") == 25, "fare is symmetric")
	check(FARES.fare("harbor_central", "desert_copper") == 40, "Harbor-Cobre R$ 40")
	check(FARES.fare("desert_copper", "mountain_pines") == 35, "Pinhais-Cobre R$ 35")
	check(FARES.fare("harbor_central", "harbor_central") == -1, "same station has no fare")
	check(FARES.fare("harbor_central", "missing") == -1, "unknown station has no fare")
	# Todo par de estações reais tem preço útil (R$ 15-40), para nenhum destino aparecer de graça.
	for a in NETWORK.stations():
		for b in NETWORK.stations():
			if a.id == b.id: continue
			var price := FARES.fare(str(a.id), str(b.id))
			check(price >= 15 and price <= 40, "fare in useful range: %s>%s" % [a.id, b.id])

	var wallet = ECONOMY.new()
	check(wallet.collect_loose_cash(50), "wallet seeded")
	var ticket := {}
	var first: Dictionary = FARES.buy(wallet, "harbor_central", "mountain_pines", 1, ticket)
	check(first.ok and first.charged == 25 and wallet.balance == 25, "ticket debits wallet once")
	var repeat: Dictionary = FARES.buy(wallet, "harbor_central", "mountain_pines", 1, ticket)
	check(repeat.ok and repeat.charged == 0 and wallet.balance == 25, "same boarding never charged twice")
	var refused: Dictionary = FARES.buy(wallet, "harbor_central", "desert_copper", 2, ticket)
	check(not refused.ok and refused.charged == 0 and wallet.balance == 25, "insufficient balance refuses without debit")
	check(str(refused.reason).contains("R$ 40"), "refusal names the price")
	check(ticket.paid_key == FARES.ticket_key("harbor_central", "mountain_pines", 1), "refusal keeps previous ticket")
	var next: Dictionary = FARES.buy(wallet, "harbor_central", "harbor_north", 2, ticket)
	check(next.ok and next.charged == 15 and wallet.balance == 10, "new boarding is a new ticket")
	var invalid: Dictionary = FARES.buy(wallet, "harbor_central", "harbor_central", 3, ticket)
	check(not invalid.ok and wallet.balance == 10, "invalid trip never charges")
	check(not FARES.buy(null, "harbor_central", "harbor_north", 4, {}).ok, "missing wallet refuses")
	print("RAILWAY_FARES %s %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
