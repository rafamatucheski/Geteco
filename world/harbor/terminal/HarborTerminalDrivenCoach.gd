extends "res://world/shared/traffic/TrafficVehicle.gd"
## Retain the terminal's authored coach, livery and projection while driving.
var service: Node2D
var _native_heading := INF

func _ready() -> void:
	target_length = 107.1
	super._ready()
	active_archetype_id = "route_city"
	vehicle_id = active_archetype_id
	display_name = service.coach_model.operator_name if is_instance_valid(service.coach_model) else "Ônibus rodoviário"
	vehicle_mass = 5.5
	max_health = 350
	health = max_health
	max_speed = 380.0
	visual.hide()
	remove_from_group("ambient_traffic")
	add_to_group("harbor_terminal_coach")
	for ray in ["FrontRay","FrontRayL","FrontRayR"]: get_node(ray).enabled = false

func _process(_delta: float) -> void: pass

func _physics_process(delta: float) -> void:
	var before := global_position
	super._physics_process(delta)
	service.heading = Vector2.RIGHT.rotated(rotation)
	# Native projection changes the hull's apparent length with heading.
	var turning := not is_equal_approx(_native_heading,rotation)
	if turning:
		_native_heading = rotation
		var shape: ConvexPolygonShape2D = service._shape_for_heading(service.heading)
		var points := shape.points
		for i in points.size(): points[i] = points[i].rotated(-rotation)
		shape.points = points
		collision.shape = shape
		pedestrian_hitbox.get_node("Collision").shape = shape
	service.coach_shape = collision
	service.current_speed = velocity.length()
	var travelled := before.distance_to(global_position)
	if turning or travelled > 0.0: service._sync_native(travelled)

func _animate_car_door(_side: float = -1.0, _hold_seconds: float = 0.42) -> void:
	service.door_amount = 0.0
