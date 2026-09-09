extends Node3D

const VEHICLE := preload("res://prototypes/living_cast/CoupeTestVehicle.gd")
var car: CharacterBody3D
var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var hud: Label
var night := true
var orbit_view := false

func _ready() -> void:
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("93a8c5")
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.shadow_enabled = true
	add_child(sun)
	set_night(true)
	solid(Vector3(0,-0.25,0),Vector3(70,0.5,100),Color("30383e"))
	# Physical asymmetric barrier lets the driver strike one headlamp first.
	solid(Vector3(0,0.7,-23),Vector3(5,1.4,0.6),Color("b5a984"))
	solid(Vector3(9,0.7,-12),Vector3(0.6,1.4,15),Color("b5a984"))
	for x in [-17.0,17.0]: solid(Vector3(x,0.6,-5),Vector3(0.5,1.2,65),Color("7b8588"))
	for z in range(-35,30,4):
		visual_box(Vector3(-4,0.009,z),Vector3(0.12,0.015,1.8),Color("d6c784"))
		visual_box(Vector3(4,0.009,z),Vector3(0.12,0.015,1.8),Color("d6c784"))
	for i in 8:
		solid(Vector3(-11,0.3,-28+i*7),Vector3(0.7,0.6,0.7),Color("ba7043"))
	car = VEHICLE.new()
	car.position = Vector3(1.8,0,8)
	add_child(car)
	camera = Camera3D.new()
	camera.fov = 55
	add_child(camera)
	camera.make_current()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(24,20)
	hud.add_theme_font_size_override("font_size",19)
	hud.add_theme_color_override("font_shadow_color",Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x",2)
	hud.add_theme_constant_override("shadow_offset_y",2)
	canvas.add_child(hud)

func visual_box(pos: Vector3, size_value: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_value
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	node.material_override = material
	node.position = pos
	add_child(node)
	return node

func solid(pos: Vector3, size_value: Vector3, color: Color) -> void:
	visual_box(pos,size_value,color)
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size_value
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func set_night(value: bool) -> void:
	night = value
	environment.background_color = Color("101924") if night else Color("7e929f")
	environment.ambient_light_energy = 0.25 if night else 0.8
	sun.light_energy = 0.12 if night else 1.2

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if event.physical_keycode == KEY_L:
		car.light_mode = (car.light_mode+1)%3
		car.update_lights()
	if event.physical_keycode == KEY_N: set_night(not night)
	if event.physical_keycode == KEY_C: orbit_view = not orbit_view
	if event.physical_keycode == KEY_R:
		car.reset_vehicle()
		car.position = Vector3(1.8,0,8)
		car.rotation = Vector3.ZERO

func _process(_delta: float) -> void:
	var offset := Vector3(7,5,-8) if orbit_view else Vector3(0,6,11)
	camera.position = car.position + car.basis * offset
	camera.look_at(car.position+Vector3(0,0.5,-1))
	hud.text = "COUPE / pista isolada 3D — nao integrado a cidade\nW/S acelerar/re | A/D virar | Espaco frear | L farol | N dia/noite | C camera | R reparar/reiniciar\n%d km/h | Integridade %d%% | Farois: %s | Impactos %d" % [absf(car.speed)*3.6,car.health,["apagados","baixos","altos"][car.light_mode],car.collision_count]
