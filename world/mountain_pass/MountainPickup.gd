class_name MountainPickup
extends "res://prototypes/living_cast/HarborCoupe.gd"

## MountainPickup: Picape 3D 4x4 da Montanha (Ranch Single Heavy)
## Veículo 3D com caçamba aberta, santantônio tubular duplo, holofotes auxiliares,
## estepe off-road na caçamba, quebra-mato e tração para estradas de terra e serra.

const PICKUP_MODEL := preload("res://prototypes/living_cast/models/RanchSingleModel.gd")
const PICKUP_CAMERA := preload("res://systems/DynamicCamera.gd")

func _init() -> void:
	active_archetype_id = "ranch_single"
	max_speed = 500.0
	acceleration = 430.0
	turn_speed = 3.0
	has_nitro = false
	paint_color = Color("#7b3f11") # Marrom conhaque rústico de montanha

func _enter_tree() -> void:
	process_physics_priority = -1
	if not has_node("Collision"):
		var collider := CollisionShape2D.new()
		collider.name = "Collision"
		collider.shape = RectangleShape2D.new()
		collider.shape.size = Vector2(88, 42)
		add_child(collider)
	if not has_node("Camera"):
		var camera_node := Camera2D.new()
		camera_node.set_script(PICKUP_CAMERA)
		camera_node.name = "Camera"
		camera_node.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		camera_node.enabled = false
		camera_node.ignore_rotation = true
		add_child(camera_node)
	if not has_node("InteractArea"):
		var area := Area2D.new()
		area.name = "InteractArea"
		area.collision_layer = 0
		area.collision_mask = 4
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 68.0
		shape.shape = circle
		area.add_child(shape)
		add_child(area)
	collision_mask = 23
	z_index = 8

func _create_body_model() -> Node3D:
	return PICKUP_MODEL.new()

func _wheel_axles() -> PackedFloat32Array:
	return PackedFloat32Array([-1.45, 1.45])

func _wheel_track() -> float:
	return 0.94

func enter_vehicle(player_body: CharacterBody2D) -> void:
	if is_driven_by_player or player_body == null or health <= 0:
		return
	if has_node("Camera"):
		$Camera.enabled = true
	super.enter_vehicle(player_body)



func _headlamp_mounts() -> Array[Vector3]:
	return [Vector3(-0.78, 0.82, -2.48), Vector3(0.78, 0.82, -2.48)]
