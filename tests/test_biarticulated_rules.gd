extends SceneTree
const SERVICE := preload("res://runtime/transit/UrbanBusService.gd")
const BUS := preload("res://runtime/transit/BiarticulatedBus.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func run() -> void:
	var player := CharacterBody3D.new()
	root.add_child(player)
	var weather := {"time_of_day":.35}
	var service := SERVICE.new()
	service.configure({"session":{"ready_for_play":false,"weather":weather},"world":{"player":player}})
	root.add_child(service)
	service.set_physics_process(false)
	var bus := BUS.new()
	root.add_child(bus)
	bus.set_active(true)
	for index in 3: bus.sections[index].global_position=Vector3(0,0,index*8)
	bus.service_state="exchange"; bus.set_doors(1); bus.service_stop=0
	service.fleet.append(bus)
	service.stops.append({"inside":bus.door_point(),"definition":{"position":Vector3.ZERO,"angle":0}})
	for door in 3:
		player.global_position=bus.door_point(door)
		check(service.doorway_occupied(bus),"Door %d detects player before closing" % door)
	player.global_position=Vector3(20,0,0)
	check(not service.doorway_occupied(bus),"Empty doors allow departure")
	player.global_position=bus.door_point()
	check(service.boardable_bus()==bus,"Open scheduled bus accepts player")
	bus.set_doors(0)
	check(service.boardable_bus()==null,"Closed doors prevent boarding")
	bus.set_doors(1)
	for index in SERVICE.CAPACITY: bus.passengers.append({"id":index})
	check(service.boardable_bus()==null,"Full capacity prevents boarding")
	bus.passengers.clear()
	weather.time_of_day=3.0/24
	check(not service.service_open() and service.boardable_bus()==null,"03h stops new boarding")
	weather.time_of_day=5.0/24
	check(service.service_open(),"05h resumes service")
	var actor := CharacterBody3D.new()
	root.add_child(actor)
	actor.collision_layer=2; actor.collision_mask=7
	service.hide_person({"actor":actor})
	check(not actor.visible and actor.collision_layer==0 and actor.process_mode==Node.PROCESS_MODE_DISABLED,"Virtual passengers leave no visible actor or phantom collision")
	print("BIARTICULATED_RULES ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
