extends "res://prototypes/living_cast/HarborCoupe.gd"

## Veículo 3D modular de produção que inst instancia dinamicamente qualquer modelo da Frota Viva.
## Aplica física, colisores 2D, câmera ortogonal 3D e danos conforme o VehicleCatalog.

@export var archetype_id: String = "union_sedan":
	set(val):
		archetype_id = val

var model_spec: Dictionary = {}

func _enter_tree() -> void:
	process_physics_priority = -1
	if not has_node("Collision"):
		var collider := CollisionShape2D.new()
		collider.name = "Collision"
		collider.shape = RectangleShape2D.new()
		collider.shape.size = Vector2(82, 35)
		add_child(collider)
	if not has_node("Camera"):
		var camera_node := Camera2D.new()
		camera_node.set_script(preload("res://DynamicCamera.gd"))
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

func enter_vehicle(player_body: CharacterBody2D) -> void:
	if is_driven_by_player or player_body == null or health <= 0:
		return
	if has_node("Camera"):
		$Camera.enabled = true
	super.enter_vehicle(player_body)


func _create_body_model() -> Node3D:
	model_spec = VehicleCatalog.get_vehicle_spec(archetype_id)
	var model_path: String = model_spec.get("model_class", "res://prototypes/living_cast/models/UnionSedanModel.gd")
	var script_res = load(model_path)
	if script_res:
		var instance = script_res.new() as Node3D
		return instance
	return MODEL.new()

func _wheel_track() -> float:
	var width_m: float = float(model_spec.get("target_width", 34.0)) / PIXELS_PER_METRE
	return width_m * 0.46

func _wheel_axles() -> PackedFloat32Array:
	var length_m: float = float(model_spec.get("target_length", 82.0)) / PIXELS_PER_METRE
	var front_z: float = -length_m * 0.32
	var rear_z: float = length_m * 0.30
	return PackedFloat32Array([front_z, rear_z])

func _ready() -> void:
	model_spec = VehicleCatalog.get_vehicle_spec(archetype_id)

	# Atualizar parâmetros dinâmicos de física a partir do catálogo
	max_speed = float(model_spec.get("max_speed", 480.0))
	acceleration = float(model_spec.get("acceleration", 860.0))
	braking = float(model_spec.get("braking", 1100.0))
	turn_speed = float(model_spec.get("turn_speed", 3.0))
	health = int(model_spec.get("durability", 100))
	max_health = health
	active_archetype_id = archetype_id

	# Definir cor inicial
	var cols: Array = model_spec.get("colors", [Color("#2c3e50")])
	paint_color = cols[randi() % cols.size()]

	super._ready()

	# Ajustar dimensões de colisão 2D
	var t_len: float = float(model_spec.get("target_length", 82.0))
	var t_wid: float = float(model_spec.get("target_width", 34.0))
	if has_node("Collision"):
		$Collision.shape.size = Vector2(t_len * 0.96, t_wid * 0.94)
	if has_node("BumperHitbox") and $BumperHitbox.get_child_count() > 0:
		$BumperHitbox.get_child(0).shape.size = Vector2(t_len * 0.98, t_wid * 0.98)

	# Ajustar tamanho da câmera e do viewport para veículos longos (ex: ônibus e caminhões)
	var cam_size: float = maxf(6.0, (t_len / PIXELS_PER_METRE) * 1.25)
	if body_viewport:
		var v_size := 192
		if t_len > 100.0:
			v_size = 256
		body_viewport.size = Vector2i(v_size, v_size)
		var view := body_viewport.get_node_or_null("Camera3D") as Camera3D
		if view == null:
			for c in body_viewport.get_children():
				if c is Camera3D:
					view = c
					break
		if view:
			view.size = cam_size
			uniform_scale = PIXELS_PER_METRE * view.size / float(v_size)
			sprite.scale = Vector2.ONE * uniform_scale

	# Ajustar sombra de contato
	preload("res://ContactShadow.gd").add_vehicle(self, Vector2(t_len, t_wid))
