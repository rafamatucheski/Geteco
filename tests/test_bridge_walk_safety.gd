extends SceneTree
const SAFETY := preload("res://world/regions/unified_bridge/BridgeWalkSafety.gd")
const KIT := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var connection := CONNECTION.new()
	world.add_child(connection)
	for frame in 4: await physics_frame
	var slots := SAFETY.population_slots()
	check(slots.size()>30,"Bridge has sidewalk population slots along both banks")
	for slot in slots:
		var direction: Vector3 = slot.a.direction_to(slot.b)
		var right := direction.cross(Vector3.UP)
		for t in [0.0,.25,.5,.75,1.0]:
			for offset in [-.72,.72]:
				var p: Vector3 = slot.a.lerp(slot.b,t)+right*offset
				check(not Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),KIT.east_asphalt_footprint()),"Walking capsule stays outside asphalt: "+str(p))
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=.32
	capsule.height=1.7
	shape.shape=capsule
	shape.position.y=.85
	body.add_child(shape)
	body.collision_mask=1
	world.add_child(body)
	var rows := KIT.east_sections()
	for i in range(rows.size()-1):
		var first: Dictionary = rows[i]
		var next: Dictionary = rows[i+1]
		var row: Dictionary = first.duplicate()
		row.point=(first.point+next.point)*.5
		row.side=(first.side+next.side).normalized()
		row.road=(first.road+next.road)*.5
		if row.point.x>560 or row.point.z>-140: continue
		for side in [-1.0,1.0]:
			if not SAFETY.protected_segment(first,next,side): continue
			body.position=SAFETY.walk_point(row,side)+Vector3.UP*.09
			check(body.test_move(body.global_transform,-row.side*side*2.0),"Solid inner rail stops pedestrian entering traffic: "+str(body.position))
	# O entroncamento norte precisa continuar atravessável antes de concluir a campanha.
	var mouth := KIT.east_mouth_limits()
	var query := PhysicsRayQueryParameters3D.create(Vector3(360,.8,(mouth.x+mouth.y)*.5),Vector3(377,.8,(mouth.x+mouth.y)*.5),1)
	check(world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"North branch mouth stays open")
	check(connection.bridge_lamps.size()>20,"Curve and trunk have real light sources")
	connection.set_night_lights(1.0)
	for light in connection.bridge_lamps:
		check(light.light_energy>0.0,"Night sources light the roadway")
	connection.set_night_lights(0.0)
	for light in connection.bridge_lamps: check(is_zero_approx(light.light_energy),"Day cycle switches off bridge sources")
	var walkers: Array = []
	for slot in slots:
		if slot.point.x<377 or slot.point.x>400 or slot.point.z> -265: continue
		var actor = preload("res://scripts/Actor.gd").new()
		actor.identity=walkers.size()+70
		actor.position=slot.point+Vector3.UP*.12
		actor.route=PackedVector3Array([slot.a,slot.b])
		world.add_child(actor)
		walkers.append({"actor":actor,"start":actor.position})
		if walkers.size()==2: break
	check(walkers.size()==2,"Two real pedestrians walk the curve sidewalks")
	var invaded := false
	for frame in 600:
		await physics_frame
		for entry in walkers:
			var p: Vector3 = entry.actor.position
			if Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),KIT.east_asphalt_footprint()): invaded=true
	check(not invaded,"Pedestrians never enter asphalt during ten seconds of real movement")
	for entry in walkers: check(entry.actor.travelled>4.0,"Pedestrian circulates rather than remaining blocked")
	print("BRIDGE_WALK_SAFETY checks=",checks," failures=",failures.size())
	world.free()
	quit(0 if failures.is_empty() else 1)
