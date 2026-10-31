extends SceneTree
## Contratos reais de Economy/SaveStore; a rota de UI de produção é renderizada à parte.
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const VENDING := preload("res://activities/amusement_park/AmusementParkVending.gd")
const SITE := preload("res://world/places/amusement_park/ParkLume.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var checks := 0

class World extends Node3D:
	var player
	var gameplay := {"health":100.0}
	var driving := {"occupied":false}

class Session extends Node:
	var state = STATE.new()
	var world
	var ready_for_play := true
	var modal := false
	var blocked := false
	var menu_closed := Callable()
	var store = STORE.new()
	var saves := 0
	func is_transition_blocked() -> bool: return blocked
	func _menu(_title: String) -> void:
		modal = true
		world.player.input_locked = true
	func _button(_label: String, _callback: Callable) -> void: pass
	func show_message(_message: String) -> void: pass
	func close_menu() -> void:
		modal = false
		world.player.input_locked = false
		var callback := menu_closed
		menu_closed = Callable()
		if callback.is_valid(): callback.call()
	func save_game(_manual := false) -> bool:
		saves += 1
		return store.save(state) == OK

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PARK_VENDING ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func run() -> void:
	var session := Session.new()
	session.store.path = "user://tests/park_vending_%d/progress.json" % Time.get_ticks_usec()
	root.add_child(session)
	var world := World.new()
	root.add_child(world)
	session.world = world
	world.player = ACTOR.new()
	world.player.is_player = true
	world.add_child(world.player)
	world.player.set_physics_process(false)
	var park := SITE.new()
	world.add_child(park)
	var vending := VENDING.new()
	vending.configure(session)
	vending.set_site(park)
	for frame in 3: await physics_frame
	check(vending.nearest_action().is_empty(), "machines cannot be used remotely")
	world.player.teleport(park.to_global(VENDING.MACHINES.drinks.approach))
	check(not vending.nearest_action().is_empty(), "walking to machine exposes functional interaction")
	check(vending.open("drinks"), "machine opens at its front")
	var token: String = vending.offer_token("drinks", "water")
	var before: Dictionary = session.state.economy.snapshot()
	check(not vending.buy("drinks", "water", token).ok and session.state.economy.snapshot() == before, "insufficient money changes neither item nor wallet nor stock")
	check(vending.remaining("drinks", "water") == 24, "refused purchase keeps displayed stock")
	session.state.economy.grant_reward("park_vending_fixture", 2000)
	var initial_cash: int = session.state.economy.balance
	check(vending.buy("drinks", "water", token).ok, "paid drink enters existing inventory")
	check(session.state.economy.balance == initial_cash - 6 and session.state.economy.inventory.get("water", 0) == 1 and vending.remaining("drinks", "water") == 23, "one purchase charges catalog price and consumes exactly one unit")
	before = session.state.economy.snapshot()
	check(vending.buy("drinks", "water", token).reason == "already_applied" and session.state.economy.snapshot() == before, "same stale button receipt cannot charge or deliver twice")
	check(not vending.buy("drinks", "sandwich", token).ok and session.state.economy.snapshot() == before, "drink machine rejects item or token from another product")
	check(session.saves == 1, "only new successful purchase schedules durable checkpoint")
	var loaded := STATE.new()
	check(loaded.restore_snapshot(STORE.read_valid(session.store.path)), "real isolated save restores purchased inventory and receipt")
	session.state = loaded
	check(vending.remaining("drinks", "water") == 23 and session.state.economy.inventory.get("water", 0) == 1, "restored stock and item survive save/load together")
	token = vending.offer_token("drinks", "juice")
	before = session.state.economy.snapshot()
	world.gameplay.health = 0
	check(not vending.buy("drinks", "juice", token).ok and session.state.economy.snapshot() == before, "death invalidates open purchase")
	world.gameplay.health = 100
	session.close_menu()
	vending.open("drinks")
	world.driving.occupied = true
	check(not vending.buy("drinks", "juice", token).ok, "vehicle occupant cannot complete stale purchase")
	world.driving.occupied = false
	session.close_menu()
	vending.open("drinks")
	session.blocked = true
	check(not vending.buy("drinks", "juice", token).ok, "transition invalidates stale purchase")
	session.blocked = false
	session.close_menu()
	vending.open("drinks")
	world.player.teleport(park.to_global(Vector3(34, .08, 12)))
	check(not vending.buy("drinks", "juice", token).ok and session.state.economy.snapshot() == before, "leaving machine cannot remotely debit inventory")
	session.close_menu()
	world.player.teleport(park.to_global(VENDING.MACHINES.drinks.approach))
	session.state.economy.enable_grid_inventory()
	# Duas células de bolso; pilhas cheias impedem que esta bebida diferente caiba.
	session.state.economy.grant_item("water", 4)
	session.state.economy.grant_item("apple", 5)
	vending.open("drinks")
	before = session.state.economy.snapshot()
	check(vending.buy("drinks", "juice", token).reason == "inventory_full" and session.state.economy.snapshot() == before, "full spatial inventory preserves money stock and existing stacks")
	session.close_menu()
	session.state.economy = ECONOMY.new()
	session.state.economy.grant_reward("stock_fixture", 1000)
	vending.open("drinks")
	for unit in 24:
		check(vending.buy("drinks", "water", vending.offer_token("drinks", "water")).ok, "finite water stock unit %d" % (unit + 1))
	before = session.state.economy.snapshot()
	check(vending.remaining("drinks", "water") == 0 and not vending.buy("drinks", "water", "").ok and session.state.economy.snapshot() == before, "empty machine refuses further debit and never has negative stock")
	session.close_menu()
	vending.set_site(null)
	check(vending.nearest_action().is_empty() and not vending.open("drinks"), "unloaded park has no remote machine interaction")
	world.free()
	session.free()
	print("PARK_VENDING_RESULT ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
