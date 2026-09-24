class_name ArcticJeep
extends "res://prototypes/living_cast/HarborCoupe.gd"

## ArcticJeep: Jeepzão de Gelo 3D dos Contrabandistas (Summit SUV Arctic Spec)
## Veículo 3D pesado 4x4 camuflado para o gelo com tração integral, suspensão elevada,
## quebra-mato frontal com guincho, bagageiro de teto com estepe e barra de LED auxiliar.
## Spawna no acampamento do Lago Secreto pronto para ser roubado pelo jogador.

const JEEP_MODEL := preload("res://prototypes/living_cast/models/ArcticJeepModel.gd")
const JEEP_CAMERA := preload("res://systems/DynamicCamera.gd")

func _init() -> void:
	active_archetype_id = "arctic_jeep"
	max_speed = 530.0
	acceleration = 450.0
	turn_speed = 3.3
	has_nitro = false
	paint_color = Color("#dfe6e9") # Branco polar com reflexo azul ártico

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
		camera_node.set_script(JEEP_CAMERA)
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
	return JEEP_MODEL.new()

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



func _headlamp_mounts() -> Array[Vector3]:
	return [Vector3(-0.65, 0.96, -2.19), Vector3(0.65, 0.96, -2.19)]
