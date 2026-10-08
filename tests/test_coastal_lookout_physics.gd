extends SceneTree
## Real Actor capsule walking the authored ramp, reverse route, railing and
## vehicle-width sweeps. Dedicated fixture; integrated streaming/render review
## remains the responsibility of the Main session test.
const LOOKOUT := preload("res://world/places/coastal_lookout/CoastalLookout.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var actor: CharacterBody3D
var scene: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("LOOKOUT_PHYSICS ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func walk(point: Vector3, seconds := 10.0) -> bool:
	var until := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<until:
		var offset := point-actor.global_position
		offset.y = 0
		if offset.length()<.19: break
		actor.automatic_direction = offset.normalized()
		await physics_frame
	actor.automatic_direction = Vector3.ZERO
	var distance := actor.global_position.distance_to(point)
	if distance>.45:
		print("LOOKOUT_BLOCKED target=",point," actual=",actor.global_position)
		for i in actor.get_slide_collision_count():
			var hit := actor.get_slide_collision(i)
			print("LOOKOUT_CONTACT ",hit.get_collider().get_path()," ",hit.get_position()," normal=",hit.get_normal())
	return distance<.45

func run() -> void:
	create_timer(160).timeout.connect(func(): push_error("Lookout physics timeout"); quit(3))
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var lookout := LOOKOUT.new()
	scene.add_child(lookout)
	# Existing street's flat landing ends at the ramp; no support is supplied to
	# the climb or sea, so a missing ramp collision cannot pass this test.
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7,.3,4)
	shape.shape = box
	ground.add_child(shape)
	ground.position = LOOKOUT.ENTRANCE+Vector3(0,-.15,1.5)
	scene.add_child(ground)
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	actor.speed = 5.0
	actor.position = LOOKOUT.ENTRANCE+Vector3(.68,.1,.8)
	scene.add_child(actor)
	for frame in 6: await physics_frame
	check(await walk(LOOKOUT.ENTRANCE+Vector3(.68,.33,-2.7)),"Dante walks through bollards without jumping")
	var route := LOOKOUT.route_points()
	var climbed := true
	for i in range(1,route.size()):
		if not await walk(route[i]): climbed=false; break
	check(climbed,"real Actor walks every ramp curve to the upper platform")
	if not climbed: finish(); return
	check(await walk(LOOKOUT.summit_position()),"walkway joins the terrace without a rail across its opening")
	check(await walk(LOOKOUT.binocular_interaction_position()),"binocular position has floor and capsule clearance")
	check(absf(actor.global_position.y-LOOKOUT.SUMMIT.y)<.18,"Dante stands on terrace at authored altitude")
	check(await walk(LOOKOUT.SUMMIT),"returns from binocular to plaza centre")
	actor.automatic_direction = Vector3.FORWARD
	await create_timer(2.6).timeout
	actor.automatic_direction = Vector3.ZERO
	var gallery_center := Vector3(303,LOOKOUT.summit_position().y,-198)
	var gallery_delta := actor.global_position-gallery_center
	check(Vector2(gallery_delta.x,gallery_delta.z).length()<6.5 and absf(actor.global_position.y-gallery_center.y)<.18,"gallery railing physically stops player at lighthouse height")
	check(await walk(LOOKOUT.SUMMIT),"player recovers normally after touching guard")
	check(await walk(route[-1]),"terrace opening accessible for descent")
	var descended := true
	for i in range(route.size()-2,0,-1):
		if not await walk(route[i]): descended=false; break
	check(descended,"real Actor walks the reverse route without falls or stuck corners")
	if descended:
		check(await walk(LOOKOUT.ENTRANCE+Vector3(.68,.33,-2.7)),"descent reaches pedestrian threshold")
		check(await walk(LOOKOUT.ENTRANCE+Vector3(.68,.03,.7)),"Dante leaves through bollards preserving access")
	var hull := BoxShape3D.new()
	hull.size = Vector3(1.8,1.3,3.8)
	for x in [-.55,0.0,.55]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.collision_mask = 1
		query.transform = Transform3D(Basis.IDENTITY,LOOKOUT.ENTRANCE+Vector3(x,.85,2.1))
		query.motion = Vector3(0,0,-4)
		query.exclude = [actor.get_rid()]
		var result := scene.get_world_3d().direct_space_state.cast_motion(query)
		check(result[0]<.75,"car hull blocked at entrance offset "+str(x))
	finish()

func finish() -> void:
	print("LOOKOUT_PHYSICS_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
