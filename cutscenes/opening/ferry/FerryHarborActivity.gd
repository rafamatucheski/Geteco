extends RefCounted
## Bounded, seekable choreography for the offline film. Gameplay managers stay
## suspended; every take uses the same clock, routes and native cargo machinery.
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const WORKER := preload("res://gameplay/urban_v1/PortWorker.gd")
const VISITOR := preload("res://gameplay/urban_v1/PortVisitor.gd")
const ART := preload("res://world/regions/PortLifeArt.gd")
var workers: Array = []
var fishers: Array = []
var boats: Array = []
var cargo

func configure(world) -> void:
	cargo = world.session.urban_operations.cargo_handling
	# One porter works between the existing boxes beside the passenger quay.
	# His lane stays west of the stair landing and clear of the boarding ramp.
	var porter := WORKER.new()
	porter.configure({"id":"FilmQuayPorter","kind":"dock_worker","worker_index":23,
		"position":Vector3(220,.14,194),"route":[Vector3(220,0,194),Vector3(220,0,197),Vector3(220,0,199.8),Vector3(221.2,0,197)]})
	porter.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(porter)
	for body in world.find_children("*", "CharacterBody3D", true, false):
		if body.is_queued_for_deletion(): continue
		if body is VISITOR and body.fishing:
			fishers.append(body)
		elif body is WORKER and not body.route.is_empty() and not body.dead:
			var route: Array = body.route.duplicate()
			if body.name == "south_port_worker_07":
				# His long gameplay circuit meets the raised passenger platform.
				# Keep this take in the level corridor beneath the footbridge.
				# Pillars are at x=221.65/224.35; keep the full capsule clear.
				route = [Vector3(222.3,0,182),Vector3(222.3,0,174),Vector3(222.3,0,166),Vector3(222.3,0,174)]
			elif body.name == "south_port_worker_14":
				# The live route continues onto streamed ship support. For this
				# fixed take, work on the resident quay beside the same gantry.
				route = [Vector3(265.625,0,204.375),Vector3(267.625,0,204.375),Vector3(267.625,0,205.875),Vector3(265.625,0,205.875)]
			workers.append({"actor":body, "route":route, "height":body.global_position.y,
				"phase":float(workers.size())*3.7, "previous":Vector3.INF})
		if body.get("model") is CIVILIAN:
			body.model.lod_enabled = false
	var terminal = world.session.urban_operations.passenger_terminal
	for i in 2:
		var boat := _moving_boat(terminal,i)
		boats.append({"node":boat, "position":boat.position, "rotation":boat.rotation})
	# Reuse the production gantries, container, trolley and hoist cable. The
	# captured take owns their poses; no truck manager can freeze them at 3.9 s.
	for i in cargo.cranes.size():
		var crane: Dictionary = cargo.cranes[i]
		if crane.visual.get_parent() != cargo: crane.visual.reparent(cargo, true)
		cargo.work_trucks[i].loaded = false
		cargo.work_trucks[i].phase = "cinematic"
		crane.visual.show()
		crane.trolley.show()
		crane.cable.show()

