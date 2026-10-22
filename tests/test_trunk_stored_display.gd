extends SceneTree
## A trunk presentation must follow transfers, not Dante's carried loadout.
class InventoryState:
	extends RefCounted
	var economy
class InventorySession:
	extends RefCounted
	var state
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func _initialize() -> void:
	var economy := preload("res://systems/economy/Economy.gd").new()
	economy.enable_grid_inventory()
	economy.grant_weapon("pistol")
	economy.grant_weapon("m4a1")
	var state := InventoryState.new()
	state.economy = economy
	var session := InventorySession.new()
	session.state = state
	var runtime := preload("res://systems/inventory/FieldInventoryRuntime.gd").new()
	runtime.session = session
	check(runtime.trunk_display_loadout().values().all(func(id): return id == ""), "Carried weapons appeared in an empty trunk")
	check(economy.grid_store_weapon("m4a1", "trunk"), "Fixture could not store the carried rifle")
	economy.grant_weapon("shotgun")
	check(economy.grid_store_weapon("shotgun", "trunk"), "Fixture could not store a second long weapon")
	var before: Dictionary = economy.snapshot()
	var shown: Dictionary = runtime.trunk_display_loadout()
	check(shown.longa == "m4a1" and shown.curta == "", "Display did not use the first actually stored rifle; carried pistol leaked into trunk")
	check(economy.snapshot() == before, "Reading the display mutated inventory")
	var entries: Array = economy.grid_snapshot().trunk
	var rifle_index := -1
	for i in entries.size():
		if entries[i].id == "weapon:m4a1": rifle_index = i
	check(rifle_index >= 0 and economy.grid_equip_weapon("trunk", rifle_index), "Native rifle retrieval failed")
	check(runtime.trunk_display_loadout().longa == "shotgun", "Retrieved rifle remained as a ghost; remaining stored shotgun was not shown")
	runtime.free()
	print("TRUNK_STORED_DISPLAY ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
