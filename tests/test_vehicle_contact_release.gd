extends "res://tests/tank_control/test_heavy_impacts.gd"
## Native contacts: bumper-start acceleration, nested authored NPCs and swept props.
class AuthoredContact extends CharacterBody3D:
	# Deliberately no health/damage API: this is the noncombat actor contract.
	var model: Node3D
	func _ready() -> void:
		collision_layer=2
		collision_mask=7
		var capsule := CapsuleShape3D.new()
		capsule.radius=.30
		capsule.height=1.72
		var shape := CollisionShape3D.new()
		shape.shape=capsule
		shape.position.y=.86
		add_child(shape)
		model=preload("res://assets/CivilianModel.gd").new()
		add_child(model)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	street = Street.new()
	world.add_child(street)
	solid(Vector3(100,.2,100),Vector3(0,-.1,0))
	for backward in [false,true]:
		var vehicle := car(1.0)
		vehicle.controlled=true
		var person := Person.new()
		world.add_child(person)
		person.position=Vector3(0,.002,2.27 if backward else -2.27)
		street._people_cache=[] # nested actors can be missing from the periodic cache
		await physics_frame
		var start := person.position
		CRUSH.set_planar(vehicle,Vector3.BACK*.15 if backward else Vector3.FORWARD*.15)
		step(vehicle)
		# Encostão (30/10): arrancada lenta empurra, não lança nem sangra.
		check(not person.has_meta("street_flying") and not person.has_meta("street_down"),"slow bumper contact nudges instead of launching %s" % backward)
		check(not vehicle.get_collision_exceptions().has(person),"nudged person stays solid for the car %s" % backward)
		check(person.position.distance_to(start) > .002 and is_equal_approx(person.health,100.0),"nudge moves the person without damage %s" % backward)
		person.free()
		vehicle.free()
	# Carro insistindo devagar: a pessoa sai pelo lado e continua de pé.
	var walker := Person.new()
	world.add_child(walker)
	walker.position=Vector3(.3,.002,-2.29)
	var pusher := car(1.0)
	pusher.controlled=true
	street._people_cache=[walker]
	await physics_frame
	for frame in 150:
		CRUSH.set_planar(pusher,Vector3.FORWARD*1.0)
		step(pusher)
		await physics_frame
	check(not walker.has_meta("street_down") and walker.health == 100.0,"slow push lets the person step aside unharmed")
	check(absf(walker.position.x) > pusher.half_width,"person ends beside the car, not in front: x=%.2f" % walker.position.x)
	check(street.nudges > 0 and street.nudge_falls == 0,"nudge reaction counted without falls")
	walker.free()
	pusher.free()
	# Presa contra a parede: a pressão derruba e o carro passa por cima, sem poça de atropelamento.
	var pinned := Person.new()
	world.add_child(pinned)
	pinned.position=Vector3(0,.002,-2.29)
	var wall_ahead := solid(Vector3(8,2,.4),Vector3(0,1,-2.85))
	pusher = car(1.0)
	pusher.controlled=true
	street._people_cache=[pinned]
	await physics_frame
	var fell := false
	for frame in 90:
		CRUSH.set_planar(pusher,Vector3.FORWARD*1.0)
		step(pusher)
		await physics_frame
		if pinned.has_meta("street_down"):
			fell = true
			break
	check(fell and street.nudge_falls == 1,"pinned person goes down under sustained slow push")
	check(pinned.collision_layer == 0,"downed person no longer blocks the car")
	pinned.free()
	pusher.free()
	wall_ahead.free()
	await physics_frame
	# Acima do teto do encostão segue o atropelamento de antes.
	var struck := Person.new()
	world.add_child(struck)
	struck.position=Vector3(0,.002,-2.27)
	var fast := car(1.0)
	fast.controlled=true
	street._people_cache=[]
	await physics_frame
	CRUSH.set_planar(fast,Vector3.FORWARD*6.0)
	step(fast)
	check(struck.has_meta("street_flying"),"fast contact still launches the person: flying=%s down=%s pos=%s" % [struck.has_meta("street_flying"),struck.has_meta("street_down"),struck.position])
	struck.free()
	fast.free()
	var contact := AuthoredContact.new()
	world.add_child(contact)
	contact.position=Vector3(0,.002,-2.27)
	contact.set_physics_process(false)
	var vehicle := car(1.0)
	vehicle.controlled=true
	await physics_frame
	CRUSH.set_planar(vehicle,Vector3.FORWARD*6.0)
	step(vehicle)
	check(contact.has_meta("street_flying"),"authored contact without health gets physical response")
	for frame in 100: await physics_frame
	check(not contact.has_meta("street_flying") and contact.has_meta("street_down"),"authored contact lands physically")
	var flight := contact.get_node_or_null("BodyFlight3D")
	if flight != null:
		flight.down_time=8.0
		# O lançamento a 6 m/s cai em ragdoll e levanta com o mocap, mais longo que o tween antigo.
		for frame in 300:
			await physics_frame
			if not contact.has_meta("street_down"): break
	check(not contact.has_meta("street_down") and contact.collision_layer==2,"authored contact recovers collision and pose")
	contact.free()
	vehicle.free()
	for kind in ["lamp","bench_seat","desert_rock","desert_tree"]:
		vehicle=car(1.0)
		var prop := Node3D.new()
		world.add_child(prop)
		prop.position=Vector3(0,0,-5)
		var visual := MeshInstance3D.new()
		visual.mesh=BoxMesh.new()
		prop.add_child(visual)
		FRAGILE.register_node(kind,prop,world)
		var debris_before := street.find_children("*","RigidBody3D",true,false).size()
		CRUSH.set_planar(vehicle,Vector3.FORWARD*42)
		street._hit_props(vehicle,vehicle.horizontal_velocity,Vector3(0,0,-10))
		check(FRAGILE.query(prop.position,1).is_empty(),kind+": swept contact survives a long physics step")
		if kind != "lamp": check(street.find_children("*","RigidBody3D",true,false).size() - debris_before >= 2,kind+": fast impact produces separate physical fragments")
		prop.free()
		vehicle.free()
		FRAGILE.cells.clear()
	check(not street.swept_prop_contact(Vector3(6,0,-5),Vector3(0,0,-10),1,2),"objects beside the swept path stay standing")
	vehicle=car(1.0)
	var wall := solid(Vector3(5,2,.4),Vector3(0,1,-4))
	var behind := Node3D.new()
	world.add_child(behind)
	behind.position=Vector3(0,0,-9)
	FRAGILE.register_node("lamp",behind,world)
	await physics_frame # Admit the freshly constructed wall to the native broadphase.
	CRUSH.set_planar(vehicle,Vector3.FORWARD*42)
	street._hit_props(vehicle,vehicle.horizontal_velocity,Vector3(0,0,-12))
	check(FRAGILE.query(behind.position,1).size()==1,"wall blocks destruction of props behind it")
	street.shakes=0
	for frame in 8:
		await physics_frame
		step(vehicle)
	check(street.shakes==1,"high speed wall contact triggers one physical feedback event")
	wall.free()
	behind.free()
	vehicle.free()
	FRAGILE.cells.clear()
	var region := preload("res://world/desert/DesertRegion.gd").new()
	var chunk := Node3D.new()
	world.add_child(chunk)
	region._lamp(chunk,Vector3(0,0,-5))
	region._build_record(chunk,{"kind":"rest_bench","position":Vector3(10,0,-5)})
	preload("res://world/desert/DesertDryFlora.gd")._breakable_plant(chunk,Vector3(20,0,-5),Basis.IDENTITY,0,2.0)
	check(FRAGILE.query(Vector3(0,0,-5),1).size()==1,"real desert lamp is registered")
	check(FRAGILE.query(Vector3(10,0,-5),1).size()==1,"real desert bench is registered")
	check(FRAGILE.query(Vector3(20,0,-5),1).size()==1,"real cactus is registered")
	var lamp := region._lamps[0]
	var item: Dictionary=FRAGILE.query(Vector3(0,0,-5),1)[0]
	check(FRAGILE.hit(item,42,Vector3.FORWARD,street),"desert lamp breaks at highway speed")
	region.set_night_lights(1.0)
	check(not lamp.visible and lamp.light_energy==0,"destroyed lamp stays dark when night updates")
	region.free()
	chunk.free()
	FRAGILE.cells.clear()
	await test_people_and_props() # mass response and protected ancestors
	world.free()
	await process_frame
	print("VEHICLE_CONTACT_RELEASE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
