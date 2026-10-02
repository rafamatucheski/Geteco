extends SceneTree
const Leisure := preload("res://gameplay/urban_v1/TruckersVillageLeisure.gd")
const Art := preload("res://gameplay/urban_v1/TruckersVillageLeisureArt.gd")
const Game := preload("res://gameplay/urban_v1/TruckersVillageHorseshoes.gd")
const Economy := preload("res://systems/economy/Economy.gd")
const PLAY := Leisure.PREFIX + "play"
const CACHE := Leisure.PREFIX + "cache"
var checks := 0
var failures: Array[String] = []

class Player extends Node3D:
	var input_locked := false

class Gameplay extends RefCounted:
	var health := 100.0
	var stars := 0

class Quest extends Node:
	var commerce := {"data": {"hostility": 0.0}}

class Operations extends RefCounted:
	var village_quest: Node

class Visuals extends Node3D:
	var cache_open := false
	var throws: Array[Dictionary] = []
	func animate_throw(value: float, hit: bool) -> void:
		throws.append({"strength": value, "hit": hit})
	func set_cache_open(value: bool) -> void:
		cache_open = value

class Session extends RefCounted:
	var world: Dictionary
	var state: Dictionary
	var urban_operations: Operations
	var panel: Control
	var modal := false
	var menu_closed := Callable()
	var ready_for_play := true
	var transition := false
	var save_block := ""
	var saves := 0
	var messages: Array[String] = []
	# Mirrors the relevant FullSession modal contract; no user save is touched.
	func _menu(_title: String) -> void:
		modal = true
		world.player.input_locked = true
		panel.show()
	func close_menu() -> void:
		if menu_closed.is_valid():
			menu_closed.call()
		menu_closed = Callable()
		modal = false
		panel.hide()
		world.player.input_locked = world.gameplay.health <= 0 or is_transition_blocked()
	func is_transition_blocked() -> bool:
		return transition
	func save_block_reason() -> String:
		return save_block
	func save_game() -> void:
		saves += 1
	func show_message(message: String) -> void:
		messages.append(message)


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _fixture() -> Dictionary:
	var scope := Node3D.new()
	root.add_child(scope)
	var player := Player.new()
	scope.add_child(player)
	player.position = Art.PLAY_POINT
	var hud := Control.new()
	scope.add_child(hud)
	hud.size = Vector2(1280, 720)
	var panel := Control.new()
	hud.add_child(panel)
	panel.hide()
	var quest := Quest.new()
	scope.add_child(quest)
	var visuals := Visuals.new()
	scope.add_child(visuals)
	var session := Session.new()
	session.panel = panel
	session.urban_operations = Operations.new()
	session.urban_operations.village_quest = quest
	session.world = {"player": player, "hud": hud, "gameplay": Gameplay.new(), "driving": {"occupied": false}}
	session.state = {"region_id": "harbor", "place_id": "", "economy": Economy.new()}
	var leisure := Leisure.new()
	scope.add_child(leisure)
	leisure.configure(session, visuals)
	return {"scope": scope, "session": session, "service": leisure, "art": visuals, "quest": quest}


func _begin(fixture: Dictionary) -> bool:
	fixture.session.world.player.position = Art.PLAY_POINT
	return fixture.service.perform(PLAY)


func _round(fixture: Dictionary, target_hits: int, leave_last_in_flight := false) -> void:
	check(_begin(fixture), "A reachable player starts the round")
	var ui = fixture.service.ui
	ui.step(0.01)
	for index in Game.THROWS:
		ui.strength = 0.7 if index < target_hits else 0.1
		check(ui.try_throw(), "Throw %d is accepted after the previous flight" % (index + 1))
		if leave_last_in_flight and index == Game.THROWS - 1:
			return
		ui.step(Game.THROW_SECONDS + 0.01)


