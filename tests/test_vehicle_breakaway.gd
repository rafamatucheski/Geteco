extends SceneTree
## Cobertura de contrato dos painéis destacáveis preparados nos carros do jogador e do ambiente.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET := preload("res://runtime/FleetState.gd")
const DEBRIS := preload("res://gameplay/vehicle_effects/VehiclePanelDebris.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("BREAKAWAY_TEST timeout"); quit(3))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func make_car(id: String, point: Vector3, ambient: bool) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.vehicle_id = "breakaway-test-"+id+str(point.x)
	car.traffic = ambient
	car.paint_color = Color("2268c9") if ambient else Color("d44233")
	root.add_child(car)
	car.place(point, 0)
	car.set_physics_process(false)
	return car

func hit_front(car: CharacterBody3D) -> void:
	car.receive_impact(10, Vector3(0,.6,-car.half_length), null, 26.0, Vector3.BACK)

func run() -> void:
	for id in ["sport_coupe", "monaliza", "metro_hatch", "police_cruiser"]:
		var player := make_car(id, Vector3(0,2,0), false)
		var traffic := make_car(id, Vector3(12,2,0), true)
		var independent := make_car(id, Vector3(24,2,0), true)
		var controller: Node = player.get("breakaway_parts")
		check(controller != null and traffic.get("breakaway_parts") != null, id+" supports player and traffic")
		if controller == null:
			player.free(); traffic.free(); independent.free()
			continue
		check(controller.panels.size() == 3, id+" has hood and two bumpers")
		check(controller.detached_count() == 0, id+" starts intact")
		var overlay:=StandardMaterial3D.new()
		overlay.albedo_color=Color("4c5b6780")
		controller.panels.bumper_front.node.material_overlay=overlay
		player.receive_impact(1,Vector3(0,.6,-player.half_length),null,2.0,Vector3.BACK)
		check(controller.detached_count() == 0, id+" light contact keeps all panels attached")
		var original_other: Dictionary = independent.breakaway_parts.snapshot().duplicate(true)
		hit_front(player)
		hit_front(traffic)
		check(not player.body_dents.dents.is_empty() and not traffic.body_dents.dents.is_empty(), id+" dents both roles")
		check(controller.detached_count() >= 1 and traffic.breakaway_parts.detached_count() >= 1, id+" detaches front panels in both roles")
		var detached_front: RigidBody3D
		for fragment: RigidBody3D in get_nodes_in_group("vehicle_panel_debris"):
			if fragment.source_vehicle_id==player.vehicle_id and fragment.panel_id=="bumper_front": detached_front=fragment
		check(is_instance_valid(detached_front),id+" detached front appearance can be inspected")
		if is_instance_valid(detached_front):
			var copy_overlay: Material=detached_front.panel_mesh.material_overlay
			check(copy_overlay!=null and copy_overlay!=overlay and copy_overlay.albedo_color==overlay.albedo_color,id+" detached overlay is preserved and independent")
		check(controller.snapshot().parts.get("bumper_rear",0.0) < 1.0, id+" frontal crash preserves rear bumper")
		hit_front(player)
		check(controller.snapshot().parts.get("hood",0.0) >= 1.0, id+" repeated strong front crash releases hood")
		var detached: int = controller.spawned_count
		for index in 3: hit_front(player)
		check(controller.spawned_count == detached, id+" detached parts spawn once")
		player.finish_doors()
		player.animate_driver_door(-1,true,.01)
		await create_timer(.03).timeout
		check(player.door_presentation.ready_for_boarding, id+" damaged vehicle prepares boarding")
		check(controller.snapshot().parts.get("hood",0.0) >= 1.0 and controller.detached_count() >= 2, id+" opening doors does not resurrect panels")
		check(independent.breakaway_parts.snapshot() == original_other and independent.body_dents.dents.is_empty(), id+" shared model remains independent")
		check(player.paint_color == Color("d44233") and traffic.paint_color == Color("2268c9"), id+" individual paint survives")
		var record: Dictionary = FLEET.capture(player,"harbor")
		check(FLEET.validate(record) and record.has("breakaway_parts"), id+" fleet persists part state")
		var malformed: Dictionary=record.duplicate(true)
		malformed.breakaway_parts.parts.hood=1.1
		check(not FLEET.validate(malformed),id+" rejects out-of-range saved panel damage")
		var state_before: Dictionary = controller.snapshot().duplicate(true)
		var path := "user://breakaway-test-%d-%s.json" % [OS.get_process_id(),id]
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(record)); file.close()
		var loaded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		independent.restore_body_dents(loaded.body_dents, loaded.breakaway_parts)
		check(independent.breakaway_parts.snapshot() == state_before, id+" disk roundtrip preserves absent pieces")
		check(independent.breakaway_parts.spawned_count == 0, id+" restore creates no falling fragments")
		player.repair()
		check(controller.detached_count() == 0 and player.body_dents.dents.is_empty(), id+" repair restores body and attached pieces")
		for panel_id in controller.panels:
			check(controller.panels[panel_id].node.visible, id+" repaired panel visible "+panel_id)
		var repaired: Dictionary = controller.snapshot().duplicate(true)
		player.set_meta("invulnerable",true)
		hit_front(player)
		check(controller.snapshot() == repaired, id+" mission protection prevents detachment")
		player.remove_meta("invulnerable")
		player.receive_impact(10,Vector3(0,.6,player.half_length),null,26.0,Vector3.FORWARD)
		check(controller.snapshot().parts.get("bumper_rear",0.0) >= 1.0, id+" rear impact releases rear bumper")
		check(controller.snapshot().parts.get("hood",0.0) < 1.0, id+" rear impact preserves hood")
		player.repair()
		player.receive_impact(10,Vector3(player.half_width,.6,-player.half_length),null,26.0,Vector3.LEFT)
		check(controller.snapshot().get("parts",{}).get("hood",0.0)==0.0,id+" side scrape at front corner preserves hood")
		player.free(); traffic.free(); independent.free()
		await process_frame
	check(not get_nodes_in_group("vehicle_panel_debris").is_empty(),"detached debris survives removal of its source vehicle")
	# Seven actual fully damaged cars exceed the physics budget even without earlier cases.
	for index in 7:
		var burst_car:=make_car("metro_hatch",Vector3(index*8,2,18),true)
		burst_car.receive_impact(10,Vector3(0,.6,-burst_car.half_length),null,35.0,Vector3.BACK)
		burst_car.receive_impact(10,Vector3(0,.6,burst_car.half_length),null,35.0,Vector3.FORWARD)
		burst_car.free()
		await process_frame
		var active:=0
		for debris: RigidBody3D in get_nodes_in_group("vehicle_panel_debris"):
			if not debris.freeze and not debris.is_queued_for_deletion(): active+=1
		check(active<=DEBRIS.MAX_ACTIVE,"physics debris budget after burst "+str(index))
	var live: RigidBody3D
	for debris: RigidBody3D in get_nodes_in_group("vehicle_panel_debris"):
		if not debris.freeze and not debris.is_queued_for_deletion(): live=debris
	check(is_instance_valid(live),"stress leaves a live fragment for pause validation")
	if is_instance_valid(live):
		var timer: Timer=live.find_children("*","Timer",false,false)[0]
		var time_before:=timer.time_left
		var pose_before:=live.global_transform
		paused=true
		await create_timer(.2,true).timeout
		check(absf(timer.time_left-time_before)<.001,"pause preserves debris lifetime")
		check(live.global_transform.is_equal_approx(pose_before),"pause stops fragment physics")
		paused=false
	await create_timer(23.0).timeout
	check(get_nodes_in_group("vehicle_panel_debris").is_empty(),"detached debris expires without retaining its source")
	print("BREAKAWAY_TEST checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
