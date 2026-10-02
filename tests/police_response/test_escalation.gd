extends SceneTree
const KIT = preload("res://tests/dispatch/DispatchTestKit.gd")
const PRESENTATION = preload("res://ui/hud/WantedPresentation.gd")
const RULES = preload("res://gameplay/dispatch/DispatchRules.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	var b := KIT.build(self, KIT.grid_roads(), Vector3(0,.04,0))
	var game: Node3D = b.gameplay
	game.set_physics_process(false)
	game.police_air.set_physics_process(false)
	b.controller.set_physics_process(false)
	var case: Node = game.police_case
	await physics_frame
	for shot in 200: game.register_crime(4, Vector3.ZERO, "gunfire")
	check(game.crime_points == 4, "one burst cannot promote the player by bullet count")
	check(game.restore_state(JSON.parse_string(JSON.stringify(game.snapshot()))), "shot episode can be restored from JSON")
	game.register_crime(4,Vector3.ZERO,"gunfire")
	check(game.crime_points == 4, "save and reload cannot reset the shot episode cooldown")
	for episode in 100:
		case.tick(3.1)
		game.register_crime(4, Vector3.ZERO, "gunfire")
	check(game.stars == 2, "sustained warning shots alone never summon helicopter or army")
	game.clear_wanted()
	for alarm in 100: game.register_crime(40, Vector3.ZERO)
	check(game.stars == 3, "repeated nonfatal alarms cannot summon maximum response")
	game.clear_wanted()
	for theft in 20: game.register_crime(60, Vector3.ZERO, "police_theft")
	check(game.stars == 2, "stealing police cars cannot buy whole high-level stars")
	game.clear_wanted()
	for hit in 100: game.register_crime(12, Vector3.ZERO, "assault")
	check(game.stars == 4, "nonfatal violence can summon specialists but not maximum response")
	game.hidden_time = 20.0
	game.register_crime(0,Vector3.ONE,"police_assault")
	check(game.hidden_time == 0.0 and game.last_known == Vector3.ONE and game.crime_points == 259, "confirmed assault interrupts escape even without adding points")
	case.tick(121.0)
	check(game.stars == 4, "time alone never raises the wanted level")
	game.clear_wanted()
	game.register_crime(100, Vector3.ZERO, "assault")
	for death in 12: game.register_crime(30, Vector3.ZERO, "civilian_killed")
	check(game.stars == 4, "even sudden mass casualties do not instantly summon the army")
	case.tick(60.0)
	check(game.stars == 4, "elapsed escalation delay needs a new grave crime")
	game.register_crime(30, Vector3.ZERO, "civilian_killed")
	check(game.stars == 5, "continued grave violence after one minute reaches five stars")
	case.tick(60.0)
	for death in 5: game.register_crime(30, Vector3.ZERO, "civilian_killed")
	check(game.stars == 6, "prolonged mass violence reaches maximum response after two minutes")
	game.report_contact(Vector3.ZERO)
	check(game.police_evasion_progress() == 0.0, "actual contact cancels evasion progress")
	game.contact_age = 2.0
	game.hidden_time = 22.5
	check(is_equal_approx(game.police_evasion_progress(), .5), "six-star evasion has a readable 45-second first interval")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game.snapshot()))
	check(game.restore_state(saved) and case.escalation.fatal_points == 540, "JSON save preserves confirmed fatal gravity")
	var invalid := saved.duplicate(true)
	invalid.police_case.escalation.seconds = INF
	check(not game.restore_state(invalid) and game.stars == 6, "invalid escalation restore is rejected atomically")
	var legacy := saved.duplicate(true)
	legacy.police_case.erase("escalation")
	check(game.validate_snapshot(legacy), "old saves remain compatible")
	game.contact_age = 2.0
	game.hidden_time = 45.1
	game._update_police(.02)
	check(game.stars == 5 and case.descending, "first lost star starts gradual recovery")
	for remaining in 5:
		game.hidden_time = 8.1
		game._update_police(.02)
	check(game.stars == 0 and case.phase() == "investigation" and case.escalation.fatal_points == 0, "escape keeps local investigation but closes the escalation episode")
	game.register_crime(4, Vector3.ZERO, "gunfire")
	check(game.stars == 0, "new small offense cannot inherit the previous maximum response")
	game.clear_wanted()
	# Real damage -> death -> surviving witness -> delayed report, once per victim.
	var witness := KIT.add_patient(b.scene, Vector3(3,.04,0),100)
	witness.set_physics_process(false)
	var victim := KIT.add_patient(b.scene, Vector3(1,.04,0),10)
	victim.set_physics_process(false)
	await physics_frame
	game._damage(victim, 100.0, game.player)
	check(victim.dead and case.pending.size() == 1 and case.pending[0].kind == "civilian_killed", "fatal civilian damage creates a distinct witnessed homicide")
	game._damage(victim, 100.0, game.player)
	case.tick(2.6)
	check(case.escalation.fatal_points == 30 and game.crime_points == 30, "shooting a corpse cannot duplicate its death")
	game.clear_wanted()
	witness.position = Vector3(6,.04,0)
	var hidden_victim := KIT.add_patient(b.scene,Vector3(5,.04,0),10)
	hidden_victim.set_physics_process(false)
	KIT.add_wall(b.scene,Vector3(3,1.5,0),Vector3(.5,3,8))
	await physics_frame
	game._damage(hidden_victim,100.0,game.player)
	case.tick(2.6)
	check(hidden_victim.dead and case.escalation.fatal_points == 0 and game.stars == 0, "seeing a body behind a wall cannot identify the hidden shooter")
	b.state.safe = true
	game.register_crime(30, Vector3.ZERO, "civilian_killed")
	check(game.stars == 0 and case.escalation.fatal_points == 0 and not game.attack_allowed(), "garage protection precedes scoring and combat")
	check(RULES.variant_for(3,true) == "interceptor" and RULES.variant_for(4,true) == "tactical", "specialist ground teams begin at four stars")
	var normal := PRESENTATION.text_for(3,"pursuit",0,0)
	check(normal == PRESENTATION.text_for(3,"pursuit",0,1.0), "stars remain steady while police have contact")
	check(PRESENTATION.text_for(3,"search",.5,0) != PRESENTATION.text_for(3,"search",.5,.6), "search stars visibly pulse with time")
	check(PRESENTATION.text_for(3,"search",.9,.25) != PRESENTATION.text_for(3,"search",.5,.25), "last star pulses faster near disappearance")
	check(PRESENTATION.text_for(0,"clear",0,0).is_empty(), "clearing the case removes the wanted display")
	KIT.teardown(b)
	await process_frame
	print("POLICE_ESCALATION checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)
