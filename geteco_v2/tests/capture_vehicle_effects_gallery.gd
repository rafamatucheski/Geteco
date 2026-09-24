extends SceneTree
## Rendered presentation review for dirt slope, exhaust, damage smoke and impact.

const VEHICLE := preload("res://scripts/Vehicle.gd")
var stage: Node3D
var camera: Camera3D
var car: CharacterBody3D

func _initialize() -> void:
	call_deferred("run")

func surface(label: String, point: Vector3, size: Vector3, color: Color, tilt := 0.0) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name=label
	var box := BoxMesh.new()
	box.size=size
	mesh.mesh=box
	mesh.position=point
	mesh.rotation.z=tilt
	var material := StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=.9
	mesh.material_override=material
	stage.add_child(mesh)
	var body := StaticBody3D.new()
	body.collision_layer=1
	body.collision_mask=0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	collision.shape=shape
	body.add_child(collision)
	mesh.add_child(body)

func focus(point: Vector3, size := 10.0) -> void:
	camera.global_position=point+Vector3(7,10,9)
	camera.look_at(point+Vector3.UP*.4,Vector3.UP)
	camera.size=size
	await create_timer(.25).timeout

func capture(label: String) -> bool:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image().save_png("res://evidence/"+label+".png")==OK

func tick_effects(frames: int, motion: Vector3, move := Vector3.ZERO) -> void:
	for frame in frames:
		car.health=maxf(car.health,1)
		car.horizontal_velocity=motion
		car.global_position+=move
		car.effects.physics_tick(1.0/60.0,motion)
		await physics_frame

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	stage=Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("8198a0")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("c9d4d7")
	environment.environment.ambient_light_energy=.75
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-55,-28,0)
	sun.light_energy=1.45
	sun.shadow_enabled=true
	stage.add_child(sun)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.current=true
	stage.add_child(camera)
	surface("Road",Vector3(-7,-.1,0),Vector3(10,.2,16),Color("343d42"))
	surface("Land",Vector3(6,-.1,0),Vector3(10,.2,16),Color("4e402e"),.18)
	car=VEHICLE.new()
	car.archetype="sport_coupe"
	car.paint_color=Color("d5a544")
	stage.add_child(car)
	await physics_frame
	car.set_physics_process(false)
	car.controlled=true
	car.external_input=true
	car.brake_input=true
	car.place(Vector3(6,.18,2.4),0)
	await focus(Vector3(6,.2,.2),10)
	await tick_effects(70,Vector3(5,0,-6),Vector3(0,0,-.055))
	var dirt_ok := await capture("vehicle-effects-dirt-incline")
	car.effects.clear_all()
	car.place(Vector3(-7,.12,0),0)
	car.health=car.max_health
	car.brake_input=false
	car.throttle_input=.35
	car.speed=4
	await focus(Vector3(-7,.2,0),8)
	await tick_effects(42,-car.global_basis.z*4)
	var exhaust_ok := await capture("vehicle-effects-exhaust-normal")
	car.health=car.max_health*.35
	await tick_effects(58,Vector3.ZERO)
	var damage_ok := await capture("vehicle-effects-damage-smoke")
	car.effects.clear_all()
	car.health=car.max_health
	car.effects.impact_effects.present_impact(car.to_global(Vector3(0,.65,-car.half_length)),car.global_basis.z,10,991)
	await physics_frame
	var impact_ok := await capture("vehicle-effects-impact")
	print("VEHICLE_EFFECT_GALLERY dirt=",dirt_ok," exhaust=",exhaust_ok," damage=",damage_ok," impact=",impact_ok)
	car.effects.clear_all()
	await create_timer(.65).timeout
	stage.free()
	await process_frame
	await process_frame
	quit(0 if dirt_ok and exhaust_ok and damage_ok and impact_ok else 1)