func _moving_boat(terminal, index: int) -> Node3D:
	# Gameplay batches the moored boats with the quay. Rebuild just this native
	# boat and remove its exact box instances from the batch, so seats, motor and
	# hull rock together instead of leaving the fittings suspended in midair.
	var original := terminal.get_node("FishingBoat%d"%index) as Node3D
	var boat := ART.new()
	boat.name = "FilmFishingBoat%d"%index
	terminal.add_child(boat)
	boat.transform = original.transform
	boat.boat(false,index)
	var consolidated := terminal.get_node("BatchedWaterfrontDetails") as Node3D
	for part in boat.get_children():
		if not part is MultiMeshInstance3D: continue
		var batch := consolidated.get_node_or_null(NodePath(part.name)) as MultiMeshInstance3D
		assert(batch != null,"Native boat finish missing from waterfront batch")
		var inverse: Transform3D = batch.global_transform.affine_inverse()*part.global_transform
		for i in part.multimesh.instance_count:
			var expected: Transform3D = inverse*part.multimesh.get_instance_transform(i)
			var found := false
			for j in batch.multimesh.instance_count:
				if batch.multimesh.get_instance_transform(j).is_equal_approx(expected):
					batch.multimesh.set_instance_transform(j,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
					found = true
					break
			assert(found,"Boat fitting must move, never be duplicated")
	original.hide()
	return boat

func owns(body: Node) -> bool:
	return fishers.has(body) or workers.any(func(record): return record.actor == body)

func sample(t: float, delta: float) -> void:
	for record in workers: _worker(record, t, delta)
	for i in fishers.size():
		var actor = fishers[i]
		actor.fishing_clock = fposmod(t+float(i)*11.0, 26.0)
		actor._tick_mountain_routine(0.0)
		actor.model.activity = "fish"
		actor.model.clock = t
		actor.model._speed = 0.0
		actor.model._travel = 0.0
		actor.model._pose(delta)
	for i in boats.size():
		var record: Dictionary = boats[i]
		record.node.position = record.position+Vector3.UP*.035*sin(t*.85+float(i)*1.7)
		record.node.rotation = record.rotation+Vector3(.008*sin(t*.72+float(i)),0,.012*sin(t*.91+float(i)*2.0))
	for i in cargo.cranes.size():
		cargo.cranes[i].clock = t+8.0+float(i)*16.0
		cargo._sync_crane(i)

static func worker_pose(route: Array, time: float) -> Dictionary:
	# Pick up at station 0, carry to station 2, put down, return empty. Dwell
	# and eased starts/stops keep bodies and hand-held loads continuous at cuts.
	const SPEED := 1.3
	const DWELL := 1.8
	var duration := DWELL*2.0
	for i in route.size(): duration += route[i].distance_to(route[(i+1)%route.size()])/SPEED+.4
	var clock := fposmod(time, duration)
	for i in route.size():
		var next: Vector3 = route[(i+1)%route.size()]
		var point: Vector3 = route[i]
		var direction := (next-point).normalized()
		if i == 0 or i == 2:
			if clock < DWELL:
				return {"position":point,"direction":direction,"speed":0.0,
					"carrying":clock>=DWELL*.5 if i==0 else clock<DWELL*.5,
					"bend":sin(clock/DWELL*PI)*.22}
			clock -= DWELL
		var distance := point.distance_to(next)
		var seconds := distance/SPEED+.4
		if clock < seconds:
			# Integral of a trapezoid velocity profile, with .4 s ramps.
			var travelled := SPEED*(clock*clock/.8 if clock<.4 else
				(seconds-.4-pow(seconds-clock,2)/.8 if clock>seconds-.4 else clock-.2))
			var speed := SPEED*minf(1.0,minf(clock,seconds-clock)/.4)
			return {"position":point+direction*travelled,"direction":direction,"speed":speed,
				"carrying":i<2,"bend":0.0}
		clock -= seconds
	return {"position":route[0],"direction":Vector3.FORWARD,"speed":0.0,"carrying":false,"bend":0.0}

func _worker(record: Dictionary, t: float, delta: float) -> void:
	var actor = record.actor
	var pose := worker_pose(record.route,t+float(record.phase))
	actor.global_position = pose.position+Vector3.UP*float(record.height)
	actor.model.rotation.y = lerp_angle(actor.model.rotation.y,atan2(pose.direction.x,pose.direction.z),1.0-exp(-10.0*delta))
	actor.carrying = pose.carrying
	actor.activity = "carry" if pose.carrying else "return"
	actor.velocity = pose.direction*float(pose.speed)
	actor._sync_model(float(pose.speed)>.01)
	var model = actor.model
	model.clock = t+float(record.phase)
	model._speed = pose.speed
	model._travel = 0.0 if record.previous == Vector3.INF else minf(.15,actor.global_position.distance_to(record.previous))
	model._pose(delta)
	model.spine.rotation.x += float(pose.bend)
	record.previous = actor.global_position
