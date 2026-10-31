extends SceneTree
const BUDGET := preload("res://gameplay/lights/LightBudget.gd")
class Owner extends Node3D:
	var light: SpotLight3D
	var player := false
	var enabled := true
	var priority := 0
	func _ready() -> void:
		light = SpotLight3D.new()
		light.light_energy = 2.0
		light.set_meta("budget_energy",2.0)
		add_child(light)
	func _budget_request() -> Dictionary:
		var source := {"light":light,"headlight":priority == 0}
		if priority > 0: source.priority = priority
		return {"lights":[light],"wanted":[source] if enabled else [],"camera":Vector3.ZERO,"player":player,"decal":null,"pool":false}
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func run() -> void:
	Engine.max_fps = 60
	var owners: Array[Owner] = []
	for distance in [2.0,5.0,10.0,10.2]:
		var owner := Owner.new()
		owner.position.z = distance
		owner.player = owners.is_empty()
		root.add_child(owner)
		owners.append(owner)
		BUDGET.register(owner)
	for i in 24:
		await process_frame
		BUDGET.refresh(true)
	check(owners[1].light.visible and owners[2].light.visible and not owners[3].light.visible,"two nearest traffic sources settle")
	var flickers := 0
	var driver_failures := 0
	for i in 60:
		owners[3].position.z = 9.8 if i%2==0 else 10.2
		await process_frame
		BUDGET.refresh(true)
		if not owners[2].light.visible or owners[3].light.visible: flickers += 1
		if not owners[0].light.visible or not is_equal_approx(owners[0].light.light_energy,2.0): driver_failures += 1
	check(flickers==0,"distance ties cannot make full-powered traffic beams ping-pong")
	owners[3].position.z = 8.0
	var previous := owners[3].light.light_energy if owners[3].light.visible else 0.0
	var last := Time.get_ticks_usec()
	var jumps := 0
	var over_budget := 0
	for i in 30:
		await process_frame
		BUDGET.refresh(true)
		var now := Time.get_ticks_usec()
		var energy := owners[3].light.light_energy if owners[3].light.visible else 0.0
		if absf(energy-previous)>2.0*float(now-last)/1000000.0/.16+.04: jumps += 1
		previous = energy
		last = now
		if BUDGET.counts().active_lights>8: over_budget += 1
		if not owners[0].light.visible: driver_failures += 1
	check(jumps==0,"a closer replacement fades in without a full-energy jump")
	check(not owners[2].light.visible and owners[3].light.visible,"closer replacement settles and releases retiring source")
	check(driver_failures==0 and over_budget==0,"handoff preserves player source and total light budget")
	owners[3].enabled = false
	BUDGET.refresh(true)
	check(not owners[3].light.visible,"power-off cannot leave a fading ghost source")
	for owner in owners:
		BUDGET.unregister(owner)
		owner.free()
	BUDGET.refresh(true)
	check(BUDGET.counts().registered==0,"despawn releases all owners")
	# Lanterna do jogador e holofote da perseguição (campo priority) vencem oito projetores do
	# jogador colados na câmera, mesmo fora do raio de 25 m, e o teto de oito continua.
	var crowd: Array[Owner] = []
	for i in 10:
		var owner := Owner.new()
		owner.position.z = 1.0 + i
		owner.player = i < 8
		root.add_child(owner)
		crowd.append(owner)
	crowd[8].priority = BUDGET.PRIORITY_PLAYER_LANTERN
	crowd[9].priority = BUDGET.PRIORITY_PURSUIT
	crowd[9].position = Vector3(0,22,40)
	for owner in crowd: BUDGET.register(owner)
	await process_frame
	BUDGET.refresh(true)
	check(crowd[8].light.visible and crowd[9].light.visible,"priority sources keep their slot")
	check(is_equal_approx(crowd[9].light.light_energy,2.0),"priority source beyond 25 m does not fade")
	check(BUDGET.counts().active_lights<=8 and not crowd[7].light.visible,"priority still respects the global cap")
	for owner in crowd:
		BUDGET.unregister(owner)
		owner.free()
	quit(1 if failures else 0)
