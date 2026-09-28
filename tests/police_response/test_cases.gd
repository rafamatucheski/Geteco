extends SceneTree
const KIT = preload("res://tests/dispatch/DispatchTestKit.gd")
const VEHICLE = preload("res://scripts/Vehicle.gd")
class ContextState extends KIT.CombatState:
	var place_id := ""
	var region_id := "harbor"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	var bundle := KIT.build(self, KIT.grid_roads(), Vector3(0, .04, 0))
	var game: Node3D = bundle.gameplay
	game.set_physics_process(false)
	game.police_air.set_physics_process(false)
	bundle.controller.set_physics_process(false)
	var case: Node = game.police_case
	await physics_frame
	check(not game.report_observed_crime(15, game.player.position, "theft"), "unwitnessed theft does not identify the player")
	check(game.stars == 0 and case.pending.is_empty(), "no automatic wanted without evidence")
	var witness := KIT.add_patient(bundle.scene, Vector3(4, .04, 0), 100)
	witness.controlled_automatically = true
	await physics_frame
	check(game.report_observed_crime(15, game.player.position, "theft"), "civilian perceives unobstructed theft")
	case.tick(2.0)
	check(game.stars == 0, "civilian needs time to report")
	var observed: Vector3 = game.player.position
	game.player.position = Vector3(-20, .04, 0)
	case.tick(.6)
	check(game.stars == 1 and game.last_known.distance_to(observed) < .1, "testimony reports observed location, not fleeing player")
	check(not game.police_force_authorized(), "theft does not authorize lethal force")
	game.clear_wanted()
	game.player.position = observed
	var wall := KIT.add_wall(bundle.scene, Vector3(2, 1.5, 0), Vector3(.5, 3, 8))
	await physics_frame
	check(game.report_observed_crime(4, observed, "gunfire"), "gunfire can be heard behind wall")
	case.tick(2.6)
	check(game.stars == 0 and case.investigation_left > 0, "hearing opens location investigation without identity")
	bundle.controller._dispatch_police(1.0)
	check(bundle.controller.investigation_unit != null and bundle.controller.investigation_unit.state == "investigating", "unidentified report dispatches one real investigator")
	var investigation_count: int = bundle.controller.units.size()
	bundle.controller._dispatch_police(21.0)
	check(bundle.controller.units.size() == investigation_count and game.stars == 0, "investigation neither floods reinforcements nor identifies player")
	bundle.controller.dismiss_all("case_test")
	wall.queue_free()
	await physics_frame
	game.clear_wanted()
	game.report_observed_crime(12, observed, "assault", witness)
	witness.dead = true
	case.tick(2.6)
	check(game.stars == 0, "incapacitated witness cannot complete testimony")
	witness.queue_free()
	await physics_frame
	var context := ContextState.new()
	game.state = context
	var caller := KIT.add_patient(bundle.scene, Vector3(4, .04, 0), 100)
	caller.controlled_automatically = true
	await physics_frame
	game.report_observed_crime(15, observed, "theft")
	context.place_id = "maciota"
	context.safe = true
	case.tick(2.6)
	check(game.stars == 1 and case.case_place.is_empty(), "entering safe garage cannot erase an already witnessed exterior offense")
	check(not game.police_force_authorized(), "delayed testimony preserves garage protection")
	caller.queue_free()
	game.clear_wanted()
	game.state = bundle.state
	game.register_crime(420, observed, "reported")
	check(game.stars == 6 and not game.police_force_authorized(), "six stars alone do not authorize shots")
	game.register_crime(1, observed, "police_assault")
	check(game.police_force_authorized(), "confirmed violence authorizes response")
	case.tick(1.1)
	game.player.velocity = Vector3.ZERO
	var police_source := Node3D.new()
	police_source.set_meta("gameplay_role","police")
	var vehicle_source := Node3D.new()
	vehicle_source.set_meta("dispatch_unit",true)
	var civilian_source := Node3D.new()
	civilian_source.set_meta("gameplay_role","civilian")
	for source in [police_source,vehicle_source,civilian_source]:
		bundle.scene.add_child(source)
		game._police_rounds.append({"source":weakref(source),"point":Vector3.ZERO,"visual":{}})
	check(case.request_surrender(), "surrender available at six stars while stationary")
	check(game.police_can_arrest() and not game.police_force_authorized() and not game.attack_allowed(), "surrender permits arrest and suppresses both sides' attacks")
	check(game._police_rounds.size() == 1 and game._police_rounds[0].source.get_ref() == civilian_source, "surrender removes police rounds while preserving hostile civilian bullets")
	game._police_rounds.clear()
	game.player.velocity = Vector3(3, 0, 0)
	case.tick(.1)
	check(not game.police_surrendering(), "moving cancels surrender")
	game.player.velocity = Vector3.ZERO
	game.contact_age = 10
	game.hidden_time = 121
	game._update_police(.02)
	check(game.stars == 5, "first evasion lowers one star")
	var descending_save: Dictionary = game.snapshot()
	check(game.restore_state(descending_save) and case.descending, "save restores ongoing gradual evasion")
	game.contact_age = 10
	game.hidden_time = 8.1
	game._update_police(.02)
	check(game.stars == 4, "restored evasion keeps eight-second subsequent star interval")
	for index in 4:
		game.hidden_time = 8.1
		game._update_police(.02)
	check(game.stars == 0 and game.police_investigation_active(), "escape leaves a physical investigation case")
	var saved: Dictionary = game.snapshot()
	check(game.validate_snapshot(saved), "investigation snapshot valid")
	game.clear_wanted()
	check(game.restore_state(saved) and game.police_investigation_active(), "investigation survives save restore")
	var legacy := saved.duplicate(true)
	legacy.police_case.erase("descending")
	legacy.police_case.erase("pending")
	check(game.validate_snapshot(legacy), "older saves without evasion and pending testimony fields remain valid")
	var bad_descending := saved.duplicate(true)
	bad_descending.police_case.descending = 1
	check(not game.restore_state(bad_descending), "numeric evasion flag is rejected atomically")
	var invalid := saved.duplicate(true)
	invalid.police_case.remaining = INF
	check(not game.restore_state(invalid), "malformed investigation rejected atomically")
	check(game.police_investigation_active(), "invalid restore preserves valid investigation")
	case.tick(301)
	check(not game.police_investigation_active(), "case expires after bounded investigation")
	bundle.state.safe = true
	game.report_observed_crime(100, observed, "gunfire")
	game.register_crime(100, observed, "gunfire")
	check(game.stars == 0 and not case.request_surrender(), "garage safe state rejects crimes and arrests")
	KIT.teardown(bundle)
	await process_frame
	await vehicle_testimony_persistence()
	check(checks >= 42,"all case and persistence checks executed")
	print("POLICE_CASES checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

func vehicle_testimony_persistence() -> void:
	var bundle := KIT.build(self,KIT.grid_roads(),Vector3(-15,.05,4))
	var game: Node3D = bundle.gameplay
	game.set_physics_process(false)
	game.police_air.set_physics_process(false)
	bundle.controller.set_physics_process(false)
	var case: Node = game.police_case
	var context := ContextState.new()
	game.state = context
	var car := VEHICLE.new()
	car.archetype = "coupe"
	bundle.scene.add_child(car)
	car.position = Vector3(0,.05,0)
	car.set_physics_process(false)
	var caller := KIT.add_patient(bundle.scene,Vector3(5,.05,0),100)
	caller.controlled_automatically = true
	await physics_frame
	await physics_frame
	check(not case.visible_event(caller,car.global_position) and case.visible_event(caller,car.global_position,car), "subject vehicle hull is visible evidence rather than an occluding wall")
	check(game.report_observed_crime(15,car.global_position,"theft",car), "civilian witnesses theft of a real physical vehicle")
	case.tick(2.6)
	check(game.stars == 1 and game.last_known.distance_to(car.global_position) < .1,"vehicle theft testimony reports the vehicle scene")
	game.clear_wanted()
	var wall := KIT.add_wall(bundle.scene,Vector3(3,1.5,0),Vector3(.4,3,7))
	await physics_frame
	await physics_frame
	check(not game.report_observed_crime(15,car.global_position,"theft",car), "a real wall still blocks observing vehicle theft")
	wall.queue_free()
	await physics_frame
	await physics_frame
	check(game.report_observed_crime(15,car.global_position,"theft",car), "unobstructed testimony starts before save")
	case.tick(.7)
	var saved: Dictionary = game.snapshot()
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(saved))
	check(game.validate_snapshot(persisted) and persisted.police_case.pending.size() == 1,"pending testimony survives JSON serialization without actor references")
	check(case.pending[0].witnesses.size() == 1 and not case.pending[0].get("departed_heard",false), "taking a snapshot does not commit or detach live testimony")
	caller.dead = true
	case.tick(2.0)
	check(game.stars == 0,"a witness incapacitated after saving still cannot report in the live session")
	check(game.restore_state(persisted) and case.pending.size() == 1,"load resumes the call instead of silently losing witnessed crime")
	case.tick(1.0)
	check(game.stars == 0,"restored call retains its remaining delay")
	case.tick(.81)
	check(game.stars == 1,"restored identified testimony reaches the police after its deadline")
	var bad_age := persisted.duplicate(true)
	bad_age.police_case.pending[0].age = INF
	check(not game.restore_state(bad_age) and game.stars == 1,"invalid pending countdown is rejected without changing the active case")
	var bad_points := persisted.duplicate(true)
	bad_points.police_case.pending[0].points = 15.5
	check(not game.validate_snapshot(bad_points),"fractional crime points in pending testimony are rejected")
	var oversized := persisted.duplicate(true)
	for index in 24: oversized.police_case.pending.append(persisted.police_case.pending[0].duplicate(true))
	check(not game.validate_snapshot(oversized),"save cannot exceed the 24 pending-report budget")
	game.clear_wanted()
	caller.dead = false
	game.report_observed_crime(15,car.global_position,"theft",car)
	case.tick(.6)
	caller.dead = true
	check(game.snapshot().police_case.pending.is_empty(),"already incapacitated witnesses produce no serialized testimony")
	game.clear_wanted()
	caller.dead = false
	game.report_observed_crime(15,car.global_position,"theft",car)
	case.tick(.6)
	game.on_region_changed()
	caller.queue_free()
	await process_frame
	context.region_id = "mountain"
	game.player.position = Vector3(70,.05,0)
	case.tick(1.0)
	check(game.stars == 0,"streaming unload keeps the testimony countdown")
	case.tick(1.0)
	check(game.stars == 1 and case.case_region == "harbor" and game.last_known.distance_to(car.global_position) < .1,"live witness testimony survives unload and retains the original region and position")
	KIT.teardown(bundle)
	await process_frame
