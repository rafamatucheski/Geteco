extends SceneTree
const MISSION := preload("res://runtime/MissionWorld.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const BRIDGE := preload("res://audio/v1_ambience/ActivityAudioBridge.gd")
var failures: Array[String] = []
var checks := 0
var events: Array[String] = []

class TestController extends RefCounted:
	var clear := true
	var world: Node3D
	var vehicles: Array = []
	func vehicle_position_clear(_car, _point, _yaw) -> bool: return clear
	func spawn_vehicle(id: String, point: Vector3, yaw: float):
		var car = VEHICLE.new()
		car.archetype = id
		world.add_child(car)
		car.place(point,yaw)
		car.set_physics_process(false)
		vehicles.append(car)
		return car

class TestSession extends RefCounted:
	var mission_world
	var world: Node3D
	var state := {"region_id":"harbor","campaign":preload("res://systems/campaign/CampaignRuntime.gd").new()}
	var controller := TestController.new()
	var ready_for_play := false
	func save_game() -> void: pass
	func show_message(_text: String) -> void: pass

class TestWorld extends Node3D:
	var session := TestSession.new()

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): push_error("TOW_AUDIO_EVENTS timeout"); quit(3))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func sounding(bridge, kind: String) -> bool:
	var stream = preload("res://audio/v1_ambience/V1AudioCatalog.gd").activity(kind)
	return bridge.voices.any(func(voice): return voice.playing and voice.stream == stream)

func silence(bridge) -> void:
	for voice in bridge.voices: voice.stop()

func run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	world.session.world = world
	world.session.controller.world = world
	var mission := MISSION.new()
	world.session.mission_world = mission
	mission.session = world.session
	world.add_child(mission)
	mission.set_process(false)
	if not mission.has_signal("tow_event"):
		check(false,"MissionWorld exposes successful tow events")
		world.free()
		quit(1)
		return
	mission.connect("tow_event",func(kind: String): events.append(kind))
	var bridge = BRIDGE.new()
	bridge.world = world
	world.add_child(bridge)
	bridge.set_process(false)
	check(mission.is_connected("tow_event",bridge.on_tow_event),"production bridge binds public tow signal on ready")
	bridge.bind_tow_events(mission)
	check(mission.get_signal_connection_list("tow_event").size()==2,"rebinding does not duplicate signal observers")
	var incompatible := Node.new()
	bridge.bind_tow_events(incompatible)
	check(bridge.tow_source==null and not mission.is_connected("tow_event",bridge.on_tow_event),"incompatible source is rejected and old source disconnected")
	bridge.bind_tow_events(mission)
	incompatible.free()
	mission.truck = VEHICLE.new()
	mission.truck.archetype = "towmaster"
	world.add_child(mission.truck)
	mission.truck.set_physics_process(false)
	mission.cargo = VEHICLE.new()
	mission.cargo.archetype = "ranch_single"
	world.add_child(mission.cargo)
	mission.cargo.set_physics_process(false)
	mission.cargo.position = Vector3(0,0,mission.truck.half_length+2)
	mission.tow_job = preload("res://data/catalogs/TowJobs.gd").JOBS[0].duplicate(true)
	mission.tow_job.merge({"index":0,"token":"tow_1"})
	mission.truck.speed = 1.0
	check(not mission._tow_toggle() and events.is_empty(),"moving truck rejects loading without a cue")
	mission.truck.speed = 0.0
	check(mission._tow_toggle() and events==["loaded"] and mission.loaded,"successful load publishes exactly one event")
	check(sounding(bridge,"mission_start"),"load starts the recorded activity-start cue")
	silence(bridge)
	var saved: Dictionary = mission.snapshot()
	var restored := MISSION.new()
	restored.session = world.session
	world.add_child(restored)
	restored.set_process(false)
	bridge.bind_tow_events(restored)
	check(restored.restore_snapshot(saved) and restored.loaded,"loaded tow snapshot restores native bodies")
	check(not bridge.voices.any(func(voice): return voice.playing),"restoring saved cargo does not replay the load cue")
	var restored_cargo: Node = restored.cargo
	check(restored.cancel_tow_job() and not bridge.voices.any(func(voice): return voice.playing),"cancelling restored cargo does not play a success cue")
	bridge.bind_tow_events(mission)
	check(not restored.is_connected("tow_event",bridge.on_tow_event),"rebinding disconnects previous mission source")
	restored.truck.free()
	restored_cargo.free()
	restored.free()
	world.session.controller.clear = false
	check(not mission._tow_toggle() and events==["loaded"] and mission.loaded,"blocked unload preserves load and emits nothing")
	check(not bridge.voices.any(func(voice): return voice.playing),"rejected unload leaves cue pool silent")
	world.session.controller.clear = true
	mission.targets.neco_bay = mission.truck.to_global(Vector3(0,.1,mission.truck.half_length+mission.cargo.half_length+1))
	check(mission._tow_toggle() and events==["loaded","unloaded"] and not mission.loaded,"successful unload publishes exactly one event")
	check(sounding(bridge,"checkpoint"),"unload starts the recorded milestone cue")
	silence(bridge)
	check(mission.finish_tow_job() and events==["loaded","unloaded","delivered"],"delivery publishes once after ownership release")
	check(sounding(bridge,"complete"),"delivery starts the recorded completion cue")
	silence(bridge)
	check(not mission.finish_tow_job() and events.size()==3,"duplicate delivery has no new event")
	bridge.on_tow_event("unknown")
	check(not bridge.voices.any(func(voice): return voice.playing),"unknown public event does not play a cue")
	check(bridge.voices.size()==2,"tow cues reuse bounded existing two-voice pool")
	bridge.free()
	check(mission.get_signal_connection_list("tow_event").size()==1,"bridge teardown releases public event connection")
	world.free()
	await process_frame
	print("TOW_AUDIO_EVENTS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
