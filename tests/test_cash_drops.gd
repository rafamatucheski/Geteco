extends SceneTree
const RULES := preload("res://gameplay/CashDropRules.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var failures: Array[String] = []
var checks := 0

class LootHarness extends "res://gameplay/Gameplay.gd":
	# Exercise production drop/collection methods without unrelated police setup.
	func _ready() -> void: set_physics_process(false)
class TestWorld extends Node3D:
	var gameplay: Node3D
class Victim extends Node3D:
	var dead := true
class HeistSession extends RefCounted:
	var world: Node3D
class Heist extends RefCounted:
	var session: RefCounted
class RobberyHarness extends "res://runtime/RobberyActor.gd":
	# Só omite a apresentação; o ponto de entrada real de morte/restauração fica intacto.
	func _ready() -> void: set_physics_process(false)
	func _present_fall(_restored: bool, _impact: Vector3) -> void: pass

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6102026
	var bins := [0,0,0,0,0]
	var smallest := 301
	var largest := 0
	for i in 100000:
		var amount := RULES.roll(rng)
		if amount == 0: bins[0] += 1
		else:
			smallest = mini(smallest,amount)
			largest = maxi(largest,amount)
			bins[1 if amount <= 30 else (2 if amount <= 80 else (3 if amount <= 180 else 4))] += 1
	check(smallest == 5 and largest == 300, "all cash stays within inclusive 5–300, both endpoints reachable")
	for i in 5: check(absf(float(bins[i])/100000.0 - [0.50,0.35,0.10,0.04,0.01][i]) < .005, "fixed sample frequency tier %d: %d" % [i,bins[i]])
	print("CASH_DISTRIBUTION ", bins)
	var scene := TestWorld.new()
	root.add_child(scene)
	var gameplay := LootHarness.new()
	scene.gameplay = gameplay
	gameplay.state = STATE.new()
	gameplay.world = scene
	gameplay.player = CharacterBody3D.new()
	scene.add_child(gameplay.player)
	scene.add_child(gameplay)
	gameplay._cash_rng.seed = 6102026
	# Real civilian death entry points (including inherited port/mountain workers).
	var actors: Array[Node3D] = [preload("res://scripts/Actor.gd").new(),preload("res://gameplay/urban_v1/PortWorker.gd").new(),preload("res://gameplay/urban_v1/UrbanRoutineActor.gd").new(),preload("res://gameplay/urban_v1/TruckersVillageResident.gd").new()]
	for actor in actors:
		if actor.get_script() != preload("res://scripts/Actor.gd"): actor.gameplay = gameplay
		scene.add_child(actor)
		actor.set_physics_process(false)
		actor.receive_damage(5)
		check(not actor.has_meta("cash_drop_rolled"), "nonlethal damage does not roll " + actor.get_script().resource_path)
		actor.receive_damage(1000)
		check(actor.dead and actor.get_meta("cash_drop_rolled",false), "actual death rolls cash " + actor.get_script().resource_path)
		var rng_state: int = gameplay._cash_rng.state
		var count: int = gameplay._loot.size()
		actor.receive_damage(1000)
		gameplay.drop_cash(actor)
		check(gameplay._cash_rng.state == rng_state and gameplay._loot.size() == count, "corpse never rerolls")
	var heist_session := HeistSession.new()
	heist_session.world = scene
	var heist := Heist.new()
	heist.session = heist_session
	for restored_body in [false,true]:
		var clerk := RobberyHarness.new()
		clerk.heist = heist
		scene.add_child(clerk)
		if restored_body: clerk._fall(true)
		else: clerk.receive_damage(1000)
		check(clerk.dead and clerk.has_meta("cash_drop_rolled") == not restored_body, "clerk only drops on a new death, never save restoration")
	gameplay.clear_loot()
	var victim := Victim.new()
	scene.add_child(victim)
	victim.dead = false
	gameplay.drop_cash(victim)
	check(not victim.has_meta("cash_drop_rolled"), "living NPC cannot drop")
	victim.dead = true
	victim.set_meta("invulnerable",true)
	gameplay.drop_cash(victim)
	check(not victim.has_meta("cash_drop_rolled"), "protected residents cannot drop")
	victim.remove_meta("invulnerable")
	for i in 400:
		victim.remove_meta("cash_drop_rolled")
		gameplay.drop_cash(victim)
	check(gameplay._loot.size() == gameplay.MAX_CASH_DROPS, "crowd death burst has bounded cash entities")
	gameplay.clear_loot()
	var pickup: Node3D = gameplay.spawn_loot("cash","",300,Vector3.ZERO)
	gameplay.player.position = Vector3(0,4,0)
	gameplay._update_loot(.1)
	check(gameplay.state.economy.balance == 0, "cash cannot be collected from another floor")
	gameplay.player.position = Vector3.ZERO
	gameplay._update_loot(.1)
	check(gameplay.state.economy.balance == 300 and pickup.consumed and gameplay._loot.is_empty(), "contact collects cash and removes the active pickup")
	check(not gameplay._grant_loot(pickup) and gameplay.state.economy.balance == 300, "duplicate collection cannot pay twice")
	check(gameplay.state.economy.snapshot().transactions.is_empty(), "recurring cash never grows permanent receipt history")
	var store := STORE.new()
	store.path = "user://cash_drop_test_%d/progress.json" % Time.get_ticks_usec()
	check(store.save(gameplay.state) == OK, "cash wallet saves through production SaveStore")
	var restored := STATE.new()
	check(store.load_into(restored).get("ok",false) and restored.economy.balance == 300, "collected cash survives disk reload")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(store.path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path.get_base_dir()))
	for amount in [-1,0,4,301]: check(not restored.economy.collect_loose_cash(amount), "reject invalid cash amount %d" % amount)
	gameplay.state.economy._data.balance = gameplay.state.economy.LIMIT
	var full: Node3D = gameplay.spawn_loot("cash","",5,Vector3.ZERO)
	gameplay._update_loot(.1)
	check(not full.consumed and not full.cash_credited, "full wallet leaves cash collectable")
	gameplay._update_loot(36)
	check(gameplay._loot.is_empty(), "uncollected cash expires")
	for place in ["maciota","harbor_garage"]:
		gameplay.state.set_location("harbor",place)
		check(not gameplay.state.weapons_allowed() and not gameplay.attack_allowed(), "garage weapon restriction preserved " + place)
	await create_timer(.3).timeout
	check(not is_instance_valid(pickup) and not is_instance_valid(full), "collected and expired entities are freed")
	scene.free()
	print("CASH_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
