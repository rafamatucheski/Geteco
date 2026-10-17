extends SceneTree
## Transaction contracts only; does not certify rendered menus or lake access.
const ITEMS := preload("res://activities/fishing/FishingCatchItems.gd")
const RULES := preload("res://activities/fishing/FishingRules.gd")
const GRID := preload("res://systems/inventory/GridInventory.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const FIELD := preload("res://systems/inventory/FieldInventoryRuntime.gd")
var checks := 0
var failures: Array[String] = []

class QuietField extends FIELD:
	func _update_carried() -> void: pass

class SessionStub extends RefCounted:
	var state := {"economy":ECONOMY.new()}
	var world := {"gameplay":{"health":70.0}}
	var controller := {"save_invalid":false}
	var field_inventory
	var saved := 0
	var save_ok := true
	func save_block_reason() -> String: return "" if save_ok else "fixture blocked"
	func save_game() -> bool: saved += 1; return save_ok

class FailingSave extends SessionStub:
	func save_block_reason() -> String: return ""
	func save_game() -> bool: saved += 1; return false

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	print("FISHING_ITEMS ", "PASS " if value else "FAIL ", message)
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var fish := {"id":"tilapia", "grams":1600}
	var id := ITEMS.make_id(fish)
	check(id == "fish:tilapia:1600" and ITEMS.parse_id(id) == fish, "canonical species and integer grams")
	for definition in RULES.SPECIES:
		for grams in [definition.min, definition.max]:
			var key := ITEMS.make_id({"id":definition.id, "grams":grams})
			check(not key.is_empty() and ITEMS.parse_id(key).grams == grams and ITEMS.sale_price(key) > 0, "valid species weight bound " + key)
	for malformed in ["fish:unknown:1000", "fish:tilapia:0", "fish:tilapia:999999", "fish:tilapia:01600", "fish:tilapia:+1600", "fish:tilapia:1.6", "fish:tilapia:1600:extra", "fish::1600", "fish:tilapia:-1600"]:
		check(ITEMS.parse_id(malformed).is_empty() and GRID.spec(malformed).is_empty(), "reject invalid item " + malformed)
	check(ITEMS.make_id({"id":"tilapia", "grams":1600.5}).is_empty(), "fractional grams rejected")
	check(GRID.spec(id).stack == 1 and not GRID.spec(id).has("heal"), "raw fish is unstacked and cannot be eaten for healing")
	check(GRID.spec(id).label.contains("Tilápia") and GRID.spec(id).label.contains("1,600 kg"), "raw label preserves species and exact weight")
	check(GRID.spec("cooked_fish").heal == 35, "prepared fish uses existing consumable healing")
	var economy := ECONOMY.new()
	economy.enable_grid_inventory()
	var before := economy.snapshot()
	var stored := ITEMS.store_candidate(before, fish)
	check(not stored.is_empty() and economy.snapshot() == before, "store candidate does not mutate source")
	check(economy.restore_snapshot(stored) and economy.inventory[id] == 1, "store commits real carried inventory")
	check(economy.grant_item(id), "second identical catch occupies its own cell")
	before = economy.snapshot()
	check(ITEMS.store_candidate(before, fish).is_empty() and economy.snapshot() == before, "full pockets refuse another catch without deleting anything")
	var sold := ITEMS.sale_candidate(before, id, "fishing_sale_1")
	check(not sold.is_empty() and sold.inventory[id] == 1 and sold.balance == ITEMS.sale_price(id), "sale removes exactly one identical fish and pays its weight")
	check(ITEMS.sale_candidate(sold, id, "fishing_sale_1").is_empty(), "replayed sale cannot consume second identical fish")
	var restored := ECONOMY.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(sold))), "sold catch and receipt survive JSON restore")
	check(ITEMS.sale_candidate(restored.snapshot(), id, "fishing_sale_1").is_empty(), "sale replay remains rejected after restore")
	var capped := before.duplicate(true)
	capped.balance = ECONOMY.LIMIT - 1
	check(ITEMS.sale_candidate(capped, id, "fishing_sale_2").is_empty() and capped.inventory[id] == 2, "wallet cap preserves both fish")
	var cooked := ITEMS.cook_candidate(before, id, "fishing_cook_1")
	check(not cooked.is_empty() and cooked.inventory[id] == 1 and cooked.inventory.cooked_fish == 1 and cooked.balance == before.balance, "full pockets cook by atomically reusing the removed raw slot")
	check(ITEMS.cook_candidate(cooked, id, "fishing_cook_1").is_empty(), "replayed recipe cannot consume another identical fish")
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(cooked))), "cooked item and receipt survive JSON restore")
	check(ITEMS.cook_candidate(restored.snapshot(), id, "fishing_cook_1").is_empty(), "recipe replay remains rejected after restore")
	check(ITEMS.sale_candidate(cooked, "cooked_fish", "fishing_sale_2").is_empty(), "only raw catches enter fish sale pricing")
	var bag_economy := ECONOMY.new()
	bag_economy.enable_grid_inventory()
	bag_economy.grid_equip_bag("backpack")
	bag_economy.grant_item("water", 5)
	bag_economy.grant_item("apple", 5)
	bag_economy.grant_item(id)
	var bag := bag_economy.grid_drop_bag("harbor", "", Vector3.ZERO)
	before = bag_economy.snapshot()
	check(ITEMS.sale_candidate(before, id, "fishing_sale_3").is_empty() and ITEMS.cook_candidate(before, id, "fishing_cook_3").is_empty(), "dropped bag fish cannot be sold or cooked remotely")
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(before))) and restored.grid_recover_bag(bag) and restored.inventory[id] == 1, "dropped fish retains identity when restored and recovered")
	var legacy := ECONOMY.new()
	check(not legacy.grant_item("fish:tilapia:0001600"), "ungridded grant cannot bypass strict catch identity")
	var forged := legacy.snapshot()
	forged.inventory["fish:tilapia:0001600"] = 1
	check(not ECONOMY.validate_snapshot(forged), "ungridded malformed catch save rejected")
	var session := SessionStub.new()
	var field := QuietField.new()
	session.field_inventory = field
	field.session = session
	session.state.economy.enable_grid_inventory()
	check(ITEMS.can_store(session, fish) and ITEMS.store(session, fish) and session.saved == 0, "field storage stays in memory until fishing settles its decision")
	before = session.state.economy.snapshot()
	session.world.gameplay.health = 0
	check(not ITEMS.store(session, fish) and session.state.economy.snapshot() == before, "dead player cannot store a pending catch")
	session.world.gameplay.health = 70
	session.controller.save_invalid = true
	check(not ITEMS.store(session, fish), "invalid save cannot accept new catch items")
	session.controller.save_invalid = false
	var candidate := ITEMS.cook_candidate(before, id, "fishing_cook_1")
	check(field.commit_candidate(before, candidate) and session.saved == 1 and session.world.gameplay.health == 70, "cooking saves one atomic conversion and does not heal immediately")
	check(not field.commit_candidate(before, candidate), "stale candidate cannot overwrite a later inventory")
	var fail_session := FailingSave.new()
	var fail_field := QuietField.new()
	fail_session.field_inventory = fail_field
	fail_field.session = fail_session
	fail_session.state.economy.enable_grid_inventory()
	fail_session.state.economy.grant_item(id)
	before = fail_session.state.economy.snapshot()
	candidate = ITEMS.sale_candidate(before, id, "fishing_sale_1")
	check(not fail_field.commit_candidate(before, candidate) and fail_session.state.economy.snapshot() == before, "failed disk save restores fish, wallet and receipt together")
	field.free()
	fail_field.free()
	print("FISHING_ITEMS_RESULT ", checks, " checks ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
