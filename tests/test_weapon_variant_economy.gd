extends SceneTree
## Purchase, physical inventory, scarce drops and real isolated save/load.
const ECONOMY := preload("res://systems/economy/Economy.gd")
const GRID := preload("res://systems/inventory/GridInventory.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const MIGRATION := preload("res://systems/inventory/InventoryMigration.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
const NEW_WEAPONS := ["pistol_suppressed", "smg_compact", "smg_tactical", "shotgun_auto"]
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	print("VARIANT_ECONOMY ", "PASS " if ok else "FAIL ", label)

func run() -> void:
	for id: String in NEW_WEAPONS:
		var economy := ECONOMY.new()
		var before := economy.snapshot()
		check(not economy.purchase("weapon", id, "poor").ok and economy.snapshot() == before, id + " insufficient funds is atomic")
		economy.grant_reward("funds", 20000)
		economy.enable_grid_inventory()
		economy.grid_equip_bag("backpack")
		var price := int(CATALOG.WEAPONS[id].price)
		check(economy.purchase("weapon", id, "buy").ok and economy.balance == 20000-price, id + " shop charges the listed price")
		var owned := economy.snapshot()
		check(economy.purchase("weapon", id, "buy").ok and economy.snapshot() == owned, id + " purchase receipt cannot duplicate weapon or ammo")
		check(not economy.purchase("weapon", id, "again").ok and economy.snapshot() == owned, id + " second purchase rejected")
		check(economy.can_carry_weapon(id) and economy.equip_weapon(id), id + " belongs to a usable personal slot")
		var slot := "longa" if id == "shotgun_auto" else "curta"
		check(economy.personal_loadout()[slot] == id, id + " correct loadout slot")
		var ammo := economy.get_ammo(id)
		check(economy.buy_ammo(id, 12, "refill"), id + " ammunition can be purchased")
		check(int(economy.get_ammo(id).reserve) == int(ammo.reserve)+12, id + " purchased ammunition goes to that variant")
		var paid := economy.snapshot()
		check(economy.buy_ammo(id, 12, "refill") and economy.snapshot() == paid, id + " ammo receipt is idempotent")
		check(economy.consume_ammo(id) and economy.reload_weapon(id), id + " reload works with owned ammunition")
		check(economy.get_ammo(id).magazine + economy.get_ammo(id).reserve == ammo.magazine+ammo.reserve+11, id + " reload conserves rounds")
		var copy := ECONOMY.new()
		check(copy.restore_snapshot(JSON.parse_string(JSON.stringify(economy.snapshot()))) and copy.snapshot() == economy.snapshot(), id + " inventory and receipts survive JSON restore")
		_drop_contract(id)
	_discovery_and_capacity()
	_purchase_with_existing_sidearm()
	_attachment_capacity()
	_legacy_save()
	_save_and_garage()
	print("VARIANT_ECONOMY_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func _drop_contract(id: String) -> void:
	var economy := ECONOMY.new()
	economy.enable_grid_inventory()
	check(economy.collect_weapon_drop(id, 17), id + " floor weapon can be collected")
	var first := economy.get_ammo(id)
	check(first.magazine + first.reserve == 17, id + " floor pickup grants exactly its rounds, no free store reserve")
	check(first.magazine == mini(17, int(CATALOG.WEAPONS[id].magazine_size)), id + " dropped weapon loads available rounds")
	check(economy.collect_weapon_drop(id, 9), id + " owned duplicate replenishes ammunition")
	check(economy.get_ammo(id).magazine + economy.get_ammo(id).reserve == 26, id + " duplicate adds exactly nine rounds")
	check(ECONOMY.validate_snapshot(economy.snapshot()), id + " drop preserves unique physical ownership")
	var before := economy.snapshot()
	check(not economy.collect_weapon_drop(id, 0) and not economy.collect_weapon_drop(id, ECONOMY.MAX_AMMO+1) and economy.snapshot() == before, id + " invalid drop is atomic")
	check(GRID.extent({"id":"weapon:"+id}) == Vector2i(4 if id == "shotgun_auto" else 2, 1), id + " correct bag footprint")

func _discovery_and_capacity() -> void:
	var economy := ECONOMY.new()
	economy.grant_reward("funds", 20000)
	check(not economy.is_weapon_unlocked("smg") and not economy.purchase("weapon", "smg", "locked").ok, "MP5 remains discovery gated")
	economy.collect_weapon_drop("smg_compact", 12)
	check(not economy.is_weapon_unlocked("smg"), "compact SMG does not unlock the mountain MP5")
	economy.discover("mountain_cargo_plane_smg_01")
	check(economy.purchase("weapon", "smg", "discovered").ok, "mountain discovery still unlocks MP5")
	var full := ECONOMY.new()
	full.enable_grid_inventory()
	full.collect_weapon_drop("pistol", 99)
	full.grant_item("water", 5)
	full.grant_item("apple", 5)
	full.grant_reward("funds", 10000)
	var before := full.snapshot()
	check(not full.collect_weapon_drop("pistol_suppressed", 12) and full.snapshot() == before, "full pockets reject new variant atomically")
	check(not full.collect_weapon_drop("pistol", 12) and full.snapshot() == before, "full linked ammunition and pockets leave duplicate on ground")
	check(not full.purchase("weapon", "smg_compact", "full").ok and full.snapshot() == before, "full inventory purchase keeps cash and receipt unchanged")
	check(not full.collect_weapon_drop("unknown_variant", 12) and full.snapshot() == before, "unknown weapon rejected")
	var varied := ECONOMY.new()
	varied.enable_grid_inventory()
	varied.grid_equip_bag("backpack")
	for id in ["shotgun", "sawed_off", "shotgun_auto"]:
		check(varied.collect_weapon_drop(id, 12), id + " coexists physically in shotgun loadout")
	check(ECONOMY.validate_snapshot(varied.snapshot()), "three shotgun variants preserve inventory ownership")

func _legacy_save() -> void:
	var old := ECONOMY.new()
	for id: String in MIGRATION.LEGACY_ARSENAL:
		if id == "fists": continue
		old.grant_weapon(id)
	var legacy := old.snapshot()
	for id in legacy.weapons:
		if int(legacy.weapons[id].reserve) >= 0: legacy.weapons[id].reserve = 9999
	var restored := ECONOMY.new()
	check(restored.restore_snapshot(legacy), "pre-variant arsenal save still restores")
	restored.enable_grid_inventory()
	check(restored.get_ammo("pistol").magazine + restored.get_ammo("pistol").reserve == 99, "old persistent cheat recognized without requiring newly added weapons")
	for id: String in NEW_WEAPONS:
		check(not restored.owns_weapon(id), "legacy save does not grant unearned " + id)
	check(ECONOMY.validate_snapshot(restored.snapshot()), "legacy inventory migration retains valid ownership")

func _purchase_with_existing_sidearm() -> void:
	# A progressão normal já carrega a pistola inicial. As SMGs novas e a munição
	# incluída precisam caber na mochila sem forçar o slot curto a ficar vazio.
	for id: String in ["smg_compact", "smg_tactical", "smg"]:
		var economy := ECONOMY.new()
		economy.enable_grid_inventory()
		economy.grid_equip_bag("backpack")
		economy.grant_weapon("pistol")
		economy.grant_reward("budget", 10000)
		if id == "smg": economy.discover("mountain_cargo_plane_smg_01")
		check(economy.purchase("weapon", id, "bag_purchase").ok, id + " purchase succeeds beside carried starter pistol")
		check(economy.personal_loadout().curta == "pistol" and GRID.count(economy.grid_snapshot(), "weapon:"+id) == 1, id + " purchase preserves starter slot and stores variant physically")
		var total := int(economy.get_ammo(id).magazine)+int(economy.get_ammo(id).reserve)
		check(total == int(CATALOG.WEAPONS[id].magazine_size)+int(CATALOG.WEAPONS[id].starting_reserve), id + " entire purchased ammo pack fits alongside the weapon")
		check(ECONOMY.validate_snapshot(economy.snapshot()), id + " bag purchase retains valid unique ownership")

func _attachment_capacity() -> void:
	for id: String in NEW_WEAPONS + ["smg", "ak47"]:
		var economy := ECONOMY.new()
		economy.grant_weapon(id)
		economy.add_ammo(id, 100)
		var part := "drum" if id in ["smg", "smg_compact", "smg_tactical", "ak47"] else "extended"
		check(CUSTOM.supports(id, part), id + " supports displayed magazine option")
		var customization := {}
		customization[id] = {"parts":{"magazine":part}}
		var capacity := int(CUSTOM.effective_data(id, customization).magazine_size)
		check(economy.reload_weapon(id, capacity) and economy.get_ammo(id).magazine == capacity, id + " reload accepts actual customized capacity")
		var copy := ECONOMY.new()
		check(copy.restore_snapshot(JSON.parse_string(JSON.stringify(economy.snapshot()))), id + " customized capacity survives save")

func _save_and_garage() -> void:
	var state := STATE.new()
	state.economy.enable_grid_inventory()
	state.economy.grid_equip_bag("backpack")
	state.economy.grant_reward("variant_budget", 20000)
	for id: String in NEW_WEAPONS:
		check(state.economy.collect_weapon_drop(id, 12), "save fixture owns " + id)
	state.equip_weapon("pistol_suppressed")
	var original := state.economy.snapshot()
	state.set_location("harbor", "maciota")
	check(state.equipped_weapon == "fists" and not state.can_attack(), "garage entry holsters new variants")
	for id: String in NEW_WEAPONS:
		check(not state.equip_weapon(id) and not state.consume_ammo(id) and not state.reload_weapon(id), "garage blocks equip/fire/reload of " + id)
	var store := STORE.new()
	store.path = OS.get_temp_dir().path_join("geteco-weapon-variants-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]).path_join("progress.json")
	check(store.save(state) == OK, "save variants in isolated disk slot")
	var loaded := STATE.new()
	check(store.load_into(loaded).get("ok", false), "load variants through production SaveStore")
	check(loaded.equipped_weapon == "fists" and not loaded.can_attack(), "restored garage remains weapon free")
	check(loaded.economy.snapshot().weapons == original.weapons, "save/load retains each variant and exact ammunition")
	loaded.set_location("harbor", "")
	check(loaded.equip_weapon("pistol_suppressed") and loaded.can_attack(), "variant available after leaving garage")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(store.path+suffix): DirAccess.remove_absolute(store.path+suffix)
	DirAccess.remove_absolute(store.path.get_base_dir())
