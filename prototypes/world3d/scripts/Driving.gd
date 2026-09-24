extends Node
const VEHICLE := preload("res://scripts/Vehicle.gd")
var world
var car: CharacterBody3D
var occupied := false
var prompt: Label
var speed_label: Label
var instructions: Label
var status := ""
var status_time := 0.0
var interface_clock := 0.0
var exit_capsule := CapsuleShape3D.new()

func _ready() -> void:
	car = VEHICLE.new()
	car.name = "PlayerCoupe"
	car.position = Vector3(-4.25,0.04,9)
	world.add_child(car)
	exit_capsule.radius = 0.32
	exit_capsule.height = 1.72
	prompt = Label.new()
	prompt.position = Vector2(26,626)
	prompt.add_theme_font_size_override("font_size",20)
	world.hud.add_child(prompt)
	speed_label = Label.new()
	speed_label.position = Vector2(1100,620)
	speed_label.add_theme_font_size_override("font_size",28)
	world.hud.add_child(speed_label)
	instructions = world.hud.get_node("Help")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		interact()

func can_enter() -> bool:
	if occupied or absf(car.speed) > 0.5: return false
	for side in [-1,1]:
		var door := car.to_global(Vector3(side*1.55,0,0.15))
		if world.player.position.distance_to(door) > 1.8: continue
		var ray := PhysicsRayQueryParameters3D.create(world.player.position+Vector3.UP*0.9,door+Vector3.UP*0.9,7,[world.player.get_rid(),car.get_rid()])
		if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return true
	return false

func interact() -> bool:
	if get_tree().paused: return false
	if occupied: return leave()
	if not can_enter(): return false
	occupied = true
	car.controlled = true
	car.brake_input = false
	car.throttle_input = 0
	world.player.set_physics_process(false)
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.hide()
	world.camera.target = car
	return true

func exit_position() -> Vector3:
	for side in [-1,1]:
		for offset in [0.15,-1.1,1.1]:
			var point := car.to_global(Vector3(side*1.65,0,offset))
			point.y = 0.04
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = exit_capsule
			query.collision_mask = 7
			query.exclude = [world.player.get_rid()]
			query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*0.87)
			if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
			var start := car.to_global(Vector3(side*1.08,0,offset))
			start.y = point.y
			query.exclude = [world.player.get_rid(),car.get_rid()]
			query.transform.origin = start+Vector3.UP*0.87
			query.motion = point-start
			var sweep: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
			if sweep[0] < 1.0: continue
			var ground := PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.3,point-Vector3.UP*0.2,1)
			if world.get_world_3d().direct_space_state.intersect_ray(ground).is_empty(): continue
			return point
	return Vector3.INF

func leave() -> bool:
	if not occupied: return false
	if absf(car.speed) > 0.5:
		_message("Pare o carro para sair")
		return false
	var point := exit_position()
	if not point.is_finite():
		_message("Saída bloqueada — afaste o carro")
		return false
	occupied = false
	car.controlled = false
	car.external_input = false
	car.throttle_input = 0
	world.player.teleport(point)
	world.player.collision_layer = 2
	world.player.collision_mask = 7
	world.player.show()
	world.player.set_physics_process(true)
	world.camera.target = world.player
	return true

func _message(text: String) -> void:
	status = text
	status_time = 2.5

func _process(delta: float) -> void:
	status_time = maxf(0,status_time-delta)
	interface_clock += delta
	if interface_clock < 0.1: return
	interface_clock = 0
	prompt.text = status if status_time > 0 else ("F  Sair do carro" if occupied else ("F  Entrar no carro" if can_enter() else ""))
	speed_label.text = "%02d km/h" % roundi(absf(car.speed)*3.6) if occupied else ""
	instructions.text = "W / S  acelerar / ré    A / D  virar    Espaço  frear    F  sair    Esc  pausa" if occupied else "WASD  mover    Shift  correr    F  entrar    Roda  zoom    Q / E  girar    Esc  pausa"

func _physics_process(_delta: float) -> void:
	if occupied: world.player.position = car.position
