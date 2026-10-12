extends SceneTree
const BUS := preload("res://runtime/transit/BiarticulatedBus.gd")
const SERVICE := preload("res://runtime/transit/UrbanBusService.gd")
const SHIFT := preload("res://runtime/transit/BusDriverShift.gd")
const STATE := preload("res://runtime/FleetState.gd")
class Player extends CharacterBody3D:
	var input_locked := false
class Driver extends Node:
	var occupied := true
	var car: CharacterBody3D
	func is_body_transition_active() -> bool: return false
	func _external_transition_blocked() -> bool: return false
	func _entry_option() -> Dictionary: return {}
class World extends Node3D:
	var player: Player
	var driving: Driver
	var hud: CanvasLayer
	var session: Dictionary
class Poses extends RefCounted:
	var bus: CharacterBody3D
	func at(offset: float) -> Array[Transform3D]: return bus.placement_poses(Vector3(0,.04,-offset),0)
	func front(offset: float) -> Transform3D: return at(offset)[0]
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(60).timeout.connect(func(): quit(2))
	var world := World.new(); root.add_child(world)
	world.player=Player.new(); world.player.position=Vector3(100,0,100); world.add_child(world.player)
	world.driving=Driver.new(); world.add_child(world.driving)
	world.hud=CanvasLayer.new(); world.add_child(world.hud)
	var state := preload("res://runtime/GameState.gd").new()
	world.session={"ready_for_play":true,"modal":false,"state":state}
	var bus := BUS.new(); bus.driver_shift=true; world.add_child(bus)
	bus.set_active(true); bus.set_physics_process(false); bus.place(Vector3(0,.04,0),0)
	bus.controlled=true; bus.external_input=true; bus.work_state={"next_stop":0,"stops":0,"earned":0,"laps":0}
	world.driving.car=bus
	var service := SERVICE.new(); world.add_child(service); service.set_physics_process(false)
	service.configure({"world":world,"state":{"region_id":"harbor","place_id":""},"urban_transit":{"instances":{}},"session":world.session})
	service.stops=[{"offset":0.0,"definition":{"id":"a","name":"A"}},{"offset":40.0,"definition":{"id":"b","name":"B"}}]
	var poses := Poses.new(); poses.bus=bus; service.path_poses=poses
	var job := SHIFT.new(); job.configure(service); service.add_child(job); job.active_bus=bus
	var cash: int=state.economy.balance
	check(job.docked(bus),"All three aligned modules admit the stop")
	check(job.toggle_doors() and bus.door_amount==1,"Driver opens the doors at the target stop")
	var start := bus.global_position
	bus.throttle_input=1; bus._physics_process(1.0)
	check(bus.global_position==start and bus.speed==0,"Open doors prevent acceleration")
	check(not job.toggle_doors() and state.economy.balance==cash,"Early door closing cannot earn a fare")
	job.tick(bus,2.1)
	var actor := preload("res://scripts/Actor.gd").new(); world.add_child(actor); actor.set_physics_process(false); actor.teleport(bus.door_point())
	service.people.append({"id":999,"actor":actor,"stop":0,"bus":null,"phase":"unavailable","slot":0})
	check(not job.toggle_doors(),"A physical actor in the doorway prevents closing")
	service.people.clear(); actor.queue_free()
	check(job.toggle_doors() and bus.door_amount==0,"Clear completed boarding allows departure")
	check(state.economy.balance==cash+12 and bus.work_state.next_stop==1,"One stop pays once and advances the objective")
	check(not job.toggle_doors() and state.economy.balance==cash+12,"Repeated opening at the old stop cannot farm payment")
	bus.place(Vector3(0,.04,-40),0)
	check(job.toggle_doors(),"The next distinct stop can be served")
	job.tick(bus,2.1); check(job.toggle_doors(),"The second stop closes after exchange")
	check(bus.work_state.laps==1 and bus.work_state.stops==2 and state.economy.balance==cash+84,"A complete circuit pays its bonus once")
	var record := STATE.capture(bus,"harbor")
	check(STATE.validate(record),"Work progress is accepted in the fleet snapshot")
	var filename := "user://bus-driver-%d.json" % OS.get_process_id()
	FileAccess.open(filename,FileAccess.WRITE).store_string(JSON.stringify(record))
	var loaded: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(filename))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	var restored := BUS.new(); restored.stolen=true; world.add_child(restored); restored.set_active(false)
	restored.restore_fleet_extras(loaded)
	check(restored.driver_shift and not restored.stolen and restored.work_state.stops==2,"JSON restoration preserves peaceful driver ownership and progress")
	loaded.bus_work.next_stop=-1
	check(not STATE.validate(loaded),"Invalid job progress is rejected")
	bus.work_state.next_stop=1; bus.sections[2].rotation.y=deg_to_rad(30)
	check(not job.docked(bus),"A misaligned rear section cannot board passengers")
	job.finish()
	check(not is_instance_valid(job.active_bus) and bus.driver_shift and not bus.stolen,"Ending a shift parks the borrowed bus without a crime")
	print("BUS_DRIVER_SHIFT ",checks," checks ",failures," failures")
	world.queue_free(); await process_frame
	quit(1 if failures else 0)
