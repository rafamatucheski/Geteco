extends SceneTree
## Transactional wine stock, healing, intoxication and save validation. The
## Main runner separately verifies physical availability and UI integration.
const WINE := preload("res://gameplay/wine/WineState.gd")
const CATALOG := preload("res://gameplay/wine/WineCatalog.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("CELLAR_WINE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	var wallet := ECONOMY.new()
	var cellar := WINE.new()
	check(cellar.total_servings() == 0 and cellar.intensity() == 0, "new save starts sober without paid bottles")
	check(not cellar.purchase("zacharias_nemea", wallet).ok and wallet.balance == 0 and cellar.total_servings() == 0, "insufficient funds cannot create wine or debt")
	check(wallet.grant_reward("curitiba_cellar_test_funds", 10000), "isolated test wallet funded")
	var countries := {}
	for id: String in CATALOG.ORDER:
		var before := wallet.balance
		var wine := CATALOG.spec(id)
		check(cellar.purchase(id, wallet).ok, "purchase available: " + id)
		check(wallet.balance == before - int(wine.price) and cellar.count(id) == 3, "one debit gives one three-serving bottle: " + id)
		countries[wine.country] = true
	check(countries.size() == 4 and countries.has("Grécia") and countries.has("Brasil") and countries.has("Portugal") and countries.has("Chile"), "all four requested origins have purchasable wines")
	check(WINE.validate_wallet(cellar.snapshot(), wallet.snapshot()), "paid bottle receipts agree with wine serial")
	var before_state := cellar.snapshot()
	var before_wallet := wallet.snapshot()
	check(not cellar.purchase("missing", wallet).ok and cellar.snapshot() == before_state and wallet.snapshot() == before_wallet, "unknown bottle is atomic")
	var sip := cellar.drink("zacharias_nemea", 30.0)
	check(sip.ok and sip.heal > 0 and sip.heal <= 70 and cellar.count("zacharias_nemea") == 2, "drinking consumes exactly one serving and restores missing health")
	check(cellar.intensity() > 0 and cellar.stage() != "Sóbrio", "wine adds persistent alcohol")
	before_state = cellar.snapshot()
	check(not cellar.drink("zacharias_nemea", 30.0).ok and cellar.snapshot() == before_state, "rapid repeated drinking is rejected without consuming another serving")
	cellar.tick(3.0)
	sip = cellar.drink("zacharias_nemea", 97.0)
	check(sip.ok and is_equal_approx(float(sip.heal), 3.0), "healing cannot exceed full health")
	cellar.tick(3.0)
	var before_level := cellar.intensity()
	sip = cellar.drink("zacharias_nemea", 100.0)
	check(sip.ok and float(sip.heal) == 0 and cellar.intensity() > before_level, "full health still allows drinking and intoxication")
	cellar.tick(3.0)
	before_state = cellar.snapshot()
	check(not cellar.drink("zacharias_nemea", 50).ok and cellar.snapshot() == before_state, "empty bottle cannot be consumed")
	check(not cellar.drink("ancla_merlot", 0).ok and cellar.snapshot() == before_state, "dead player cannot recover by consuming wine")
	check(not cellar.drink("ancla_merlot", NAN).ok and cellar.snapshot() == before_state, "nonfinite health cannot corrupt wine state")
	check(not cellar.drink("ancla_merlot", 50).ok and cellar.snapshot() == before_state, "alcohol ceiling blocks another strong drink atomically")
	cellar.tick(NAN)
	cellar.tick(-1)
	check(cellar.snapshot() == before_state, "invalid clock samples preserve alcohol state")
	var restored := WINE.new()
	var serialized: Variant = JSON.parse_string(JSON.stringify(cellar.snapshot()))
	var loaded := restored.restore_snapshot(serialized)
	var equivalent: bool = loaded and restored.data.servings == cellar.data.servings and restored.data.serial == cellar.data.serial and restored.data.gift_claimed == cellar.data.gift_claimed
	equivalent = equivalent and is_equal_approx(float(restored.data.alcohol), float(cellar.data.alcohol)) and is_equal_approx(float(restored.data.cooldown), float(cellar.data.cooldown))
	check(equivalent, "stock and intoxication survive JSON round trip")
	check(WINE.validate_wallet(restored.snapshot(), wallet.snapshot()), "restored wine and payment receipts remain consistent")
	var stock: Dictionary = restored.snapshot().servings
	restored.recover()
	check(restored.intensity() == 0 and restored.data.cooldown == 0 and restored.snapshot().servings == stock, "rescue clears intoxication and preserves purchased bottles")
	cellar.tick(1000)
	check(cellar.intensity() == 0 and cellar.data.cooldown == 0, "elapsed game time naturally restores sobriety")
	check(cellar.claim_gift(), "Nelson's first-visit gift is accessible")
	before_state = cellar.snapshot()
	check(not cellar.claim_gift() and cellar.snapshot() == before_state, "gift cannot duplicate on reentry")
	check(restored.restore_snapshot(cellar.snapshot()) and not restored.claim_gift(), "saved gift receipt prevents duplication after restore")
	var valid := cellar.snapshot()
	var corrupt: Array = [null, {}, []]
	for change in [{"alcohol":NAN}, {"alcohol":INF}, {"alcohol":-1}, {"alcohol":101}, {"cooldown":-1}, {"cooldown":4}, {"serial":1.5}, {"gift_claimed":1}, {"servings":{"fake":1}}, {"servings":{"ancla_merlot":-1}}, {"servings":{"ancla_merlot":1.5}}, {"servings":{"ancla_merlot":37}}]:
		var bad := valid.duplicate(true)
		bad.merge(change, true)
		corrupt.append(bad)
	for index in corrupt.size():
		before_state = restored.snapshot()
		check(not restored.restore_snapshot(corrupt[index]) and restored.snapshot() == before_state, "corrupt save rejected without partial mutation " + str(index))
	var missing_receipt := wallet.snapshot()
	missing_receipt.transactions.erase("spend:curitiba_wine_1")
	check(not WINE.validate_wallet(valid, missing_receipt), "missing debit receipt rejects inconsistent save")
	var forged := valid.duplicate(true)
	forged.serial = 0
	check(not WINE.validate_wallet(forged, wallet.snapshot()), "wine serial cannot rewind paid receipts")
	var conflicting := WINE.new()
	var conflict_wallet := ECONOMY.new()
	conflict_wallet.grant_reward("curitiba_receipt_test", 500)
	conflict_wallet.spend(145, "curitiba_wine_1")
	before_wallet = conflict_wallet.snapshot()
	check(not conflicting.purchase("zacharias_nemea", conflict_wallet).ok and conflict_wallet.snapshot() == before_wallet and conflicting.total_servings() == 0, "preexisting payment receipt cannot mint a duplicate bottle")
	var full := WINE.new()
	var full_wallet := ECONOMY.new()
	full_wallet.grant_reward("curitiba_capacity_test", 10000)
	for bottle in 12: check(full.purchase("ancla_cabernet", full_wallet).ok, "capacity accepts bottle " + str(bottle + 1))
	before_state = full.snapshot()
	before_wallet = full_wallet.snapshot()
	check(not full.purchase("ancla_merlot", full_wallet).ok and full.snapshot() == before_state and full_wallet.snapshot() == before_wallet, "full capacity rejects purchase without debit")
	check(not full.claim_gift() and full.snapshot() == before_state, "full stock does not lose the unclaimed gift")
	print("CELLAR_WINE_RESULT ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
