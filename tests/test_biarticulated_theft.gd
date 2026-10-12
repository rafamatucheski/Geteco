extends SceneTree
const BUS := preload("res://runtime/transit/BiarticulatedBus.gd")
const SERVICE := preload("res://runtime/transit/UrbanBusService.gd")
const STATE := preload("res://runtime/FleetState.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func solid(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size=size; shape.shape=box
	body.add_child(shape); body.position=at; parent.add_child(body)
	return body
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(90).timeout.connect(func(): quit(2))
	var stage := Node3D.new(); root.add_child(stage)
	solid(stage,Vector3(0,-.1,0),Vector3(120,.2,120))
	var bus := BUS.new(); stage.add_child(bus); bus.place(Vector3(0,.04,0),0); bus.set_active(true)
	bus.set_physics_process(false); bus.service_stop=0; bus.service_state="exchange"
	var service := SERVICE.new(); service.configure({"session":{"ready_for_play":false},"urban_transit":{"instances":{}}})
	stage.add_child(service); service.set_physics_process(false); service.fleet.append(bus)
	service.stops.append({"definition":{"id":"test"}})
	await physics_frame
	check(bus.is_in_group("drivable"),"The articulated service participates in driver interaction")
	check(service.claim_bus(bus) and bus.stolen,"Theft transfers scheduled ownership")
	check(not bus.is_servicing_stop(),"A stolen bus no longer advertises scheduled boarding")
	var origin := bus.global_position
	var route_distance := bus.route_distance
	service.tick_bus(bus,1.0)
	check(bus.global_position==origin and bus.route_distance==route_distance,"Scheduling cannot move the stolen bus")
	bus.controlled=true; bus.external_input=true; bus.throttle_input=1; bus.steer_input=.6
	for frame in 180:
		bus._physics_process(1.0/60.0)
		await physics_frame
	check(bus.global_position.distance_to(origin)>3 and absf(bus.global_position.x-origin.x)>.2,"Manual acceleration and steering leave the authored route")
	for index in range(1,3):
		var front_hitch: Vector3 = bus.sections[index-1].global_position+bus.sections[index-1].global_basis.z*(bus.LENGTHS[index-1]*.5+bus.JOINT_GAP*.5)
		var rear_hitch: Vector3 = bus.sections[index].global_position-bus.sections[index].global_basis.z*(bus.LENGTHS[index]*.5+bus.JOINT_GAP*.5)
		check(front_hitch.distance_to(rear_hitch)<.01,"Hitch %d remains connected in turns" % index)
	bus.steer_input=0; bus.brake_input=true
	for frame in 100: bus._physics_process(1.0/60.0); await physics_frame
	check(absf(bus.speed)<.01,"Manual brakes stop all three sections")
	var before_reverse := bus.global_position
	bus.brake_input=false; bus.throttle_input=-1
	for frame in 90: bus._physics_process(1.0/60.0); await physics_frame
	check(bus.speed<0 and bus.global_position.distance_to(before_reverse)>1,"Reverse moves the complete articulated vehicle")
	bus.stop_boarding_motion(); bus.input_locked=true
	var record := STATE.capture(bus,"harbor")
	check(STATE.validate(record),"The save accepts the articulated archetype and its durability")
	var file := "user://biarticulated-theft-%d.json" % OS.get_process_id()
	FileAccess.open(file,FileAccess.WRITE).store_string(JSON.stringify(record))
	var loaded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	check(STATE.validate(loaded),"A real temporary JSON round trip preserves the snapshot")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	var restored := BUS.new(); restored.stolen=true; stage.add_child(restored)
	restored.restore_fleet_extras(loaded); restored.place(Vector3(loaded.position[0],loaded.position[1],loaded.position[2]),loaded.yaw); restored.set_active(false)
	for index in 3: check(restored.sections[index].global_position.distance_to(bus.sections[index].global_position)<.01,"Save restores section %d without straightening the parked bus" % index)
	loaded.articulation=[99.0,0.0]
	check(not STATE.validate(loaded),"Invalid articulation is rejected")
	var wall := solid(stage,bus.sections[2].global_position+Vector3(1.6,1.5,0),Vector3(.4,3,1))
	await physics_frame
	var trial: Array[Transform3D]=[]
	for body in bus.sections:
		var pose: Transform3D=body.global_transform; pose.origin.x+=.5; trial.append(pose)
	check(not bus.admits(trial),"A rear-section obstruction rejects the whole movement")
	wall.queue_free(); await physics_frame
	var person := {"id":777,"actor":null,"bus":bus,"phase":"aboard","stop":0,"slot":0,"age":0.0}
	service.people.append(person); bus.passengers.append(person)
	service.evacuate_one(bus)
	check(bus.passengers.is_empty() and person.bus==null and person.phase=="fleeing","Passenger ownership is released after theft")
	check(is_instance_valid(person.actor) and person.actor.visible and person.actor.collision_layer==2,"Evacuated passenger is a physical, visible actor")
	bus.controlled=false; bus.input_locked=false; bus.set_doors(0)
	bus.set_active(false); var parked := bus.global_transform; bus.set_active(true)
	check(bus.global_transform==parked and bus.stolen and not bus.traffic,"Suspension and return preserve the stolen pose and ownership")
	bus.place(Vector3(59.5,.04,-30),0)
	var unsupported := {"id":778,"actor":null,"bus":bus,"phase":"aboard","stop":0,"slot":1,"age":0.0}
	service.people.append(unsupported); bus.passengers.append(unsupported)
	await physics_frame
	service.evacuate_one(bus)
	check(unsupported.actor==null and unsupported.bus==bus,"Passengers are never materialized over unsupported ground")
	print("BIARTICULATED_THEFT ",checks," checks ",failures," failures")
	stage.queue_free(); await process_frame
	quit(1 if failures else 0)
