extends SceneTree
## Directed native-3D contracts for surface contact, budgets, cooldown and cleanup.

const VEHICLE := preload("res://scripts/Vehicle.gd")
const SURFACE := preload("res://gameplay/vehicle_effects/VehicleSurfaceProbe.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func surface(parent: Node3D, label: String, point: Vector3, size: Vector3, tilt := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	mesh.rotation.z = tilt
	parent.add_child(mesh)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	mesh.add_child(body)
	return mesh

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	surface(world,"Road",Vector3(0,-.10,0),Vector3(10,.20,16))
	surface(world,"Land",Vector3(14,-.10,0),Vector3(9,.20,12),.18)
	surface(world,"Meadow",Vector3(0,-.10,20),Vector3(10,.20,10))
	surface(world,"CrashWall",Vector3(0,1,-3),Vector3(6,2,.3))
	var car := VEHICLE.new()
	car.archetype = "sport_coupe"
	world.add_child(car)
	car.place(Vector3(0,.12,0),0)
	await frames(3)
	car.set_physics_process(false)
	var initial_particles := car.find_children("*","GPUParticles3D",true,false)
	print("VEHICLE_EFFECTS initial_particles=",initial_particles.map(func(node: Node): return node.name))
	check(is_instance_valid(car.effects) and car.effects.get_child_count()==3,"vehicle owns the three isolated effect modules")
	check(car.wheels.size()==4,"effects consume four authored wheel centers")
	check(car.tail_material!=null,"existing rear/brake emissive material remains connected")
	car.controlled = true
	car.external_input = true
	car.speed = 0
	car.throttle_input = -1
	car.brake_input = false
	car._drive_player(1.0)
	check(car.speed<0 and absf(car.speed)<=car.REVERSE_SPEED,"existing reverse movement remains connected and speed-limited")
	car.speed = 6
	car.throttle_input = 0
	car.brake_input = true
	car._drive_player(.1)
	check(car.speed<6,"existing service/hand brake still decelerates the vehicle")
	var rear: Node3D
	for wheel in car.wheels:
		if not bool(wheel.get_meta("front",false)): rear=wheel; break
	var road_contact := SURFACE.sample(car,rear.global_position)
	check(not road_contact.is_empty() and road_contact.kind=="hard","real rear wheel ray identifies asphalt contact")
	check(road_contact.normal.dot(Vector3.UP)>.99 and absf(road_contact.point.y)<.01,"asphalt contact preserves real height and normal")
	var slope_contact := SURFACE.sample(car,Vector3(14,.65,0))
	check(not slope_contact.is_empty() and slope_contact.kind=="dirt","terrain ray identifies dirt independently from asphalt")
	check(slope_contact.normal.dot(Vector3.UP)>.9 and slope_contact.normal.dot(Vector3.UP)<.995,"inclined contact returns its tilted physical normal")
	check(SURFACE.sample(car,Vector3(30,4,0)).is_empty(),"no effect contact exists without ground below the wheel")

	var tire = car.effects.tire_effects
	car.brake_input = true
	car.horizontal_velocity = Vector3(6,0,-8)
	tire.physics_tick(.06,true)
	car.position.z -= .28
	tire.physics_tick(.06,true)
	check(tire.emitters.size()==2 and tire.emitters[0].emitting and tire.emitters[1].emitting,"hard braking and lateral slip emit from both rear contacts")
	check(tire.last_modes==["smoke","smoke"],"dry asphalt uses tire smoke rather than dust or water")
	check(not tire.marks.is_empty() and tire.marks[0].na.dot(Vector3.UP)>.99,"skid marks store the sampled surface normal")
	car.place(Vector3(14,.35,0),0)
	car.horizontal_velocity = Vector3(4,0,0)
	tire.physics_tick(.06,true)
	car.position.z-=.24
	tire.physics_tick(.06,true)
	check("dirt" in tire.last_modes,"moving wheel contact on terrain selects bounded dust")
	check(tire.marks.any(func(mark: Dictionary): return mark.kind=="dirt" and mark.na.dot(Vector3.UP)<.995),"terrain marks inherit the real inclined surface normal")
	var grass_contact := SURFACE.sample(car,Vector3(0,.65,20))
	check(not grass_contact.is_empty() and grass_contact.kind=="grass","meadow ray identifies grass")
	tire.clear_all()
	car.brake_input = false
	car.place(Vector3(0,.12,20),0)
	car.horizontal_velocity = Vector3(0,0,-6)
	tire.physics_tick(.06,true)
	car.position.z-=.36
	tire.physics_tick(.06,true)
	check("grass" in tire.last_modes,"rolling straight on grass throws turf")
	check((tire.emitters[0].process_material as ParticleProcessMaterial).gravity.y<0,"turf falls back instead of floating like dust")
	check(tire.marks.any(func(mark: Dictionary): return mark.kind=="grass" and int(mark.life)==tire.RUT_LIFETIME_MSEC),"straight driving on grass leaves a lasting rut without sliding")
	var light_width: float = tire.marks.back().w
	car.handling.mass = 6.0
	tire.clear_all()
	tire.physics_tick(.06,true)
	car.position.z-=.36
	tire.physics_tick(.06,true)
	check(not tire.marks.is_empty() and float(tire.marks.back().w)>light_width,"heavier vehicle cuts a wider rut")
	car.brake_input = true
	var wet := slope_contact.duplicate()
	wet.wet = true
	tire._emit_surface(0,wet,"water",8,4)
	check((tire.emitters[0].process_material as ParticleProcessMaterial).color.is_equal_approx(Color(.75,.86,1,.62)),"wet contact selects the V1-blue water spray")
	for index in 100:
		var a := Vector3(index*.10,0,0)
		tire._append_mark(0,{"point":a,"normal":Vector3.UP,"kind":"hard","wet":false},"hard")
	check(tire.marks.size()<=tire.MAX_MARK_SEGMENTS,"skid mark ring never exceeds its fixed segment budget")

	var impact = car.effects.impact_effects
	check(not impact.present_impact(Vector3.ZERO,Vector3.RIGHT,1,77,1000),"sub-threshold contact does not produce collision particles")
	check(impact.present_impact(Vector3.ZERO,Vector3.RIGHT,8,77,1000),"first rigid impact produces a point burst")
	check(not impact.present_impact(Vector3.ZERO,Vector3.RIGHT,8,77,1100),"continuous contact is suppressed inside its cooldown")
	check(impact.present_impact(Vector3.ZERO,Vector3.RIGHT,8,77,1700) and impact.burst_count==2,"same collider can produce a later distinct impact")
	check(impact.emitter.amount==14 and impact.emitter.one_shot,"impact budget is one reusable fourteen-particle emitter")
	impact.last_by_collider.clear()
	impact.last_global_msec = -999999
	impact.burst_count = 0
	car.place(Vector3(0,.12,0),0)
	car.health = car.max_health
	car.controlled = true
	car.external_input = true
	car.brake_input = false
	car.throttle_input = 1
	car.speed = 12
	car.horizontal_velocity = -car.global_basis.z*12
	car.set_physics_process(true)
	await frames(20)
	car.set_physics_process(false)
	check(impact.burst_count==1,"real CharacterBody collision emits once instead of repeating through residual contact")
	check(impact.emitter.global_position.z<-.75,"collision burst stays at the physical wall contact rather than vehicle origin")

	var power = car.effects.powertrain_effects
	car.place(Vector3(0,.12,0),0)
	car.health = car.max_health
	car.throttle_input = .35
	power.physics_tick(true)
	check(power.exhaust.emitting and power.damage_smoke==null,"healthy running engine has only subtle rear exhaust")
	car.health = car.max_health*.40
	power.physics_tick(true)
	check(power.damage_smoke.emitting,"damage below half integrity starts separate hood smoke")
	check(power.damage_smoke.global_position.z < car.global_position.z and power.exhaust.global_position.z > car.global_position.z,"damage smoke and normal exhaust use distinct real mounts")
	power._emit_backfire()
	check(power.backfire.one_shot and power.backfire.amount==12,"V1 throttle-release backfire reuses one bounded emitter")
	var dmg_proc := power.damage_smoke.process_material as ParticleProcessMaterial
	check(dmg_proc.angular_velocity_min < 0 and dmg_proc.angular_velocity_max > 0,"damage smoke has rotational vortex dynamics")
	check(dmg_proc.scale_min < 0.35 and dmg_proc.scale_max >= 0.9,"damage smoke combines smaller breakout wisps with dense billows")
	
	# Test idle exhaust micro-wisps vs throttle punch
	car.speed = 0.0
	car.throttle_input = 0.0
	power.previous_throttle = 0.0
	power.physics_tick(true)
	var exh_proc := power.exhaust.process_material as ParticleProcessMaterial
	check(exh_proc.scale_min <= 0.28 and exh_proc.scale_max <= 0.65,"idle engine generates smaller subtle micro-wisps")
	car.throttle_input = 0.9
	power.physics_tick(true)
	check(exh_proc.scale_max >= 1.0 and power.exhaust.amount_ratio >= 0.5,"throttle punch produces denser expanded puff")
	var particle_nodes := car.find_children("*","GPUParticles3D",true,false).size()
	for frame in 120:
		car.effects.physics_tick(1.0/60.0,Vector3.ZERO)
	check(car.find_children("*","GPUParticles3D",true,false).size()==particle_nodes,"steady updates create no particle nodes per frame")
	car.effects.presentation_enabled = false
	car.effects.physics_tick(.3,Vector3.ZERO)
	check(not power.exhaust.emitting and not power.damage_smoke.emitting and not tire.emitters[0].emitting,"distance/visibility suspension stops every continuous emitter")

	var emitter_ref: WeakRef = weakref(tire.emitters[0])
	car.queue_free()
	await process_frame
	await process_frame
	check(emitter_ref.get_ref()==null,"removing the vehicle releases its effect nodes")
	world.queue_free()
	await process_frame
	print("VEHICLE_EFFECTS checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
