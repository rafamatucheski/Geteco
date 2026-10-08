extends SceneTree
## Native collision and actual lockpick/economy integration. FullSession walking
## and save-store round trips are covered by the separate production fixture.
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const CONTENT := preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const NATIVE := preload("res://world/places/NativePlace.gd")
const SECRETS := preload("res://world/places/harbor_buildings/HarborBuildingSecrets.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []

class Session extends RefCounted:
	var world: Dictionary
	var state: Dictionary
	var modal := false
	var blocked := false
	var saves := 0
	var notice := ""
	func is_transition_blocked() -> bool: return blocked
	func save_game() -> void: saves += 1
	func show_message(message: String) -> void: notice = message
	func close_menu() -> void:
		modal = false
		world.player.input_locked = false

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("BUILDING_SECRETS ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(3))
	var definition := {}
	var index := 0
	for candidate in CATALOG.definitions():
		for floor_index in int(candidate.floor_count):
			if not CONTENT.secret_spec(candidate, floor_index).is_empty():
				definition = candidate.duplicate(true)
				index = floor_index
				break
		if not definition.is_empty(): break
	check(not definition.is_empty(), "at least one authored physical locked room")
	if definition.is_empty(): quit(1); return
	definition.building_floor_index = index
	definition.rewards = CONTENT.floor_rewards(definition, index)
	var stage := Node3D.new()
	root.add_child(stage)
	var room := NATIVE.new()
	room.definition = definition
	stage.add_child(room)
	var player := ACTOR.new()
	player.is_player = true
	player.controlled_automatically = true
	stage.add_child(player)
	player.set_physics_process(false)
	var session := Session.new()
	session.world = {"player":player, "gameplay":{"health":100.0}}
	session.state = {"economy":ECONOMY.new(), "world_state":{}}
	var secrets := SECRETS.populate(room, definition, index, session)
	var spec := CONTENT.secret_spec(definition, index)
	var approach: Vector3 = spec.door_position + Vector3(.7, .04, 0)
	player.teleport(approach)
	await physics_frame
	await physics_frame
	check(not player.test_move(player.global_transform, Vector3.UP * .002), "real player fits authored door approach")
	check(player.test_move(player.global_transform, Vector3.LEFT * 1.4), "closed door physically blocks a swept player")
	check(not secrets.perform(), "missing lockpick cannot open door")
	check(not session.modal and not player.input_locked, "missing item leaves control available")
	check(session.state.economy.grant_item("lockpick", 2), "two real inventory tools admitted")
	player.position += Vector3.BACK * 3.0
	check(not secrets.perform(), "remote use rejected")
	player.teleport(approach)
	check(secrets.perform(), "actual minigame begins near locked door")
	check(session.modal and player.input_locked and secrets.lockpick.active, "minigame owns input while active")
	secrets.lockpick.finish(false)
	check(session.state.economy.inventory.get("lockpick", 0) == 2 and not secrets.opened, "cancel does not consume item or open door")
	check(not session.modal and not player.input_locked, "cancel restores player control")
	check(secrets.perform(), "second minigame can begin after cancel")
	for pin in secrets.lockpick.required_pins:
		secrets.lockpick.angle = secrets.lockpick.target_angle
		secrets.lockpick.attempt()
	check(secrets.opened and not secrets.lockpick.active, "actual correct pin attempts unlock door")
	check(session.state.economy.inventory.get("lockpick", 0) == 1, "success consumes exactly one carried lockpick")
	check(CONTENT.valid_unlocks(session.state.world_state.harbor_building_unlocks, CATALOG.definitions()), "unlock state conforms to catalog")
	check(not CONTENT.valid_unlocks({"unknown":true}, CATALOG.definitions()), "unknown door state rejected")
	check(not CONTENT.valid_unlocks({spec.id:1}, CATALOG.definitions()), "nonboolean unlock state rejected")
	check(player.test_move(player.global_transform, Vector3.LEFT * 1.4), "door remains physical during its opening motion")
	await create_timer(.38).timeout
	await physics_frame
	check(not player.test_move(player.global_transform, Vector3.LEFT * 1.4), "opened passage admits the complete swept body")
	check(not secrets.perform() and session.state.economy.inventory.get("lockpick", 0) == 1, "opened door cannot consume another lockpick")
	var cash: Dictionary = {}
	for reward in definition.rewards:
		if reward.get("kind", "") == "cash": cash = reward; break
	check(not cash.is_empty(), "secret chamber contains its authored cash")
	if not cash.is_empty():
		check(room.is_floor_clear(cash.local_position, .32), "cash lies on an accessible free floor footprint")
		var first: Dictionary = session.state.economy.grant_world_reward(cash)
		var balance: int = session.state.economy.balance
		var restored_economy := ECONOMY.new()
		check(restored_economy.restore_snapshot(session.state.economy.snapshot()), "cash receipt survives economy snapshot restore")
		var repeated: Dictionary = restored_economy.grant_world_reward(cash)
		check(first.ok and repeated.ok and not repeated.changed and restored_economy.balance == balance, "reentry receipt cannot duplicate secret cash")
	room.free()
	room = NATIVE.new()
	room.definition = definition
	stage.add_child(room)
	secrets = SECRETS.populate(room, definition, index, session)
	await physics_frame
	await physics_frame
	check(secrets.opened and not player.test_move(player.global_transform, Vector3.LEFT * 1.4), "restored opened door is visually and physically open")
	check(session.state.economy.inventory.get("lockpick", 0) == 1, "door restoration spends no further item")
	# Fresh unopened state for interrupted/death paths; the durable wallet is kept.
	room.free()
	session.state.world_state = {}
	room = NATIVE.new()
	room.definition = definition
	stage.add_child(room)
	secrets = SECRETS.populate(room, definition, index, session)
	await physics_frame
	check(secrets.perform(), "fresh door begins before death interruption")
	session.world.gameplay.health = 0.0
	# SceneTree.process_frame fires before the nodes' _process callbacks. The
	# second boundary observes one completed cancellation tick rather than the
	# same boundary at which the zero-health value was written.
	await process_frame
	await process_frame
	check(not secrets.lockpick.active and not secrets.opened and not session.modal, "death cancels UI without unlocking")
	check(session.state.economy.inventory.get("lockpick", 0) == 1 and not secrets.perform(), "dead player cannot spend tools or open rooms")
	session.world.gameplay.health = 100.0
	check(secrets.perform(), "living recovery can start a new attempt")
	secrets.set_active(false)
	check(not secrets.lockpick.active and not secrets.lockpick.visible and not session.modal, "inactive room cannot retain a CanvasLayer or input lock")
	check(not secrets.perform(), "inactive room rejects a new lockpicking attempt")
	secrets.set_active(true)
	check(secrets.perform(), "reactivated room can use the same unconsumed lock")
	room.free()
	check(not session.modal and not player.input_locked, "unloading owned minigame releases UI and control")
	print(JSON.stringify({"test":"harbor_building_secrets", "checks":checks, "failures":failures}))
	stage.queue_free()
	quit(0 if failures.is_empty() else 1)
