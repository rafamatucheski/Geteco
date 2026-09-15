class_name CharacterPreview3D
extends SubViewportContainer

@export var auto_rotate := false
@export var rotate_speed := .25
var viewport: SubViewport
var camera: Camera3D
var model_root: Node3D
var dante_root: Node3D
var active_outfit_id := "dante_classic"
var is_dragging := false
var last_mouse_pos := Vector2.ZERO
var rig: CharacterBody2D

func _ready() -> void:
	custom_minimum_size = Vector2(260, 320)
	stretch = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(360, 440)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.72
	camera.position = Vector3(0, 1.0, 3.5)
	camera.look_at(Vector3(0, .67, 0))
	for spec in [[Vector3(-30,35,0),1.25,Color("ffe5cc")], [Vector3(-20,-50,0),.65,Color("c6dbed")], [Vector3(-15,180,0),.8,Color("e6d2b0")]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_energy = spec[1]
		light.light_color = spec[2]
		viewport.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("8896a3")
	environment.environment.ambient_light_energy = .45
	viewport.add_child(environment)
	model_root = Node3D.new()
	viewport.add_child(model_root)
	dante_root = model_root
	# The production builder preserves child zero as the ground shadow slot.
	model_root.add_child(Node3D.new())
	rig = preload("res://scripts/player/DantePreviewRig.gd").new()
	rig.collision_layer = 0
	rig.collision_mask = 0
	add_child(rig)
	rig.model_root = model_root
	# A loja mostra o mesmo Dante Meshy que o jogador vai vestir.
	rig.use_meshy = true
	set_outfit(active_outfit_id)

func set_outfit(outfit_id: String) -> void:
	active_outfit_id = outfit_id
	if rig == null: return
	model_root.rotation.y = PI - .22
	rig.build(outfit_id)

func _process(delta: float) -> void:
	if viewport != null and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		is_dragging = false
		return
	if auto_rotate and not is_dragging and model_root:
		model_root.rotation.y += rotate_speed * delta

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_dragging = event.pressed
		last_mouse_pos = event.position
	elif event is InputEventMouseMotion and is_dragging:
		model_root.rotation.y += (event.position.x-last_mouse_pos.x)*.015
		last_mouse_pos = event.position
