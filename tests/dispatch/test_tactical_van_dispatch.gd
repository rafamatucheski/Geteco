extends SceneTree
## Seleção, escalada e chamada de volta reais do dispatch. Contratos headless não
## certificam o trajeto na rua, a apresentação nem o tempo de quadro.
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
var checks := 0
var failures: Array[String] = []
var completed: Array[String] = []
var parked := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	parked = 0
	var b := KIT.build(self,KIT.grid_roads(),Vector3(0,.04,0))
	b.gameplay.set_physics_process(false)
	b.controller.set_physics_process(false)
	if is_instance_valid(b.gameplay.police_air): b.gameplay.police_air.set_physics_process(false)
	b.gameplay.last_known_valid = true
	b.gameplay.last_known = Vector3.ZERO
	return b

func dispatch(b: Dictionary, level: int) -> RefCounted:
	b.gameplay.stars = level
	var unit: RefCounted = b.controller.dispatch_police_to(Vector3.ZERO)
	if unit != null:
		unit.vehicle.set_physics_process(false)
		# Mantém os spawns reais de rua livres entre as chamadas. Esta fixture confere
		# a composição do dispatch; dirigir a rota é validado à parte.
		unit.vehicle.place(Vector3(60,.12,-56 + parked * 13),0.0)
		parked += 1
	await physics_frame
	await physics_frame
	return unit

func fill_four_stars(b: Dictionary) -> bool:
	for index in RULES.MAX_ACTIVE[4]:
		var unit: RefCounted = await dispatch(b,4)
		if unit == null:
			check(false,"four-star fixture dispatch %d has a real clear spawn and route" % index)
			return false
	return true

func escalation() -> void:
	var b := fixture()
	await physics_frame
	if not await fill_four_stars(b): KIT.teardown(b); return
	var controller: Node3D = b.controller
	var old: RefCounted = controller.units[0]
	check(old.variant == "tactical" and old.vehicle.archetype == "police_cruiser","four-star tactical response remains a cruiser")
	check(RULES.tactical_van_count(controller._active_police()) == 0,"a tactical cruiser does not count as a transport van")
	var van: RefCounted = await dispatch(b,5)
	check(van != null and van.vehicle.archetype == "police_transport","full four-star response makes room for its first five-star van")
	if van == null: KIT.teardown(b); return
	check(old.state == "departing" and old.crew_remaining == 2 and not old.finished,"ordinary crew departs normally without deleting or replacing its officers")
	check(controller._active_police().size() == RULES.MAX_ACTIVE[5],"composition replacement preserves the existing active-unit cap")
	check(van.crew_capacity == 6 and van.crew_remaining == 6,"transport keeps its finite six-officer crew")
	check(RULES.response_variant(5,controller._active_police()) == "interceptor","five stars keep one responding van rather than flooding the formation")
	van._begin_recall(true)
	var replacement: RefCounted = await dispatch(b,5)
	check(replacement != null and replacement.vehicle.archetype == "police_transport","a recalling van does not suppress the next responding van")
	if replacement == null: KIT.teardown(b); return
	var tank: RefCounted = await dispatch(b,6)
	check(tank != null and tank.variant == "tank","six-star tank support still follows the first responding van")
	if tank == null: KIT.teardown(b); return
	var second: RefCounted = await dispatch(b,6)
	check(second != null and second.vehicle.archetype == "police_transport","six stars admit the second van by replacing one ordinary crew")
	check(RULES.tactical_van_count(controller._active_police()) == 2,"six stars count exactly two responding transport vans")
	check(controller._active_police().size() <= RULES.MAX_ACTIVE[6] and controller.units.size() <= RULES.MAX_UNITS,"all live and active caps remain bounded through escalation")
	var extra: RefCounted = await dispatch(b,6)
	check(extra == null,"a full response with both vans cannot gain another active vehicle")
	completed.append("escalation")
	KIT.teardown(b)
	await process_frame

