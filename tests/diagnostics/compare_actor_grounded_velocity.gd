extends SceneTree
## Sonda diferencial isolada, não um benchmark de jogabilidade/FPS. As duas variantes
## compilam o código atual do Actor em memória; só a velocidade vertical no chão
## difere. O Actor, a cápsula, os degraus, a direção e o move_and_slide reais rodam.
## --fixed-fps 60 pode acelerar este diagnóstico funcional headless.
const ACTOR_PATH := "res://scripts/Actor.gd"
const PROPS := preload("res://world/harbor_route_detail/HarborRouteProps.gd")
const GROUNDED_LINE := "velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta"
const GROUNDED_ZERO_LINE := "velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta"
class MovingSupport extends AnimatableBody3D:
	var moving := false
	func _physics_process(delta: float) -> void:
		if moving: position += Vector3(1.0,-.15,0.0)*delta

var failures: Array[String] = []
var results: Array[Dictionary] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func variant_script(grounded: float) -> GDScript:
	var source := FileAccess.get_file_as_string(ACTOR_PATH).replace("\r\n", "\n")
	source = source.replace(GROUNDED_ZERO_LINE, GROUNDED_LINE)
	if source.count(GROUNDED_LINE) != 1:
		check(false,"Actor grounded expression changed; probe requires review")
		return null
	source = source.replace(GROUNDED_LINE, "velocity.y = %.1f if is_on_floor() else velocity.y - 20.0 * delta" % grounded)
	source = source.replace("extends CharacterBody3D", "extends CharacterBody3D\nvar ground_probe_move_usec := 0\nvar ground_probe_move_calls := 0")
	if source.count("\tmove_and_slide()\n") != 1:
		check(false,"Actor move boundary changed; probe requires review")
		return null
	source = source.replace("\tmove_and_slide()\n", "\tvar ground_probe_began := Time.get_ticks_usec()\n\tmove_and_slide()\n\tground_probe_move_usec += Time.get_ticks_usec()-ground_probe_began\n\tground_probe_move_calls += 1\n")
	var script := GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		check(false,"In-memory Actor variant compiled")
		return null
	return script

