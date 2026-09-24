extends StaticBody2D
## Solid foundation until a vehicle knocks the signal down.
const MODEL := preload("res://geodata/roads/traffic/TrafficSignalModel3D.gd")
const BASE_RADIUS := 5.5
const PIXELS_PER_METRE := 16.0
const ANGLE_STEPS := 16
const FALL_SPEED := 35.0
var broken := false
var _fall_view: SubViewport
var _fall_tween: Tween
var _standing_z := 0
static var _render_cache: Dictionary = {}
var road_index := -1
var entry_tangent := Vector2.RIGHT
var signal_state := 0
var sprite: Sprite2D
var render_view: SubViewport
var _near_view := false

func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("obstacle")
	add_to_group("metal_prop")
	add_to_group("fixed_traffic_signal")
	add_to_group("fragile_road_post")
	var collision := CollisionShape2D.new()
	collision.name = "Foundation"
	var circle := CircleShape2D.new()
	circle.radius = BASE_RADIUS
	collision.shape = circle
	add_child(collision)
	sprite = Sprite2D.new()
	sprite.name = "Signal3D"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	preload("res://systems/ContactShadow.gd").add_2d(self, Vector2(16, 12), 0.38)
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-65, -110, 130, 140)
	add_child(notifier)
	notifier.screen_entered.connect(_screen_entered)
	notifier.screen_exited.connect(func(): _near_view = false)

func _screen_entered() -> void:
	_near_view = true
	get_node("/root/PresentationBudget").request(self)

func set_signal_state(state: int) -> void:
	state = clampi(state, 0, 2)
	if state == signal_state: return
	signal_state = state
	# The shared viewport is rendered once for each aspect. Queueing the post
	# here can leave the previous texture visible indefinitely when it is already
	# presented; select/build the cached aspect immediately instead.
	if _near_view: ensure_presentation()

func ensure_presentation() -> void:
	if not is_inside_tree() or sprite == null: return
	if broken: return
	var angle_step := posmod(roundi(entry_tangent.angle() * ANGLE_STEPS / TAU), ANGLE_STEPS)
	var key := "%d:%d" % [angle_step, signal_state]
	var data: Dictionary = _render_cache.get(key, {})
	if data.is_empty() or not is_instance_valid(data.get("view")):
		data = _build_render(angle_step, signal_state)
		_render_cache[key] = data
	render_view = data.view
	sprite.texture = data.texture
	sprite.scale = Vector2.ONE * data.scale
	sprite.position = data.offset
	preload("res://systems/ContactShadow.gd").add_silhouette(sprite, render_view)

func _build_render(angle_step: int, state: int, falling: bool = false) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "SharedSignal3D_%d_%d" % [angle_step, state]
	viewport.size = Vector2i(384, 384) if falling else Vector2i(256, 256)
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var host: Node = get_tree().root.get_node_or_null("PresentationBudget")
	if host and is_instance_valid(host):
		host.add_child(viewport)
	else:
		get_tree().root.call_deferred("add_child", viewport)
	var model := MODEL.new()
	viewport.add_child(model)
	var tangent := Vector2.from_angle(float(angle_step) * TAU / ANGLE_STEPS)
	model.rotation.y = atan2(tangent.x, tangent.y)
	model.set_signal_state(state)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0, 8, 6), Vector3(0, 1.85, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0 if falling else 6.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.2
	viewport.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c9d6df")
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var scale_factor := PIXELS_PER_METRE * camera.size / float(viewport.size.x)
	# Project the physical ground point: the base stays exactly on its collider.
	# The viewport camera matrices are not initialized until its first render.
	# Project analytically here so a newly cached sprite cannot inherit a stale
	# ground offset (headless unproject tests alone do not expose that mismatch).
	var ground_offset := Vector2(0.0, -1.85 * camera.basis.y.y * PIXELS_PER_METRE)
	return {"view": viewport, "model": model, "texture": viewport.get_texture(), "scale": scale_factor,
		"offset": ground_offset}

func receive_vehicle_impact(speed: float, direction: Vector2) -> void:
	if broken or not is_finite(speed) or not direction.is_finite() or speed < FALL_SPEED: return
	broken = true
	if has_node("ContactShadow"): $ContactShadow.hide()
	if sprite != null and sprite.has_node("PoseShadow"): sprite.get_node("PoseShadow").hide()
	_standing_z = z_index
	collision_layer = 0
	get_node("Foundation").set_deferred("disabled", true)
	var angle_step := posmod(roundi(entry_tangent.angle() * ANGLE_STEPS / TAU), ANGLE_STEPS)
	var data := _build_render(angle_step, signal_state, true)
	_fall_view = data.view
	render_view = _fall_view
	sprite.texture = data.texture
	sprite.scale = Vector2.ONE * data.scale
	sprite.position = data.offset
	var model: Node3D = data.model
	for lens in model.lenses:
		lens.emission_enabled = false
		lens.albedo_color = Color("202428")
	var initial := model.quaternion
	var axis := Vector3(direction.y, 0, -direction.x).normalized()
	if axis.is_zero_approx(): axis = Vector3.FORWARD
	_fall_tween = create_tween()
	_fall_tween.tween_method(func(angle: float):
		model.quaternion = Quaternion(axis, angle) * initial
		_fall_view.render_target_update_mode = SubViewport.UPDATE_ONCE,
		0.0, PI * 0.49, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tween.tween_callback(func(): z_as_relative = false; z_index = 7)

func restore_world_prop() -> void:
	if _fall_tween: _fall_tween.kill()
	broken = false
	if has_node("ContactShadow"): $ContactShadow.show()
	if sprite != null and sprite.has_node("PoseShadow"): sprite.get_node("PoseShadow").show()
	z_as_relative = true
	z_index = _standing_z
	collision_layer = 1
	get_node("Foundation").set_deferred("disabled", false)
	ensure_presentation()
	if is_instance_valid(_fall_view): _fall_view.queue_free()
	_fall_view = null

func _exit_tree() -> void:
	if _fall_tween: _fall_tween.kill()
	if is_instance_valid(_fall_view): _fall_view.queue_free()
