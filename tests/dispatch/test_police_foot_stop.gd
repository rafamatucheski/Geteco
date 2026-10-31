extends SceneTree
## Frenagem real e equipes despachadas quando nenhum acostamento pode ser planejado.
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const DRIVER := preload("res://gameplay/dispatch/DispatchDriver.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DT := 1.0/60.0
var checks := 0
var failures: Array[String] = []

class Unit extends "res://gameplay/dispatch/DispatchUnit.gd":
	var observed_target: Node3D
	func _target() -> Node3D: return observed_target
	func _sees_target(_target: Node3D) -> bool: return true

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	for id in ["police_cruiser", "bike_police"]: await approach(id)
	await approach("police_cruiser",true)
	print("POLICE_FOOT_STOP checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() and checks >= 20 else 1)

func approach(id: String, real_shoulder := false) -> void:
	var b := KIT.build(self, KIT.single_road(), Vector3(13,0,0))
	b.controller.set_physics_process(false)
	b.gameplay.set_physics_process(false)
	b.player.set_physics_process(false)
	b.gameplay.stars = 3
	b.gameplay.contact_age = 0.0
	b.gameplay.last_known = b.player.position
	var car: CharacterBody3D = b.controller._create_vehicle("police",Vector3.ZERO,-PI*.5,id)
	var u := Unit.new()
	u.controller = b.controller
	u.service = "police"
	u.vehicle = car
	u.variant = "motorcycle" if id == "bike_police" else "patrol"
	u.level = 3
	u.crew_capacity = u.RULES.crew_size(id)
	u.crew_remaining = u.crew_capacity
	u.observed_target = b.player
	u.driver = DRIVER.new()
	u.driver.setup(car,12.0,10.0)
	u.driver.disable_overtaking()
	if not real_shoulder: b.controller.routes.configure([])
	var path := Curve3D.new()
	path.add_point(Vector3.ZERO)
	path.add_point(Vector3(80,0,0))
	u.driver.set_route(path)
	b.controller.units.append(u)
	for _i in 5: await physics_frame
	car.speed = 8.0
	car.horizontal_velocity = Vector3.RIGHT * 8.0
	u._sync_motorcycle_rider()
	if id == "bike_police":
		var rider: Node3D = car._motorcycle_rider_parts[0]
		check(rider.get_meta("police_motorcycle_rider",false),"mounted motorcycle rider is a police officer")
		check(rider.body_source.is_empty() and rider.wardrobe_overrides.top == 6,"mounted officer uses uniform instead of generic imported civilian")
		check(rider.find_child("OfficerBadge",true,false) != null,"mounted uniform includes its own badge")
	if id == "police_cruiser" and not real_shoulder:
		var walls: Array[StaticBody3D] = []
		for side in [-1.0,1.0]: walls.append(KIT.add_wall(b.scene,Vector3(5,1.5,side*1.72),Vector3(25,3,.55)))
		for _i in 240:
			u.tick(DT)
			await physics_frame
		check(u.officers.is_empty() and u.state == "enroute","blocked doors keep crew aboard without driving circles")
		check(absf(car.speed) < .35,"blocked exits retain a physically stopped vehicle")
		for wall in walls: wall.queue_free()
		await physics_frame
	var worst_step := 0.0
	var previous: Vector3 = car.position
	var stopped := false
	var still_frame := -1
	var frame := 0
	for _i in 600:
		u.tick(DT)
		await physics_frame
		frame += 1
		worst_step = maxf(worst_step,previous.distance_to(car.position))
		previous = car.position
		if still_frame < 0 and absf(car.speed) < .35: still_frame = frame
		if not u.officers.is_empty():
			stopped = true
			break
	# 27/10: entre a viatura parar e a equipe descer havia até 3 s + 0,6 s de espera fixa.
	var exit_seconds := float(frame - still_frame) * DT if still_frame >= 0 else INF
	print("POLICE_FOOT_STOP %s parada->desce %.2f s" % [id + (" (acostamento)" if real_shoulder else ""), exit_seconds])
	check(stopped,id + " brakes and deploys its finite crew without a shoulder route")
	if stopped: check(exit_seconds <= 2.0,id + " crew starts leaving within 2 s of the stop (%.2f s)" % exit_seconds)
	if stopped:
		var acting := -1
		for _i in 120:
			u.tick(DT)
			await physics_frame
			if u.officers.any(func(o): return o.mode == "combat"):
				acting = _i + 1
				break
		print("POLICE_FOOT_STOP %s desce->age %.2f s" % [id, float(acting) * DT])
		check(acting > 0 and float(acting) * DT <= 1.0,id + " officer is acting within 1 s of leaving the vehicle")
	check(absf(car.speed) < .35,id + " disembark occurs only after physical stop")
	check(worst_step < .5,id + " braking never teleports the vehicle")
	check(u.crew_remaining < u.crew_capacity,id + " deployed officer consumes the seated crew slot")
	if id == "bike_police" and not u.officers.is_empty():
		check(not car._motorcycle_rider_parts[0].visible,"mounted rider disappears when officer dismounts")
		check(u.officers[0].motorcycle_officer,"dismounted rider retains motorcycle police identity")
	# O jogador volta para um carro em movimento: os mesmos policiais voltam e depois perseguem.
	var escaping := VEHICLE.new()
	escaping.archetype = "metro_hatch"
	b.scene.add_child(escaping)
	escaping.set_physics_process(false)
	escaping.position = car.position + Vector3(55,0,0)
	escaping.horizontal_velocity = Vector3.RIGHT * 10.0
	u.observed_target = escaping
	u._police_working(DT)
	check(u.state == "recall",id + " moving vehicle target recalls the same crew")
	# Se o suspeito sair de novo durante a chamada de volta, não termina o embarque por engano.
	u.observed_target = b.player
	u._police_recall(DT)
	check(u.state == "working" and u.officers.all(func(o): return o.mode in ["combat","disembark"]),id + " foot target interrupts recall without replacing officers")
	# Uma segunda entrada termina a travessia física da porta, volta e retoma.
	u.observed_target = escaping
	u._police_working(DT)
	for _i in 600:
		u._police_recall(DT)
		await physics_frame
		if u.state == "enroute": break
	check(u.state == "enroute" and u.officers.is_empty() and u.crew_remaining == u.crew_capacity,id + " officers physically reboard before pursuit resumes")
	u._sync_motorcycle_rider()
	if id == "bike_police": check(car._motorcycle_rider_parts[0].visible,"police rider returns to saddle after boarding")
	# A pending parking route must also be cancelled before a new car chase.
	u.state = "enroute"
	u.observed_target = escaping
	u.stop_planner.curve = path
	u.stop_planner.goal = b.player.position
	u._stall_police_enroute(DT)
	check(u.stop_planner.curve == null,id + " moving car target cancels stale parking route")
	# Equipes já paradas precisam retomar em vez de desembarcar numa perseguição de carro.
	u.state = "parked"
	u.state_age = 2.0
	u._police_parked(DT)
	check(u.state == "enroute",id + " parked unit resumes when the player drives away")
	KIT.teardown(b)
	await process_frame
