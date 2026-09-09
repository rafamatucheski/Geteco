extends "res://prototypes/living_cast/HarborCoupe.gd"

## MountainSUV: Veículo 3D Jogável da Montanha (Summit SUV 4x4)
## Reúne o modelo 3D do Summit SUV dos Lobos de Gelo com tração 4x4,
## física para subida de serra, barra de LED e resistência off-road.

const SUV_MODEL := preload("res://prototypes/living_cast/models/SummitSUVModel.gd")
const SUV_CAMERA := preload("res://DynamicCamera.gd")

func _init() -> void:
	active_archetype_id = "summit_suv"
	max_speed = 520.0
	acceleration = 420.0
	turn_speed = 3.2
	has_nitro = false
	paint_color = Color("2980b9") # Azul glacial tático

func _enter_tree() -> void:
	process_physics_priority = -1
	if not has_node("Collision"):
		var collider := CollisionShape2D.new()
		collider.name = "Collision"
		collider.shape = RectangleShape2D.new()
		collider.shape.size = Vector2(86, 40)
		add_child(collider)
	if not has_node("Camera"):
		var camera_node := Camera2D.new()
		camera_node.set_script(SUV_CAMERA)
		camera_node.name = "Camera"
		camera_node.enabled = false
		camera_node.ignore_rotation = true
		add_child(camera_node)
	if not has_node("InteractArea"):
		var area := Area2D.new()
		area.name = "InteractArea"
		area.collision_layer = 0
		area.collision_mask = 4
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.shape.radius = 65.0
		area.add_child(shape)
		add_child(area)
	collision_mask = 23
	z_index = 8

func _create_body_model() -> Node3D:
	return SUV_MODEL.new()

func _wheel_axles() -> PackedFloat32Array:
	return PackedFloat32Array([-1.45, 1.45])

func _wheel_track() -> float:
	return 0.98

func enter_vehicle(player_body: CharacterBody2D) -> void:
	if is_driven_by_player or player_body == null or health <= 0:
		return
	if has_node("Camera"):
		$Camera.enabled = true
	super.enter_vehicle(player_body)

func exit_vehicle() -> void:
	if has_node("Camera"):
		$Camera.enabled = false
	super.exit_vehicle()


func _headlamp_mounts() -> Array[Vector3]:
	return [Vector3(-0.74, 0.88, -2.42), Vector3(0.74, 0.88, -2.42)]
