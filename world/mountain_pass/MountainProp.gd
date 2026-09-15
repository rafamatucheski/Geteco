extends Node2D
## Matches projected floor geometry to 2D physics at 18 pixels per metre.
var model_script: Script
var paint := Color("584735")
var model: Node3D
var viewport: SubViewport
var camera: Camera3D
var sprite: Sprite2D
var open_front := false
var _rendered_once := false
const DISPLAY_SCALE := 0.4921875 # 256 / 7m * scale = 18px/m

func _ready() -> void:
	z_index = 4
	viewport = SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	model = model_script.new(paint)
	viewport.add_child(model)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 8, 5)
	camera.look_at(Vector3(0,1,0))
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.reset_physics_interpolation()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a8c9dd")
	environment.environment.ambient_light_energy = 0.85
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	light.light_energy = 1.1
	viewport.add_child(light)
	sprite = Sprite2D.new()
	sprite.texture = viewport.get_texture()
	sprite.scale = Vector2.ONE * DISPLAY_SCALE
	sprite.position = (Vector2(128,128) - camera.unproject_position(Vector3.ZERO)) * DISPLAY_SCALE
	add_child(sprite)
	# Projection/collision are ready immediately. The expensive first 3D render
	# waits until the prop approaches the camera, instead of drawing every den
	# and shelter across the entire streamed region in the same frame.
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.name = "FirstRenderVisibility"
	var drawn_size := Vector2(viewport.size)*DISPLAY_SCALE
	notifier.rect = Rect2(sprite.position-drawn_size*0.5,drawn_size).grow(100)
	notifier.screen_entered.connect(_render_when_visible)
	add_child(notifier)
	var footprint: Vector2 = model.footprint_size
	var shadow_size := Vector2(project(Vector3(footprint.x,0,0)).length(), project(Vector3(0,0,footprint.y)).length())
	preload("res://systems/ContactShadow.gd").add_box(self, shadow_size * 1.05, 0.44)
	if open_front:
		_solid(Rect2(-footprint*0.5, Vector2(footprint.x,0.15)))
		_solid(Rect2(-footprint*0.5, Vector2(0.15,footprint.y)))
		_solid(Rect2(Vector2(footprint.x*0.5-0.15,-footprint.y*0.5), Vector2(0.15,footprint.y)))
	else:
		_solid(Rect2(-footprint*0.5,footprint))

func project(point: Vector3) -> Vector2:
	return (camera.unproject_position(point) - camera.unproject_position(Vector3.ZERO)) * DISPLAY_SCALE

func _process(_delta: float) -> void:
	if not is_instance_valid(model) or open_front: return
	# Raised roof pixels must occlude actors standing behind the solid floor.
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if actor == null: return
	var front := project(Vector3(0, 0, model.footprint_size.y * 0.5)).y
	sprite.z_as_relative = false
	sprite.z_index = 12 if to_local(actor.global_position).y < front else 4

func _solid(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionPolygon2D.new()
	var points := PackedVector2Array()
	for point in [rect.position, Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		points.append(project(Vector3(point.x,0,point.y)))
	shape.polygon = points
	body.add_child(shape)
	add_child(body)

func _render_when_visible() -> void:
	if _rendered_once: return
	_rendered_once = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
