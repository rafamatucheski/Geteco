extends SceneTree
## Real Actor/Vehicle movement across the bridge and tunnel paving lips.
## The previous paving check started above the pavement and missed curb entry.
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0
var stage: Node3D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func floor_box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.position = center
	body.add_child(collision)
	stage.add_child(body)

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	stage.add_child(CONNECTION.new())
	# The regional road owns this native support, with asphalt at y=0.
	floor_box(Vector3(560,-.25,CONNECTION.CENTER_Z),Vector3(210,.5,8.75))
	# Terrain immediately beyond the east portal, outside the shared structure.
	floor_box(Vector3(CONNECTION.TUNNEL_END_X+4,-.25,CONNECTION.CENTER_Z),Vector3(8,.5,14))
	await physics_frame
	await physics_frame
	for bike in [false,true]:
		var body
		if bike:
			body = VEHICLE.new()
			body.archetype = "bike_urban"
			body.controlled = true
			body.external_input = true
		else:
			body = ACTOR.new()
			body.is_player = true
			body.controlled_automatically = true
		stage.add_child(body)
		body.set_physics_process(false)
		if bike: body.max_forward_speed = 2.0
		else: body.speed = 2.0
		var who := "bike_urban" if bike else "Dante"
		for side in [-1.0,1.0]:
			var routes := [
				{"id":"bridge_side","from":Vector3(520,.15,CONNECTION.CENTER_Z+side*3.5),"to":Vector3(520,.15,CONNECTION.CENTER_Z+side*5.65)},
				{"id":"tunnel_side","from":Vector3(605,.15,CONNECTION.CENTER_Z+side*2.9),"to":Vector3(605,.15,CONNECTION.CENTER_Z+side*5.65)},
				{"id":"west_portal","from":Vector3(CONNECTION.TUNNEL_START_X-3,.15,CONNECTION.CENTER_Z+side*5.65),"to":Vector3(CONNECTION.TUNNEL_START_X+3,.15,CONNECTION.CENTER_Z+side*5.65)},
				{"id":"east_portal","from":Vector3(CONNECTION.TUNNEL_END_X+3,.15,CONNECTION.CENTER_Z+side*5.65),"to":Vector3(CONNECTION.TUNNEL_END_X-3,.15,CONNECTION.CENTER_Z+side*5.65)}]
			for route in routes:
				await traverse(body,bike,route.from,route.to,"%s %s side=%s entry" % [who,route.id,side])
				await traverse(body,bike,route.to,route.from,"%s %s side=%s return" % [who,route.id,side])
			# The exterior wall and bridge rail must still block the whole body.
			for x in [520.0,605.0]:
				body.global_position = Vector3(x,.075,CONNECTION.CENTER_Z+side*5.65)
				body.rotation.y = 0.0
				check(body.test_move(body.global_transform,Vector3(0,0,side*3)),"%s outer barrier remains solid at x=%s side=%s" % [who,x,side])
		body.free()
		await physics_frame
	print("MOUNTAIN_TUNNEL_ACCESS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func traverse(body, bike: bool, start: Vector3, finish: Vector3, label: String) -> void:
	var direction := Vector3(finish.x-start.x,0,finish.z-start.z).normalized()
	if bike:
		body.place(start,atan2(-direction.x,-direction.z))
		body.throttle_input = 0.0
		body.brake_input = true
	else:
		body.teleport(start)
		body.automatic_direction = Vector3.ZERO
	for i in 24:
		await physics_frame
		body._physics_process(1.0/60.0)
	var reached := false
	var lowest: float = body.global_position.y
	var highest := lowest
	var contacts: Array[String] = []
	for i in 230:
		if bike:
			body.throttle_input = 1.0
			body.brake_input = false
		else: body.automatic_direction = direction
		await physics_frame
		body._physics_process(1.0/60.0)
		lowest = minf(lowest,body.global_position.y)
		highest = maxf(highest,body.global_position.y)
		for j in body.get_slide_collision_count():
			var collider := body.get_slide_collision(j).get_collider() as Node
			if collider == null: continue
			var id := str(collider.get_parent().name)
			if not contacts.has(id): contacts.append(id)
		var remaining := Vector3(finish.x-body.global_position.x,0,finish.z-body.global_position.z)
		if remaining.dot(direction) <= .10:
			reached = true
			break
	check(reached,label+" physically crosses the paving edge")
	check(lowest > -.10 and highest < .20,label+" stays supported without a vertical jump")
	print("MOUNTAIN_ACCESS_CASE ",JSON.stringify({"label":label,"reached":reached,"position":str(body.global_position),"low":lowest,"high":highest,"contacts":contacts}))