func box(parent: Node3D, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var mesh := BoxShape3D.new()
	mesh.size = size
	shape.shape = mesh
	body.add_child(shape)
	body.position = at
	parent.add_child(body)
	return body

func ramp(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for z in [-3.0,3.0]:
		points.append(Vector3(-4,0,z))
		points.append(Vector3(4,1.7,z))
		points.append(Vector3(-4,-.2,z))
		points.append(Vector3(4,-.2,z))
	shape.points = points
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)

func run() -> void:
	var cases := [
		{"id":"flat_idle","start":Vector3(0,.04,0),"direction":Vector3.ZERO,"ticks":180},
		{"id":"flat_walk","start":Vector3(-3,.04,0),"direction":Vector3.RIGHT,"ticks":150},
		{"id":"ramp_up","start":Vector3(-5,.04,0),"direction":Vector3.RIGHT,"ticks":240},
		{"id":"ramp_down","start":Vector3(3,1.6,0),"direction":Vector3.LEFT,"ticks":240},
		# Mesmo limite físico de velocidade usado por MountainProgression.motion.
		{"id":"ramp_down_ski_speed","start":Vector3(3,1.6,0),"direction":Vector3.LEFT,"ticks":24,"speed":455.0/16.0},
		{"id":"curb_up","start":Vector3(-3,.04,0),"direction":Vector3.RIGHT,"ticks":70},
		{"id":"curb_down","start":Vector3(-.7,.16,0),"direction":Vector3.LEFT,"ticks":100},
		{"id":"solid_wall","start":Vector3(-2,.04,0),"direction":Vector3.RIGHT,"ticks":75},
		{"id":"removed_support","start":Vector3(0,.04,0),"direction":Vector3.ZERO,"ticks":30},
	]
	for grounded in [-1.0,0.0]:
		var script := variant_script(grounded)
		if script == null: quit(2); return
		for spec in cases: await run_case(script,grounded,spec)
		await run_moving_support(script,grounded)
	print("ACTOR_GROUNDED_COMPARISON ",JSON.stringify({"checks":checks,"failures":failures,"results":results,"scope":"Functional isolated real Actor variants; method wall times only, not production FPS or CPU counters.","slope_note":"The -1 vertical component can alter slope travel after collision sliding. Uphill/downhill endpoints are reported separately; the contract is supported progress and descent to the floor, not identical flat-ground speed."}))
	quit(0 if failures.is_empty() else 1)

func run_case(script: GDScript, grounded: float, spec: Dictionary) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := box(stage,Vector3(40,.2,40),Vector3(0,-.1,0))
	if str(spec.id).begins_with("ramp_"): ramp(stage)
	if str(spec.id).begins_with("curb_"): stage.add_child(PROPS.create_sidewalk_slab(Vector2(4,4),.12))
	if spec.id == "solid_wall": box(stage,Vector3(1,3,8),Vector3(0,1.5,0))
	var actor = script.new()
	actor.controlled_automatically = true
	actor.speed = float(spec.get("speed",2.0))
	actor.position = spec.start
	stage.add_child(actor)
	for i in 20: await physics_frame
	check(actor.is_on_floor(),"%s grounded=%.1f initial support" % [spec.id,grounded])
	actor.ground_probe_move_usec = 0
	actor.ground_probe_move_calls = 0
	actor.automatic_direction = spec.direction
	var start: Vector3 = actor.position
	if spec.id == "removed_support": floor_body.free()
	var supported := 0
	var highest := actor.position.y as float
	var furthest := actor.position.x as float
	for i in int(spec.ticks):
		await physics_frame
		if actor.is_on_floor(): supported += 1
		highest = maxf(highest,actor.position.y)
		furthest = maxf(furthest,actor.position.x)
	var end: Vector3 = actor.position
	var valid := true
	match spec.id:
		"flat_idle": valid = end.distance_to(Vector3.ZERO) < .04 and supported >= int(spec.ticks)-1
		"flat_walk": valid = end.x > 1.8 and absf(end.y) < .04 and supported >= int(spec.ticks)-1
		"ramp_up": valid = end.x > 1.5 and end.y > 1.1 and actor.is_on_floor()
		"ramp_down": valid = end.x < -4.5 and absf(end.y) < .04 and actor.is_on_floor()
		"ramp_down_ski_speed": valid = end.x < -4.5 and absf(end.y) < .04 and actor.is_on_floor() and supported >= int(spec.ticks)-1
		"curb_up": valid = end.x > -1 and absf(end.y-.12) < .04 and actor.is_on_floor()
		"curb_down": valid = end.x < -3.5 and absf(end.y) < .04 and actor.is_on_floor()
		"solid_wall": valid = furthest < -.75 and highest < .04
		"removed_support": valid = end.y < -1 and not actor.is_on_floor()
	check(valid,"%s grounded=%.1f endpoint=%s supported=%d/%d" % [spec.id,grounded,end,supported,spec.ticks])
	results.append({"case":spec.id,"grounded_y":grounded,"start":str(start),"end":str(end),"displacement":str(end-start),"supported":supported,"ticks":spec.ticks,"highest":highest,"max_x":furthest,"move_calls":actor.ground_probe_move_calls,"move_wall_usec":actor.ground_probe_move_usec,"valid":valid})
	stage.free()
	await physics_frame

func run_moving_support(script: GDScript, grounded: float) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var platform := MovingSupport.new()
	# Match moving train solids: velocity inferred from physics transform updates.
	platform.sync_to_physics = false
	platform.process_physics_priority = -10
	platform.position = Vector3(0,.8,0)
	var collider := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(4,.4,4)
	collider.shape = hull
	platform.add_child(collider)
	stage.add_child(platform)
	var actor = script.new()
	actor.controlled_automatically = true
	actor.position = Vector3(0,1.04,0)
	stage.add_child(actor)
	for i in 20: await physics_frame
	check(actor.is_on_floor(),"moving_support grounded=%.1f initial support" % grounded)
	var start: Vector3 = actor.position
	actor.ground_probe_move_usec = 0
	actor.ground_probe_move_calls = 0
	platform.moving = true
	var supported := 0
	var max_relative_error := 0.0
	for i in 120:
		await physics_frame
		if actor.is_on_floor(): supported += 1
		var relative: Vector3 = actor.position-platform.position-Vector3.UP*.2
		max_relative_error = maxf(max_relative_error,relative.length())
	var carried_end: Vector3 = actor.position
	var carried: bool = actor.is_on_floor() and carried_end.x-start.x > 1.8 and max_relative_error < .08 and supported >= 119
	check(carried,"moving_support grounded=%.1f carried=%s supported=%d/120 relative_error=%.5f" % [grounded,carried_end,supported,max_relative_error])
	platform.free()
	for i in 30: await physics_frame
	var fall_end: Vector3 = actor.position
	var fell: bool = not actor.is_on_floor() and fall_end.y < carried_end.y-1.0
	check(fell,"moving_support grounded=%.1f removed platform falls=%s" % [grounded,fall_end])
	results.append({"case":"moving_support_and_removal","grounded_y":grounded,"start":str(start),"carried_end":str(carried_end),"fall_end":str(fall_end),"supported":supported,"ticks":120,"max_relative_error":max_relative_error,"move_calls":actor.ground_probe_move_calls,"move_wall_usec":actor.ground_probe_move_usec,"valid":carried and fell})
	stage.free()
	await physics_frame