func _run() -> void:
	for action in ["interact", "ui_accept", "fire"]:
		Input.action_release(action)
	_test_availability()
	_test_rounds_and_cache()
	await _test_cancel_and_context()
	_test_snapshot_validation()
	_test_receipts_and_full_wallet()
	print("TRUCKERS_VILLAGE_LEISURE: ", checks, " checks; failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)


func _test_availability() -> void:
	var fixture := _fixture()
	var session: Session = fixture.session
	var service = fixture.service
	check(service.nearest_action().get("target") == PLAY and not service.is_processing(), "The idle court is available on foot without per-frame polling")
	session.world.player.position = Art.PLAY_POINT + Vector3(Leisure.REACH + 0.01, 0, 0)
	check(service.nearest_action().is_empty() and not service.perform(PLAY), "The court cannot be started outside physical reach")
	session.world.player.position = Art.PLAY_POINT
	check(not service.perform(CACHE) and not service.perform("unrelated"), "A forged or unrelated target is rejected")
	session.modal = true
	check(service.nearest_action().is_empty(), "An existing modal blocks the court")
	session.modal = false
	session.world.player.input_locked = true
	check(not service.perform(PLAY), "An existing player input lock blocks the court")
	session.world.player.input_locked = false
	session.ready_for_play = false
	check(not service.perform(PLAY), "A session still loading cannot start leisure")
	session.ready_for_play = true
	session.state.region_id = "elsewhere"
	check(service.nearest_action().is_empty(), "Another region cannot use a stale world prompt")
	session.state.region_id = "harbor"
	session.state.place_id = "truckers_village_house_1"
	check(service.nearest_action().is_empty(), "An interior cannot use an exterior court prompt")
	session.state.place_id = ""
	session.world.gameplay.health = 0.0
	check(not service.perform(PLAY), "A dead player cannot play")
	session.world.gameplay.health = 100.0
	session.world.gameplay.stars = 1
	check(not service.perform(PLAY), "An active wanted level blocks leisure")
	session.world.gameplay.stars = 0
	session.world.driving.occupied = true
	check(not service.perform(PLAY), "The player must leave the vehicle to play")
	session.world.driving.occupied = false
	session.transition = true
	check(not service.perform(PLAY), "A transition cannot open the minigame")
	session.transition = false
	fixture.quest.commerce.data.hostility = 1.0
	check(not service.perform(PLAY), "Local hostility blocks the minigame")
	fixture.quest.commerce.data.hostility = 0.0
	session.world.player.position = Art.CACHE_POINT
	check(service.nearest_action().is_empty() and not service.perform(CACHE), "The cache stays locked before a perfect score")
	fixture.scope.free()


func _test_rounds_and_cache() -> void:
	var fixture := _fixture()
	var session: Session = fixture.session
	var service = fixture.service
	_round(fixture, 1)
	check(service.best_score == 1 and session.state.economy.balance == 0 and session.saves == 1, "One hit records progress without awarding the two-hit prize")
	check(not session.modal and not session.world.player.input_locked and not service.playing, "A finished round releases its modal and movement lock")
	check(not service.is_processing() and not service.ui.is_processing(), "Completed leisure stops idle polling and meter updates")
	_round(fixture, 2)
	check(service.best_score == 2 and session.state.economy.balance == 200, "Two hits grant the R$ 200 prize")
	check(session.state.economy.snapshot().transactions.has("reward:" + Leisure.PRIZE_ID), "The prize has a durable economy receipt")
	_round(fixture, 2)
	check(session.state.economy.balance == 200 and service.best_score == 2, "Repeating a winning round cannot duplicate the cash prize")
	_round(fixture, 0)
	check(service.best_score == 2, "A worse round cannot lower the personal record")
	_round(fixture, 3)
	check(service.best_score == 3 and session.state.economy.balance == 200 and fixture.art.throws.size() == 15, "A perfect round records three hits and every throw reaches the visual adapter")
	check(fixture.art.throws[-1].hit and is_equal_approx(fixture.art.throws[-1].strength, 0.7), "The visual throw uses the exact UI strength and hit result")
	check(not service.perform(CACHE), "A perfect score still requires walking to the cache")
	session.world.player.position = Art.CACHE_POINT
	check(service.nearest_action().get("target") == CACHE and service.perform(CACHE), "A perfect record unlocks the nearby hidden box")
	check(session.state.economy.balance == 850 and service.cache_opened and fixture.art.cache_open, "The cache grants R$ 650 and updates the real service state and visual lid")
	check(not service.perform(CACHE) and service.nearest_action().is_empty() and session.state.economy.balance == 850, "The opened cache has no repeat collection action")
	var saved: Dictionary = service.snapshot()
	check(Leisure.validate_snapshot(saved) and saved.best_score == 3 and saved.cache_opened, "Progress exports a valid durable snapshot")
	check(service.restore_snapshot({"version": 1, "best_score": 0, "cache_opened": false}), "An old valid marker can be restored")
	check(service.best_score == 3 and service.cache_opened and session.state.economy.balance == 850, "Economy receipts reconcile old markers without granting money again")
	fixture.scope.free()


func _test_cancel_and_context() -> void:
	var fixture := _fixture()
	var session: Session = fixture.session
	var service = fixture.service
	check(_begin(fixture) and session.modal and session.world.player.input_locked and not session.panel.visible and service.ui.visible, "Starting leisure owns a modal and movement lock while showing only its compact UI")
	check(not service.perform(PLAY) and service.nearest_action().is_empty(), "An active round cannot be reentered")
	session.close_menu()
	check(not service.playing and not service.ui.active and not session.modal and not session.world.player.input_locked, "External menu closure cancels without recursive close calls or leaked locks")
	check(session.saves == 0 and session.state.economy.balance == 0, "External cancellation neither saves a result nor grants cash")
	check(_begin(fixture), "The court reopens before external dismissal with the fire action held")
	Input.action_press("fire")
	session.close_menu()
	await process_frame
	check(not service.playing and session.world.player.input_locked and service.is_processing(), "External dismissal preserves the input lock while the fire action is held")
	Input.action_release("fire")
	service._process(0.01)
	check(not session.world.player.input_locked and not service.is_processing(), "The external-dismissal guard releases cleanly after fire is released")
	check(_begin(fixture), "The court reopens after external cancellation")
	Input.action_press("interact")
	service.ui.cancel_game()
	check(not session.modal and session.world.player.input_locked and service.is_processing(), "A held action keeps the movement lock until release after UI cancellation")
	Input.action_release("interact")
	service._process(0.01)
	check(not session.world.player.input_locked and not service.is_processing(), "Releasing the action clears the temporary lock and stops polling")
	for reason in ["death", "transition", "distance", "region", "place", "wanted", "hostility"]:
		check(_begin(fixture), "A fresh round starts before %s invalidates it" % reason)
		match reason:
			"death": session.world.gameplay.health = 0.0
			"transition": session.transition = true
			"distance": session.world.player.position += Vector3(Leisure.REACH + 0.1, 0, 0)
			"region": session.state.region_id = "elsewhere"
			"place": session.state.place_id = "test_interior"
			"wanted": session.world.gameplay.stars = 1
			"hostility": fixture.quest.commerce.data.hostility = 1.0
		service._process(0.01)
		check(not service.playing and not service.ui.active and not session.modal and session.state.economy.balance == 0, "%s cancels immediately without paying a result" % reason)
		if reason in ["death", "transition"]:
			check(session.world.player.input_locked, "Leisure cancellation preserves the %s movement lock" % reason)
		session.world.gameplay.health = 100.0
		session.world.gameplay.stars = 0
		session.transition = false
		session.state.region_id = "harbor"
		session.state.place_id = ""
		fixture.quest.commerce.data.hostility = 0.0
		session.world.player.input_locked = false
	_round(fixture, 3, true)
	session.world.gameplay.health = 0.0
	service.ui.step(Game.THROW_SECONDS + 0.01)
	check(session.state.economy.balance == 0 and service.best_score == 0 and session.world.player.input_locked, "Death during the last flight cannot pay before the service's next context poll")
	session.world.gameplay.health = 100.0
	session.world.player.input_locked = false
	_round(fixture, 3, true)
	session.menu_closed = func(): pass
	service._process(0.01)
	check(not service.playing and not service.ui.active and session.modal and session.world.player.input_locked, "Another modal's ownership cancels leisure without closing or unlocking the replacement")
	check(session.state.economy.balance == 0 and session.saves == 0, "Interrupted rounds never award or persist a completed score")
	session.close_menu()
	_round(fixture, 3, true)
	session.menu_closed = func(): pass
	service.ui.step(Game.THROW_SECONDS + 0.01)
	check(not service.playing and session.modal and session.world.player.input_locked and session.state.economy.balance == 0 and service.best_score == 0, "Losing modal ownership during the last flight cannot award before the service polls again")
	session.close_menu()
	fixture.scope.free()


func _test_snapshot_validation() -> void:
	for score in [0, 1, 2, 3, 2.0]:
		check(Leisure.validate_snapshot({"version": 1, "best_score": score, "cache_opened": false}), "Valid integral score %s survives serialization" % str(score))
	for score in [-1, 4, 1.5, NAN, INF, "3", true, null]:
		check(not Leisure.validate_snapshot({"version": 1, "best_score": score, "cache_opened": false}), "Malformed score %s is rejected" % str(score))
	check(not Leisure.validate_snapshot({"version": 1, "best_score": 2, "cache_opened": true}), "An opened cache cannot exist before the perfect record")
	check(not Leisure.validate_snapshot({"version": 1, "best_score": 3, "cache_opened": 1}), "The cache flag must be a real boolean")
	check(not Leisure.validate_snapshot({"version": 2, "best_score": 0, "cache_opened": false}) and not Leisure.validate_snapshot({}), "Unknown and incomplete save formats are rejected")
	var fixture := _fixture()
	check(fixture.service.restore_snapshot({"version": 1, "best_score": 1, "cache_opened": false}), "A valid snapshot restores progress")
	var before: Dictionary = fixture.service.snapshot()
	check(not fixture.service.restore_snapshot({"version": 1, "best_score": 9, "cache_opened": true}) and fixture.service.snapshot() == before, "A rejected snapshot leaves the existing progress intact")
	fixture.session.save_block = "mission"
	_round(fixture, 2)
	check(fixture.session.saves == 0 and fixture.session.state.economy.balance == 200 and fixture.service.best_score == 2, "Blocked autosaving retains the earned state without forcing a user save")
	fixture.scope.free()


func _test_receipts_and_full_wallet() -> void:
	var fixture := _fixture()
	var session: Session = fixture.session
	var service = fixture.service
	check(session.state.economy.grant_reward(Leisure.PRIZE_ID, 200), "Fixture obtains the real prize receipt")
	check(service.restore_snapshot({"version": 1, "best_score": 0, "cache_opened": false}) and service.best_score == 2 and not service.cache_opened, "A prior prize receipt restores at least two hits without opening the cache")
	check(session.state.economy.grant_reward(Leisure.CACHE_ID, 650), "Fixture obtains the real cache receipt")
	check(service.restore_snapshot({"version": 1, "best_score": 0, "cache_opened": false}) and service.best_score == 3 and service.cache_opened and fixture.art.cache_open, "A prior cache receipt restores the perfect score and open lid")
	fixture.scope.free()
	fixture = _fixture()
	session = fixture.session
	service = fixture.service
	check(session.state.economy.grant_reward("fixture_full_wallet", Economy.LIMIT), "Fixture fills the actual economy wallet")
	_round(fixture, 3)
	check(service.best_score == 3 and not session.state.economy.snapshot().transactions.has("reward:" + Leisure.PRIZE_ID), "A full wallet retains the record without inventing a prize receipt")
	session.world.player.position = Art.CACHE_POINT
	check(not service.perform(CACHE) and not service.cache_opened and not fixture.art.cache_open, "A full wallet cannot consume or visually open the hidden cache")
	check(session.state.economy.spend(1000, "fixture_make_room"), "The wallet can make room for a later collection")
	check(service.perform(CACHE) and service.cache_opened and session.state.economy.balance == Economy.LIMIT - 350, "The preserved cache can be collected after making wallet space")
	_round(fixture, 2)
	check(session.state.economy.balance == Economy.LIMIT - 150 and session.state.economy.snapshot().transactions.has("reward:" + Leisure.PRIZE_ID), "An unpaid prize remains earnable on a later qualifying round")
	fixture.scope.free()
