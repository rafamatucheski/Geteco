extends SceneTree

const ACTOR := preload("res://scripts/Actor.gd")
const PROPS := preload("res://world/harbor_route_detail/HarborRouteProps.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func box(parent: Node3D, size: Vector3, point: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var geometry := BoxShape3D.new()
	geometry.size = size
	shape.shape = geometry
	body.add_child(shape)
	body.position = point
	parent.add_child(body)
	return body

func ticks(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	box(stage, Vector3(40, .2, 40), Vector3(0, -.1, 0))
	var slab := PROPS.create_sidewalk_slab(Vector2(4, 4), .12)
	stage.add_child(slab)
	for player in [true, false]:
		var actor = ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		stage.add_child(actor)
		for speed in [1.6, 3.5, 6.5]:
			actor.speed = speed
			for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1,0,1), Vector3(-1,0,1), Vector3(1,0,-1), Vector3(-1,0,-1)]:
				actor.automatic_direction = Vector3.ZERO
				actor.teleport(side * 3.0 + Vector3.UP * .02)
				actor._steering = null
				await ticks(5)
				actor.automatic_direction = -side.normalized()
				await ticks(ceili((side.length()*3.0 - .9) / speed * 60.0))
				var label := "player=%s speed=%.1f side=%s position=%s" % [player, speed, side, actor.position]
				check(Vector2(actor.position.x, actor.position.z).length() < 1.2 and absf(actor.position.y - .12) < .04, "climb " + label)
				actor.automatic_direction = side.normalized()
				await ticks(ceili(3.6 / speed * 60.0))
				check(absf(actor.position.y) < .04, "descend " + label)
		actor.free()
	# The real modular curb in both orientations, including its narrow ends.
	slab.free()
	var curb := PROPS.create_curb_segment(4, .30, .14)
	stage.add_child(curb)
	var actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	actor.speed = 3.5
	stage.add_child(actor)
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		actor.automatic_direction = Vector3.ZERO
		actor.teleport(side * (1.2 if side.x != 0 else 3.0) + Vector3.UP * .02)
		await ticks(5)
		actor.automatic_direction = -side
		await ticks(45 if side.x != 0 else 65)
		check(actor.position.dot(side) < -.2 if side.x != 0 else actor.position.dot(side) < 1.3, "curb side " + str(side) + " position=" + str(actor.position))
	curb.free()
	# Use the actual city batch builder; the video planter was a MultiMesh.
	var chunk := Node3D.new()
	stage.add_child(chunk)
	DRESSING._flush(chunk, {"planter": [Transform3D.IDENTITY]})
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		actor.automatic_direction = Vector3.ZERO
		actor.teleport(side * 1.8 + Vector3.UP * .02)
		await ticks(5)
		actor.automatic_direction = -side
		await ticks(45)
		check(actor.position.dot(side) > .80 and actor.position.y < .04, "planter blocks walking " + str(side) + " position=" + str(actor.position))
	actor.automatic_direction = Vector3.ZERO
	actor.teleport(Vector3(10,.02,10))
	var citizen = ACTOR.new()
	citizen.controlled_automatically = true
	stage.add_child(citizen)
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		citizen.automatic_direction = Vector3.ZERO
		citizen.teleport(side * 1.8 + Vector3.UP * .02)
		citizen._steering = null
		await ticks(5)
		citizen.automatic_direction = -side
		var clear := true
		for i in 100:
			await physics_frame
			# The NPC may steer around the planter, but cannot enter its stone
			# footprint or gain height by walking through the foliage.
			clear = clear and (absf(citizen.position.x) > .55 or absf(citizen.position.z) > .55) and citizen.position.y < .04
		check(clear, "NPC respects planter volume " + str(side))
	citizen.free()
	# Height alone must not turn furniture into a walkable step.
	chunk.free()
	var low_solid := box(stage, Vector3(4, .14, 4), Vector3(0, .07, 0))
	actor.automatic_direction = Vector3.ZERO
	actor.teleport(Vector3(3, .02, 0))
	await ticks(5)
	actor.automatic_direction = Vector3.LEFT
	await ticks(45)
	check(actor.position.x > 2.15, "unclassified low solid is not auto-stepped")
	low_solid.free()
	# A low overhead beam must prevent a step that would intersect the head.
	var ceiling := box(stage, Vector3(8, .1, 8), Vector3(0, 1.80, 0))
	var paving := PROPS.create_sidewalk_slab(Vector2(4, 4), .14)
	stage.add_child(paving)
	actor.automatic_direction = Vector3.ZERO
	actor.teleport(Vector3(3, .02, 0))
	await ticks(5)
	actor.automatic_direction = Vector3.LEFT
	await ticks(45)
	check(actor.position.x > 2.15 and actor.position.y < .04, "step checks head clearance")
	ceiling.free()
	paving.free()
	var high_paving := PROPS.create_sidewalk_slab(Vector2(4, 4), .40)
	stage.add_child(high_paving)
	actor.automatic_direction = Vector3.ZERO
	actor.teleport(Vector3(3, .02, 0))
	await ticks(5)
	actor.automatic_direction = Vector3.LEFT
	await ticks(45)
	check(actor.position.x > 2.25 and actor.position.y < .04, "high paving remains a wall")
	stage.free()
	print("CURB_ACCESS checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
