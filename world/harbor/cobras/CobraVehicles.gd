extends Node2D
## Two reusable production vehicles, not static scenery. No ambient respawn.
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
const COUPE := preload("res://prototypes/living_cast/HarborCoupe.gd")
const CAMERA := preload("res://systems/DynamicCamera.gd")
var parking_positions: Dictionary = {}
var secret_car: CharacterBody2D
var workshop_truck: CharacterBody2D

func _ready() -> void:
	if parking_positions.is_empty():
		return
	workshop_truck = FACTORY.spawn_parked_vehicle(self, "CobraWorkshopPickup", parking_positions.workshop, PI, "ranch_pickup", 5, Color("8c8170"))
	# The service truck deliberately trades speed for mass; use the district's
	# established .75 pacing rather than accelerating every new vehicle.
	workshop_truck.max_speed *= 0.75
	workshop_truck.acceleration *= 0.75
	secret_car = COUPE.new()
	secret_car.name = "AshbendCopperCoupe"
	secret_car.position = parking_positions.secret
	secret_car.rotation = PI
	secret_car.z_index = 8
	secret_car.collision_mask = 23
	secret_car.paint_color = Color("9f673f")
	secret_car.max_speed = 520.0
	secret_car.acceleration = 940.0
	secret_car.braking = 1500.0
	secret_car.has_nitro = false
	var collider := CollisionShape2D.new()
	collider.name = "Collision"
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(65, 28)
	collider.shape = rectangle
	secret_car.add_child(collider)
	var camera := CAMERA.new()
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.ignore_rotation = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.zoom = Vector2(1.55, 1.55)
	camera.zoom_close = 1.55
	camera.zoom_far = 1.25
	camera.zoom_nitro = 1.15
	camera.max_speed = secret_car.max_speed
	secret_car.add_child(camera)
	var interaction := Area2D.new()
	interaction.name = "InteractArea"
	interaction.collision_layer = 0
	interaction.collision_mask = 4
	var circle := CircleShape2D.new()
	circle.radius = 100.0
	var interaction_shape := CollisionShape2D.new()
	interaction_shape.shape = circle
	interaction.add_child(interaction_shape)
	secret_car.add_child(interaction)
	add_child(secret_car)

func get_vehicle_data() -> Dictionary:
	return {"secret": secret_car, "workshop": workshop_truck}
