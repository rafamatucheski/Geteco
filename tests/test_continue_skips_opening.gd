extends SceneTree

class SavedWorld extends Node2D:
	var loaded_from_save := false

class Garage extends Node2D:
	func set_campaign_contact_enabled(_enabled: bool) -> void: pass
	func set_mission_board_unlocked(_enabled: bool) -> void: pass

class Story extends Node:
	var active := true
	var resumed := false
	func resume() -> void: resumed = true

class Mission extends "res://world/harbor/campaign/HarborArrivalMission.gd":
	var opening_started := false
	func _refresh_board() -> void: pass
	func _begin_arrival(_prepare_only := false) -> void: opening_started = true
	func _set_phase(value: String, _description: String, _destination: Vector2) -> void:
		phase = value

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1

func run() -> void:
	var state := root.get_node("CampaignState")
	var loading := root.get_node("GameLoading")
	for with_loading in [false, true]:
		for scenario in ["new", "saved_missing_flag", "saved_seen", "mission_1"]:
			state.reset_campaign()
			var saved: Dictionary = state.to_save_data()
			if scenario == "saved_seen": saved.campaign_flags["harbor_arrival_seen"] = true
			if scenario == "mission_1": saved.campaign_flags["harbor_delivery_started"] = true
			# Exercise the same JSON conversion and campaign restoration as a save.
			check(state.restore_from_save(JSON.parse_string(JSON.stringify(saved))), "Restore " + scenario)
			var world := SavedWorld.new()
			world.loaded_from_save = scenario != "new"
			root.add_child(world)
			var pickup := Node2D.new()
			pickup.name = "FirstDeliveryPickup"
			world.add_child(pickup)
			var garage := Garage.new()
			world.add_child(garage)
			var story := Story.new()
			world.add_child(story)
			var mission := Mission.new()
			world.add_child(mission)
			mission.set_process(false)
			mission.world = world
			mission.campaign = state
			mission.garage = garage
			mission.entrance = garage
			mission.story_arrival = story
			loading.active = with_loading
			mission.start_or_resume()
			if with_loading:
				loading.presentation_preparing.emit()
				# Fresh games now await the movie handoff; no movie is instantiated
				# by this probe. Resumes must instead await normal loading finish.
				if scenario != "new": loading.finished.emit()
			check(mission.opening_started == (scenario == "new"), "Opening only for new game: %s loading=%s" % [scenario, with_loading])
			if scenario == "mission_1":
				check(mission.phase == "delivery_pickup", "Mission 1 keeps its saved objective")
			elif scenario != "new":
				check(story.resumed, "Saved arrival resumes without CGI")
				check(state.to_save_data().campaign_flags.get("harbor_arrival_seen", false), "Arrival flag retained for next save")
			world.free()
			loading.active = false
	print("CONTINUE_OPENING failures=%d" % failures)
	quit(0 if failures == 0 else 1)