func blocked_spawn() -> void:
	var b := fixture()
	await physics_frame
	if not await fill_four_stars(b): KIT.teardown(b); return
	KIT.add_wall(b.scene,Vector3(0,2,0),Vector3(400,8,400))
	await physics_frame
	var van: RefCounted = await dispatch(b,5)
	check(van == null,"blocked van spawning fails instead of materializing through solids")
	check(b.controller.events_named("tactical_van_replacement").is_empty(),"failed van spawn cannot dismiss the existing response")
	check(b.controller._active_police().size() == RULES.MAX_ACTIVE[4] and b.controller.units.all(func(u): return u.state == "enroute"),"all previous crews remain assigned after spawn failure")
	completed.append("blocked_spawn")
	KIT.teardown(b)
	await process_frame

func direct_six_stars() -> void:
	var b := fixture()
	await physics_frame
	if not await fill_four_stars(b): KIT.teardown(b); return
	var first: RefCounted = await dispatch(b,6)
	check(first != null and first.vehicle.archetype == "police_transport","direct four-to-six escalation fills the free slot with its first van")
	if first == null: KIT.teardown(b); return
	var second: RefCounted = await dispatch(b,6)
	check(second != null and second.vehicle.archetype == "police_transport","at a full cap the second van cannot be starved by pending tank support")
	check(RULES.tactical_van_count(b.controller._active_police()) == 2 and b.controller._active_police().size() == RULES.MAX_ACTIVE[6],"direct escalation reaches its van quota without expanding the cap")
	var tank: RefCounted = await dispatch(b,6)
	check(tank != null and tank.variant == "tank","once both vans respond the existing six-star tank support can replace an ordinary crew")
	check(RULES.tactical_van_count(b.controller._active_police()) == 2 and b.controller._active_police().filter(func(u): return u.variant == "tank").size() == RULES.MAX_TANKS,"tank reinforcement preserves both vans and the one-tank quota")
	check(b.controller._active_police().size() == RULES.MAX_ACTIVE[6] and b.controller.units.size() <= RULES.MAX_UNITS,"armor support replacement preserves active and total caps")
	var excess: RefCounted = await dispatch(b,6)
	check(excess == null,"a complete two-van one-tank response rejects excess reinforcements")
	completed.append("direct_six")
	KIT.teardown(b)
	await process_frame

func stranded_departure() -> void:
	var b := fixture()
	await physics_frame
	if not await fill_four_stars(b): KIT.teardown(b); return
	var van: RefCounted = await dispatch(b,5)
	if van == null:
		check(false,"stranded fixture receives its initial van")
		KIT.teardown(b)
		return
	var old: RefCounted = b.controller.units[0]
	var ordinary: RefCounted = b.controller.units[1]
	old.stranded = true
	old.stranded_age = 200.0
	ordinary.abort_response()
	ordinary.stranded = true
	ordinary.stranded_age = 100.0
	van.abort_response()
	van.stranded = true
	van.stranded_age = 1.0
	check(b.controller._active_police().has(van),"third stranded departure still counts toward the active-unit cap")
	var available: RefCounted = b.controller.units[2]
	check(b.controller._tactical_van_replacement(5,[old,available],[]) == available,"a departing ordinary crew cannot eclipse a valid composition replacement")
	var replacement: RefCounted = await dispatch(b,5)
	check(replacement != null and replacement.vehicle.archetype == "police_transport","a departing stranded van does not satisfy the responding van quota")
	check(van.state == "departing" and not van.finished,"replacement does not delete or reactivate a stranded outgoing van")
	completed.append("stranded_departure")
	KIT.teardown(b)
	await process_frame

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(45.0).timeout.connect(func(): push_error("TACTICAL_VAN timeout"); quit(3))
	check(RULES.tactical_van_limit(4) == 0 and RULES.response_archetype(4,"tactical") == "police_cruiser","transport eligibility still begins at five stars")
	check(RULES.tactical_van_limit(5) == 1 and RULES.tactical_van_limit(6) == 2,"existing one/two van quotas remain proportional to wanted level")
	await escalation()
	await blocked_spawn()
	await direct_six_stars()
	await stranded_departure()
	check(completed.size() == 4 and checks >= 29,"all integration scenarios completed the required checks")
	print("TACTICAL_VAN checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)
