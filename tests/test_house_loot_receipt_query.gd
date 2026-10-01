extends SceneTree
## Real economy + loot adapter; presentation fixture is a membership witness.
## Actual home geometry/collection stays covered by test_truckers_village_house_loot.
const ECONOMY := preload("res://systems/economy/Economy.gd")
const LOOT := preload("res://gameplay/urban_v1/TruckersVillageHouseLoot.gd")

class CountingEconomy extends "res://systems/economy/Economy.gd":
	var snapshot_calls := 0
	func snapshot() -> Dictionary:
		snapshot_calls += 1
		return super.snapshot()

class PlayerFixture extends Node3D:
	var dead := false

class StashFixture extends Node3D:
	var available := true
	var updates := 0
	func set_available(value: bool, _animated := false) -> void:
		available = value
		updates += 1

class HomesFixture extends Node3D:
	var homes: Array = []
	var current_home := -1
	func house_at(_point: Vector3) -> int: return -1

class SessionFixture extends RefCounted:
	var world: Dictionary
	var state: Dictionary
	var ready_for_play := true
	var messages := 0
	func show_message(_message: String) -> void: messages += 1

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("HOUSE_LOOT_RECEIPT ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func tick(loot: Node) -> void:
	loot._scan = 0.0
	loot._process(.2)

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("HOUSE_LOOT_RECEIPT requires --no-save")
		quit(2)
		return
	var economy := CountingEconomy.new()
	var scene := Node3D.new()
	root.add_child(scene)
	var homes := HomesFixture.new()
	scene.add_child(homes)
	for _index in 3:
		var stash := StashFixture.new()
		homes.add_child(stash)
		homes.homes.append({"loot":stash})
	var player := PlayerFixture.new()
	scene.add_child(player)
	var session := SessionFixture.new()
	session.world = {"player":player,"gameplay":{"health":100.0},"driving":{"occupied":true}}
	session.state = {"region_id":"harbor","place_id":"","economy":economy}
	var loot := LOOT.new()
	scene.add_child(loot)
	loot.set_process(false)
	loot.configure(session, homes)
	check(economy.grant_reward("tonico_home_stash_0",120), "fixture registers first receipt")
	tick(loot)
	check(not homes.homes[0].loot.available and homes.homes[1].loot.available, "driving still reconciles taken and available stashes")
	check(economy.balance == 120 and session.messages == 0, "driving does not collect additional reward")
	check(economy.snapshot_calls == 0, "driving scan does not clone economy")
	check(economy.grant_reward("tonico_home_stash_1",180), "fixture registers later receipt")
	tick(loot)
	check(not homes.homes[1].loot.available, "new receipt is reflected while still driving")
	check(economy.snapshot_calls == 0, "later scan does not clone economy")
	player.dead = true
	session.world.driving.occupied = false
	tick(loot)
	check(economy.balance == 300 and homes.homes[2].loot.available, "dead player cannot collect an untaken stash")
	check(economy.snapshot_calls == 0, "dead scan also avoids deep copy")
	var updates: int = homes.homes[0].loot.updates
	session.state.region_id = "mountain"
	tick(loot)
	check(homes.homes[0].loot.updates == updates, "other-region gate stays unchanged")
	session.state.region_id = "harbor"
	session.state.place_id = "other_place"
	tick(loot)
	check(homes.homes[0].loot.updates == updates, "separate-place gate stays unchanged")
	var has_accessor := economy.has_method("has_reward_receipt")
	check(has_accessor, "narrow read-only receipt accessor exists")
	if has_accessor:
		check(economy.call("has_reward_receipt","tonico_home_stash_0") == true, "accessor finds recorded reward")
		check(economy.call("has_reward_receipt","tonico_home_stash_2") == false, "missing reward is absent")
		check(economy.spend(1,"tonico_home_stash_2"), "fixture records same id in spend namespace")
		check(economy.call("has_reward_receipt","tonico_home_stash_2") == false, "spend receipt cannot impersonate reward")
		var saved: Dictionary = economy.snapshot()
		var restored := ECONOMY.new()
		check(restored.restore_snapshot(saved), "receipt state restores through existing snapshot contract")
		check(restored.call("has_reward_receipt","tonico_home_stash_0") == true, "restored receipt remains visible to accessor")
		saved.transactions.erase("reward:tonico_home_stash_0")
		check(economy.call("has_reward_receipt","tonico_home_stash_0") == true and restored.call("has_reward_receipt","tonico_home_stash_0") == true, "snapshot isolation is unchanged")
		var before := economy.balance
		check(not economy.grant_reward("tonico_home_stash_0",120) and economy.balance == before, "query does not alter reward idempotence")
		check(economy.grant_reward("zero_payload",0) and economy.call("has_reward_receipt","zero_payload") == true, "zero-payload reward receipt is recognized")
	print("HOUSE_LOOT_RECEIPT checks=",checks," failures=",failures)
	scene.free()
	quit(0 if failures == 0 else 1)
