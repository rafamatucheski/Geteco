extends SceneTree
var failures: Array[String] = []
var world: Node2D

class Cemetery extends HarborCemetery:
	func _ready() -> void:
		add_to_group("cemetery")
		_build_ground()
		_build_wall()
		_build_plot_grid()

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(180).timeout.connect(func(): printerr("CORONER_PHYSICAL timeout"); quit(2))
	Engine.max_fps = 0
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var care := root.get_node("CoronerCare")
	var medical := root.get_node("NPCMedicalCare")
	var cemetery := Cemetery.new()
	cemetery.position = Vector2(900,900)
	world.add_child(cemetery)
	var road := Path2D.new()
	road.curve = Curve2D.new()
	for point in [Vector2(100,100),Vector2(900,100),cemetery.get_coroner_stop_position(),Vector2(100,448),Vector2(100,100)]:
		road.curve.add_point(point)
	road.add_to_group("unified_traffic_lane")
	world.add_child(road)
	var director := EmergencyDepotDirector.new()
	world.add_child(director)
	var depot := EmergencyDepotMarker.new()
	depot.service_key = "coroner"
	depot.depot_id = "test_iml"
	depot.position = Vector2(100,100)
	director.add_child(depot)
	director.register_depot(depot)
	var person := preload("res://AnimatedPedestrian3D.gd").new()
	person.name = "PhysicalVictim"
	person.position = Vector2(400,100)
	world.add_child(person)
	await physics_frame
	person._die()
	if OS.get_cmdline_user_args().has("fragments"):
		preload("res://guns/combat/ExplosionRemains.gd").spawn(person,Vector2(375,100))
	medical.witness_called(person)
	var key: String = care.identity(person)
	var second_key := ""
	if OS.get_cmdline_user_args().has("multiple"):
		var second := preload("res://AnimatedPedestrian3D.gd").new()
		second.name = "SecondVictim"
		second.position = Vector2(460,125)
		world.add_child(second)
		await physics_frame
		second._die()
		medical.witness_called(second)
		second_key = care.identity(second)
	var observed := {}
	care.case_changed.connect(func(changed_key: String, phase: String):
		if changed_key==key: observed[phase] = true)
	var unit: Node2D
	var travel := 0.0
	var last := Vector2.INF
	var lost_crew := false
	for frame in 9600:
		await physics_frame
		if care.records().has(key): observed[care.records()[key].phase] = true
		if OS.get_cmdline_user_args().has("crew_loss") and not lost_crew and care.records()[key].phase=="carrying":
			var carrier: Node = care.active[key].carrier.get_ref()
			carrier.take_damage(100)
			lost_crew = true
		if unit == null:
			for candidate in get_nodes_in_group("emergency_vehicle"):
				if candidate.type==3 and candidate.visible: unit=candidate
		if is_instance_valid(unit):
			if last.is_finite(): travel += last.distance_to(unit.global_position)
			last = unit.global_position
		if frame%600==0:
			if frame==1200 and OS.get_cmdline_user_args().has("crew_loss"):
				for member in get_nodes_in_group("mortician"):
					print("LOSS_CREW ",member.get_meta("medical_identity","")," pos=",member.position," state=",member.state," dead=",member.is_dead," target=",member.target.get_path() if is_instance_valid(member.target) else "none"," dest=",member.movement_navigation.destination," path=",member.movement_navigation.path," unit=",member.hearse.get_instance_id() if is_instance_valid(member.hearse) else 0)
			print("FLOW ", frame, " ",care.records().get(key)," unit=",unit.global_position if is_instance_valid(unit) else Vector2.INF,
				" stage=",unit.get("_coroner_stage") if is_instance_valid(unit) else "none")
		if observed.has("buried") and is_instance_valid(unit) and not unit.visible and (second_key.is_empty() or care.records()[second_key].phase=="buried"): break
	check(unit!=null, "A witnessed death dispatches an actual IML van")
	check(observed.has("carrying"), "Actual workers approach, bag and carry the victim")
	check(observed.has("transport") and observed.has("morgue"), "Actual van returns to the IML before cemetery release")
	check(observed.has("cemetery") and observed.has("burial") and observed.has("buried"), "Van reaches the gate and a worker physically reaches the reserved plot")
	check(travel>1000, "Transport covers the route without test teleports")
	check(cemetery._graves.size()==(1 if second_key.is_empty() else 2) and person.is_dead and not person.visible, "Burial creates one grave per victim and keeps the victim dead")
	if not second_key.is_empty():
		check(care.records()[second_key].phase=="buried" and care.records()[key].plot!=care.records()[second_key].plot,"Multiple victims retain distinct identities and separate plots")
	if OS.get_cmdline_user_args().has("crew_loss"):
		check(lost_crew and observed.has("recovery") and observed.has("buried"),"A killed carrier leaves recoverable cargo that a surviving team recollects")
	if OS.get_cmdline_user_args().has("fragments"):
		check(get_nodes_in_group("explosion_remains").is_empty() and int(care.records()[key].get("collected_parts",0))>=4, "All anatomical fragments are collected under one burial identity")
	if is_instance_valid(unit): check(not unit.visible, "The crew boards and the van returns to its depot")
	print("CORONER_PHYSICAL failures=",failures)
	world.queue_free()
	for i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)
