extends SceneTree
const STATE := preload("res://runtime/GameState.gd")
const POLICY := preload("res://runtime/ShopSafety.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	var state := STATE.new()
	state.economy.grant_weapon("pistol")
	var inventory_before: Dictionary = state.economy.snapshot()
	var shops: Array = POLICY.IDS.duplicate()
	for definition in preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").definitions():
		if POLICY.peaceful(definition.id): shops.append(definition.id)
	print("PEACEFUL_SHOP_INVENTORY count=",shops.size()," ids=",shops)
	for id: String in shops:
		state.set_location("mountain" if id.begins_with("mountain") or id == "ski_lodge" else "desert" if id == "desert_digo" else "harbor", id)
		check(not state.weapons_allowed() and not state.can_attack(), id + " blocks all combat")
		check(state.equipped_weapon == "fists" and not state.equip_weapon("pistol"), id + " holsters and rejects drawing")
		check(not state.consume_ammo("pistol") and not state.reload_weapon("pistol"), id + " rejects ammo use/reload")
		check(not POLICY.admission_allowed(id,1) and not POLICY.admission_allowed(id,5) and POLICY.admission_allowed(id,0), id + " requires lost police")
	check(state.economy.snapshot().weapons == inventory_before.weapons, "holstering preserves owned weapons")
	state.set_location("harbor", "harbor_curitiba_cellar")
	var restored := STATE.new()
	check(restored.restore_snapshot(state.snapshot()), "shop snapshot restores")
	check(not restored.can_attack() and restored.equipped_weapon == "fists", "shop restore reapplies restriction")
	state.set_location("harbor")
	check(state.weapons_allowed() and state.equip_weapon("pistol"), "exit permits drawing again")
	check(POLICY.admission_allowed("harbor_bank",5), "bank assault remains available")
	check(POLICY.peaceful("harbor_building_torque_store"), "retail building shares shop protection")
	check(not POLICY.admission_allowed("harbor_building_torque_store",1), "retail building also blocks police")
	state.set_location("harbor", "harbor_bank")
	check(state.weapons_allowed(), "bank keeps combat")
	for id in ["maciota", "harbor_garage"]:
		state.set_location("harbor", id)
		check(not state.can_attack(), id + " retains protection")
	var room := Node3D.new()
	room.set_meta("invulnerable",true)
	root.add_child(room)
	for identity in ["cellar_luisa", "cellar_nelson"]:
		var actor := ACTOR.new()
		actor.set_meta("interior_npc_id",identity)
		actor.set_physics_process(false)
		room.add_child(actor)
		actor.set_physics_process(false)
		actor.receive_damage(10000)
		check(PROTECTION.is_protected(actor) and actor.health == 100 and not actor.dead, identity + " ignores lethal direct damage")
	room.queue_free()
	await process_frame
	print("SHOP_SAFETY checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
