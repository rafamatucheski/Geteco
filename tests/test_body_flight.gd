extends SceneTree
const FLIGHT := preload("res://gameplay/street_physics/BodyFlight3D.gd")
const ACTOR := preload("res://scripts/Actor.gd")
class Stage extends Node3D:
	var gameplay: Node
class Street extends "res://gameplay/street_physics/StreetPhysics.gd":
	var landings := 0
	func _ready() -> void:
		blood = BLOOD.new()
		add_child(blood)
		set_physics_process(false)
	func on_body_landed(actor: CharacterBody3D, lethal: bool, source: Node, speed: float, heading: Vector3) -> void:
		landings += 1
		super.on_body_landed(actor,lethal,source,speed,heading)
var world: Stage
var street: Street
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func box(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = size
	shape.shape = hull
	body.add_child(shape)
	world.add_child(body)
	body.position = point
	return body
func person(point := Vector3.ZERO) -> CharacterBody3D:
	var body := ACTOR.new()
	body.controlled_automatically = true
	world.add_child(body)
	body.teleport(point)
	return body
func run() -> void:
	world = Stage.new()
	root.add_child(world)
	box(Vector3(0,-.1,0),Vector3(60,.2,60))
	street = Street.new()
	world.add_child(street)
	for tick in 3: await physics_frame
	for speed in [8.0,24.0]:
		var body = person(Vector3(0,.04,0))
		var source := Node3D.new()
		world.add_child(source)
		var before := street.landings
		var flight = FLIGHT.launch(body,Vector3(0,0,-speed),speed>12.5,street,source)
		check(flight != null and not body.is_physics_processing(),"flight owns locomotion")
		check(FLIGHT.launch(body,Vector3.RIGHT*speed,false,street,source)==null,"duplicate impact cannot replace active owner")
		var model: Node3D = body.visual.get_child(0)
		check(not model.is_processing(),"walk cycle yields articulated limbs to impact")
		var last: Basis = body.visual.basis
		var biggest_turn := 0.0
		var lowest := INF
		for tick in 240:
			await physics_frame
			biggest_turn = maxf(biggest_turn,last.get_rotation_quaternion().angle_to(body.visual.basis.get_rotation_quaternion()))
			last = body.visual.basis
			lowest = minf(lowest,body.position.y)
			if not body.has_meta("street_flying"): break
		check(not body.has_meta("street_flying") and street.landings==before+1,"flight lands and applies damage once")
		check(lowest > -.08,"swept body stays above floor")
		check(biggest_turn < .35,"pose remains continuous across flight and landing: %s"%biggest_turn)
		check(absf(body.visual.basis.y.normalized().y)<.2,"landing retains prone pose without standing reset")
		check(body.dead == (speed>12.5),"original lethal speed contract preserved")
		if not body.dead:
			check(body.health<60 and body.has_meta("street_down"),"survivor waits for help")
			var resting: Transform3D = model.thighs[0].transform
			for tick in 12: await physics_frame
			check(model.thighs[0].transform.is_equal_approx(resting),"injured body does not keep walking on ground")
			body.recover_from_injury()
			for tick in 100:
				await physics_frame
				if not body.has_meta("street_down"): break
			check(not body.has_meta("street_down") and body.is_physics_processing() and model.is_processing(),"help restores locomotion and visual owner")
			check(body.collision_layer==2 and body.collision_mask==7,"help restores walking collisions")
			check(body.visual.transform.is_equal_approx(Transform3D.IDENTITY),"help restores upright body")
		source.queue_free()
		body.queue_free()
		await process_frame
	var wall := box(Vector3(0,1,-3),Vector3(5,2,.15))
	var body = person(Vector3(0,.04,0))
	await physics_frame
	var flight = FLIGHT.launch(body,Vector3(0,0,-30),false,street,null)
	for tick in 180: await physics_frame
	check(body.position.z > -2.1,"whole prone body stops before a thin wall")
	check(not body.has_meta("street_flying"),"wall collision still reaches ground and settles")
	if is_instance_valid(flight):
		flight.down_time = FLIGHT.SELF_RECOVERY_SECONDS
		for tick in 100: await physics_frame
	check(not body.has_meta("street_down"),"abandoned survivor can recover without ambulance")
	wall.queue_free()
	body.queue_free()
	await process_frame
	body = person()
	body.set_meta("invulnerable",true)
	check(FLIGHT.launch(body,Vector3.RIGHT*25,true,street,null)==null and body.health==100,"protected actor remains untouched")
	body.remove_meta("invulnerable")
	check(FLIGHT.launch(body,Vector3(NAN,0,0),false,street,null)==null,"invalid momentum rejected")
	flight = FLIGHT.launch(body,Vector3.RIGHT*12,false,street,null)
	await physics_frame
	paused = true
	var frozen: Vector3 = body.position
	for tick in 5: await process_frame
	check(body.position==frozen,"pause freezes the impact body")
	paused = false
	flight.free()
	check(body.collision_mask==7 and body.is_physics_processing() and not body.has_meta("street_down"),"cancelling owner restores actor state")
	body.queue_free()
	await process_frame
	body = person()
	flight = FLIGHT.launch(body,Vector3(0,0,-20),false,street,null)
	for tick in 3: await physics_frame
	body.receive_damage(1000)
	for tick in 180:
		await physics_frame
		if not is_instance_valid(flight): break
	check(body.dead and not is_instance_valid(flight) and body.position.y > -.08,"death in flight still collides with floor and releases owner")
	body.queue_free()
	await process_frame
	body = person()
	flight = FLIGHT.launch(body,Vector3(0,0,-8),false,street,null)
	for tick in 180:
		await physics_frame
		if not body.has_meta("street_flying"): break
	body.recover_from_injury()
	for tick in 10: await physics_frame
	body.receive_damage(1000)
	for tick in 10: await physics_frame
	check(body.dead and not is_instance_valid(flight) and not body.is_physics_processing(),"death while rising cancels recovery and releases owner")
	world.free()
	await process_frame
	print("BODY_FLIGHT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
