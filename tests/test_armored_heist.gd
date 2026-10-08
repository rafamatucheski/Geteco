extends SceneTree
## Runtime, native lockpick and real economy in a controlled exterior fixture.
## Vehicle travel, dispatch response and Main admission are deliberately separate.
const TRANSPORT := preload("res://gameplay/armored/ArmoredTransport.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
class Player extends CharacterBody3D:
	var input_locked := false
class Guard extends Node3D:
	var health := 110.0
	var dead := false
class Car extends CharacterBody3D:
	var health := 1200.0
	var traffic := true
	var controlled := false
	var route := Curve3D.new()
	var speed := 0.0
	var half_width := 1.1
	var half_length := 2.8
	var opened := false
	var empty := false
	var player_authored := false
	func door_point() -> Vector3: return global_position + Vector3(0, .4, 3.6)
	func set_vault(value: bool, taken := false) -> void:
		opened = value
		empty = taken
	func is_player_damage_source() -> bool: return player_authored
class Game extends Node:
	signal weapon_fired(weapon: String, origin: Vector3)
	signal explosion_occurred(origin: Vector3, radius: float, source: Node)
	signal player_died
	signal player_arrested
	var health := 100.0
	var stars := 0
	var player: Node3D
	var reports: Array[Dictionary] = []
	func pursuit_target() -> Node3D: return player
	func register_crime(points: int, point: Vector3, kind: String, testimony: Dictionary = {}) -> void:
		reports.append({"points":points, "point":point, "kind":kind, "testimony":testimony})
class Controller extends RefCounted:
	var vehicles: Array = []
	func _on_screen(_point: Vector3, _margin: float) -> bool: return false
class World extends Node3D:
	var player: Player
	var gameplay: Game
	var driving := {"occupied":false, "car":null}
class Session extends RefCounted:
	var state = preload("res://runtime/GameState.gd").new()
	var world: World
	var controller := Controller.new()
	var ready_for_play := true
	var modal := false
	var messages: Array[String] = []
	func is_transition_blocked() -> bool: return false
	# This fixture does not admit crew; the real actor/ballistic fixture owns that.
	func position_clear(_point: Vector3) -> bool: return false
	func show_message(message: String) -> void: messages.append(message)
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): print("ARMORED_HEIST watchdog"); quit(3))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("ARMORED_HEIST ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func fixture(level := 0, urban := true, id := "1:0") -> Dictionary:
	var world := World.new()
	root.add_child(world)
	current_scene = world
	world.player = Player.new()
	world.add_child(world.player)
	world.gameplay = Game.new()
	world.gameplay.player = world.player
	world.add_child(world.gameplay)
	var session := Session.new()
	session.world = world
	session.state.economy.grant_item("lockpick", 3)
	var event := TRANSPORT.new()
	event.configure(session)
	event.data = SCHEDULE.initial({"id":id, "origin":"harbor_bank", "destination":"desert_bank"}, level)
	# Stopped on the road, with service doors closed: the lockpick applies here.
	event.data.phase = "driving"
	event.security_level = level
	event.last_event = id
	event.profile = SCHEDULE.security(level)
	world.add_child(event)
	event.set_process(false)
	event.set_physics_process(false)
	event.minigame.set_process(false)
	var point: Vector3 = event.banks.harbor_bank.entry_position if urban else Vector3(6000, 0, 6000)
	world.player.position = point
	for index in 4:
		var car := Car.new()
		world.add_child(car)
		car.position = point + Vector3(index * 8, 0, -3.6)
		event.fleet.append(car)
		session.controller.vehicles.append(car)
	return {"world":world, "session":session, "event":event, "game":world.gameplay}
func solve(lock: CanvasLayer) -> void:
	lock.angle = lock.target_angle
	for index in 15: lock.step(.1, 0, true)
func break_pick(lock: CanvasLayer) -> void:
	lock.angle = -85 if lock.target_angle >= 0 else 85
	for index in 30: lock.step(.1, 0, true)
func check_crew_stations() -> void:
	for level in [0, 2, 5]:
		var f := fixture(level)
		var event: Node3D = f.event
		event.fleet[2].rotation.y = .6
		event.fleet[3].rotation.y = -.7
		var stations: Dictionary = {}
		var separated := true
		var beside_doors := true
		var capacity := true
		for index in int(event.profile.crew_count):
			var seat: int = event._seat(index)
			var car: Node3D = event.fleet[seat]
			var point: Vector3 = event._crew_point(index)
			var local: Vector3 = car.to_local(point)
			beside_doors = beside_doors and absf(local.x) >= car.half_width + .3 and absf(local.z) <= car.half_length - .25
			if not stations.has(seat): stations[seat] = []
			for previous in stations[seat]:
				separated = separated and point.distance_to(previous) >= .85
			stations[seat].append(point)
		for seat in stations:
			capacity = capacity and stations[seat].size() <= (1 if seat < 2 else 4)
		check(separated, "crew boarding points leave room for distinct bodies at security level %d" % level)
		check(beside_doors, "crew posts remain beside the rotated vehicle doors, outside its hull at security level %d" % level)
		check(capacity, "finite crew fits one carrier per truck and four guards per escort at security level %d" % level)
		f.world.free()
func check_wreck_ownership() -> void:
	# Off-tree real vehicle classes: exercise their lifetime/collision contract
	# directly without constructing unrelated vehicle visuals or simulating travel.
	for script in [preload("res://gameplay/dispatch/DispatchVehicle.gd"), preload("res://gameplay/armored/ArmoredTruck.gd")]:
		var wreck: CharacterBody3D = script.new()
		wreck.health = 0.0
		wreck.controlled = false
		wreck.collision_layer = 4
		wreck.collision_mask = 7
		wreck.set_meta("armored_transport", true)
		var removed: bool = wreck._tick_wreck(12.0) or wreck._tick_wreck(60.0)
		check(not removed and not wreck.is_queued_for_deletion() and wreck._wreck_fade < 0.0 and wreck.collision_layer == 4 and wreck.collision_mask == 7, "convoy owns the visible wreck lifetime and physical obstruction: " + script.resource_path.get_file())
		wreck.free()
	var ordinary := preload("res://gameplay/dispatch/DispatchVehicle.gd").new()
	ordinary.health = 0.0
	ordinary.controlled = false
	ordinary.collision_layer = 4
	ordinary.collision_mask = 7
	ordinary._tick_wreck(10.0)
	check(ordinary._wreck_fade == 0.0 and ordinary.collision_layer == 0 and ordinary.collision_mask == 0, "ordinary dispatch wreck still starts its standard fade and releases collision")
	check(ordinary._tick_wreck(2.0) and ordinary.is_queued_for_deletion(), "ordinary dispatch wreck retains its standard twelve-second disposal")
	ordinary.free()
func run() -> void:
	check_wreck_ownership()
	check_crew_stations()
	var f := fixture()
	var event: Node3D = f.event
	var yielding := preload("res://gameplay/traffic_yield/TrafficYieldController.gd").new()
	event.fleet[0].set_physics_process(true)
	check(yielding._yieldable(event.fleet[0]), "ordinary moving traffic remains eligible to yield to a siren")
	event.fleet[0].set_meta("armored_transport", true)
	check(not yielding._yieldable(event.fleet[0]), "siren controller cannot take over the convoy private route while traffic physics drives it")
	yielding.free()
	var original_profile: Dictionary = event.profile.duplicate(true)
	event.provoke(null)
	event.provoke(event.fleet[0])
	check(not event.data.hostile and event.security_level == 0, "null/environment and NPC vehicle sources cannot accuse Dante")
	event.provoke(f.world.player)
	check(event.data.hostile and event.security_level == 1 and event.data.escalated, "first player attack escalates the next trip once")
	event.provoke(f.world.player)
	check(event.security_level == 1 and event.profile == original_profile and event.data.security_level == 0, "repeat attacks preserve current profile and do not multiply escalation")
	var urban_delay: float = event.data.report_remaining
	event._tick_alarm(urban_delay - .1)
	check(f.game.reports.is_empty(), "urban radio respects its short reaction window")
	event._tick_alarm(.2)
	event._tick_alarm(20)
	check(f.game.reports.size() == 1 and f.game.reports[0].kind == "alarm", "one actual radio report reaches crime registration")
	event._persist()
	var restored := TRANSPORT.new()
	restored.configure(f.session)
	check(restored.security_level == 1 and restored.data.security_level == 0 and restored.data.hostile, "save restore preserves future escalation and current convoy snapshot")
	var next := SCHEDULE.initial({"id":"3:1", "origin":"desert_bank", "destination":"harbor_bank"}, restored.security_level)
	check(SCHEDULE.security(next.security_level).road_report_delay < original_profile.road_report_delay, "next departure calls the police sooner after the robbery")
	restored.free()
	f.world.free()
	f = fixture(0, false)
	event = f.event
	event.fleet[0].player_authored = true
	event.provoke(event.fleet[0])
	check(event.data.hostile and event.data.report_remaining > urban_delay, "player-authored vehicle attack is attributed and rural radio is slower")
	event._tick_alarm(100.0)
	event._persist()
	check(event.data.reported and event.data.report_remaining == 0 and SCHEDULE.valid_saved(f.session.state.world_state[SCHEDULE.KEY]), "long frame crossing the radio deadline preserves a valid nonnegative saved timer")
	f.world.free()
	f = fixture(6, false)
	event = f.event
	event.provoke(f.world.player)
	check(event.security_level == 6 and event.data.reported and f.game.reports.size() == 1, "maximum security transmits immediately even on a rural road")
	f.world.free()
	f = fixture()
	event = f.event
	f.session.state.place_id = "harbor_garage"
	event._gunfire("pistol", f.world.player.global_position)
	check(not event.data.hostile, "an interior weapon event cannot alarm the exterior convoy")
	f.session.state.place_id = ""
	event._gunfire("fists", f.world.player.global_position)
	check(not event.data.hostile, "an unconnected punch nearby is not gunfire against the convoy")
	var wall := StaticBody3D.new()
	var obstruction := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(100, 4, .3)
	obstruction.shape = wall_shape
	wall.add_child(obstruction)
	f.world.add_child(wall)
	wall.position = f.world.player.global_position + Vector3(0, 2, -1.8)
	for index in 2: await physics_frame
	event._gunfire("pistol", f.world.player.global_position)
	check(not event.data.hostile, "a solid wall prevents attributing nearby shots to an unseen player")
	wall.free()
	for index in 2: await physics_frame
	event._gunfire("pistol", f.world.player.global_position)
	check(event.data.hostile, "nearby visible player gunfire alarms the convoy through its real signal handler")
	f.world.free()

	f = fixture()
	event = f.event
	var balance: int = f.session.state.economy.balance
	check(event.perform(0) and event.minigame.active and f.session.modal and f.world.player.input_locked, "rear interaction starts the real lockpick and locks movement")
	check(not event.save_block_reason().is_empty(), "saving is blocked while the lockpick is active")
	break_pick(event.minigame)
	check(f.session.state.economy.inventory.get("lockpick",0) == 2 and not event.data.opened[0], "breaking the real lockpick consumes exactly one item without opening the door")
	check(not event.minigame.active and not f.session.modal and not f.world.player.input_locked, "broken lockpick releases the interaction controls")
	check(event.perform(0), "failed attempt can be retried with the remaining inventory")
	solve(event.minigame)
	check(event.data.opened[0] and event.fleet[0].opened and f.session.state.economy.inventory.get("lockpick",0) == 2, "solved cylinder opens the visible vault without consuming an unbroken pick")
	event._explosion(event.fleet[0].door_point(), 3, f.world.player)
	check(event.data.opened[0], "a later explosion cannot close an already opened vault")
	check(event.perform(0) and event.data.pending == 40000 and f.session.state.economy.balance == balance, "first truck carries R$40000 pending escape instead of instant wallet credit")
	check(not event.perform(0) and event.data.pending == 40000, "the same truck cannot be collected twice")
	check(not event.save_block_reason().is_empty(), "unsecured money blocks checkpoints")
	f.world.player.position += Vector3(200, 0, 0)
	f.game.stars = 1
	event._tick_escape(10)
	check(event.data.pending == 40000 and f.session.state.economy.balance == balance, "distance alone cannot secure cash while police still want Dante")
	f.game.stars = 0
	event._tick_escape(8)
	check(event.data.pending == 0 and f.session.state.economy.balance == balance + 40000, "clean escape credits exactly the first truck's R$40000")
	event._secure_cash()
	check(f.session.state.economy.balance == balance + 40000, "repeated settlement cannot duplicate the first receipt")
	f.world.player.position = event.fleet[1].door_point() - Vector3.UP * .4
	event._explosion(event.fleet[1].door_point(), 3, null)
	check(not event.data.opened[1], "unattributed explosion cannot produce a player vault breach")
	event._explosion(event.fleet[1].door_point(), 3, f.world.player)
	check(event.data.opened[1] and event.perform(1), "returning after escape can breach and take the second truck")
	f.world.player.position += Vector3(200, 0, 0)
	event._tick_escape(8)
	check(f.session.state.economy.balance == balance + 80000 and event.data.secured == [true, true], "separate escapes pay R$40000 per truck with two distinct receipts")
	event._secure_cash()
	check(f.session.state.economy.balance == balance + 80000 and event.save_block_reason().is_empty(), "finished payouts remain idempotent and release the save block")
	event._persist()
	check(SCHEDULE.valid_saved(f.session.state.world_state[SCHEDULE.KEY]), "physical heist state persists in the production validated schema")
	f.world.free()
	for released_by in ["distance", "death"]:
		f = fixture()
		event = f.event
		event.data.phase = "loading"
		event._update_crew()
		event.perform(0)
		var before_escape: int = f.session.state.economy.balance
		f.world.player.position += Vector3(200, 0, 0)
		var pursuer := Guard.new()
		event.add_child(pursuer)
		pursuer.global_position = f.world.player.global_position + Vector3(20, 0, 0)
		event.guards[0] = pursuer
		event._tick_escape(9)
		check(event.data.pending == 40000 and event.escape_seconds == 0 and f.session.state.economy.balance == before_escape, "living nearby guard blocks cash even with fleet far away and no stars (" + released_by + ")")
		if released_by == "distance":
			pursuer.global_position = f.world.player.global_position + Vector3(36, 0, 0)
		else:
			pursuer.dead = true
			pursuer.health = 0
		event._tick_escape(7.9)
		check(event.data.pending == 40000 and f.session.state.economy.balance == before_escape, "guard clearance starts a fresh full eight-second escape window (" + released_by + ")")
		event._tick_escape(.2)
		check(event.data.pending == 0 and f.session.state.economy.balance == before_escape + 40000, "guard outside combat perimeter or dead releases the reward after escape (" + released_by + ")")
		f.world.free()
	for phase in ["loading", "unloading"]:
		f = fixture()
		event = f.event
		event.data.phase = phase
		event._update_crew()
		check(event.fleet[0].opened and not event.data.opened[0] and event.nearest_action().label.contains("40.000"), phase + " exposes the service vault and offers opportunistic robbery")
		f.session.state.economy.consume_item("lockpick", 3)
		check(event.perform(0) and event.data.pending == 40000 and event.data.opened[0] and not event.minigame.active, phase + " can be robbed directly without a lockpick while guards handle cash")
		check(SCHEDULE.valid_saved(f.session.state.world_state[SCHEDULE.KEY]), phase + " robbery records a valid breached and taken vault")
		f.world.free()
	f = fixture()
	event = f.event
	event.data.phase = "loading"
	event._update_crew()
	event.data.phase = "boarding"
	event._update_crew()
	check(not event.fleet[0].opened and not event._vault_accessible(0), "undamaged service doors close when the crew boards")
	event.data.phase = "unloading"
	event.data.cargo_cycles = [2, 2]
	event.data.delivered = [true, true]
	event._update_crew()
	event._explosion(event.fleet[0].door_point(), 3, f.world.player)
	check(event.fleet[0].empty and event.nearest_action().is_empty() and not event.perform(0), "cash delivered into the bank cannot respawn by blasting an empty vault")
	f.world.free()

	f = fixture(6)
	event = f.event
	check(event.perform(0), "reinforced vault still accepts a lockpick attempt")
	solve(event.minigame)
	check(not event.data.opened[0] and event.data.lock_progress[0] == 1, "maximum security requires multiple physical lock stages")
	for index in 2:
		event.perform(0)
		solve(event.minigame)
	check(event.data.opened[0], "completing all reinforced stages opens the vault")
	event._explosion(event.fleet[0].door_point(), 3, f.world.player)
	check(event.data.opened[0], "partial blast damage cannot reset a reinforced vault opened by lockpick")
	event.perform(0)
	var before_failure: int = f.session.state.economy.balance
	f.game.health = 0
	f.game.player_died.emit()
	check(event.data.pending == 0 and event.data.phase == "finished" and f.session.state.economy.balance == before_failure, "death forfeits all unsecured money")
	check(event.fleet.is_empty() and event.guards.is_empty(), "failed heist releases its finite fleet and crew")
	check(SCHEDULE.valid_saved(f.session.state.world_state[SCHEDULE.KEY]), "failure persists a valid closed event without future reward duplication")
	f.world.free()

	f = fixture()
	event = f.event
	event.perform(0)
	f.game.player_arrested.emit()
	check(not event.minigame.active and not f.session.modal and event.pending_truck == -1, "arrest cancels the live lockpick and releases the modal")
	check(event.data.phase == "finished" and event.data.pending == 0, "arrest closes the heist without retaining loot")
	f.world.free()
	print("ARMORED_HEIST_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
