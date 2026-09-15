extends CanvasLayer
## One composition pass for terrain and projected 3D. No per-actor material copies
## or extra SubViewports. UI is drawn afterwards, starting at canvas layer 2.
const PALETTE := preload("res://world/shared/atmosphere/AtmospherePalette.gd")
const EFFECT := preload("res://world/shared/atmosphere/regional_atmosphere.gdshader")
var weather: CanvasModulate
var screen: ColorRect
var copy: BackBufferCopy
var effect: ShaderMaterial
var current: Dictionary = {}
var mountain_weight := 0.0
var summit_weight := 0.0
var resort_weight := 0.0
var cemetery_weight := 0.0
var _cemetery: Node2D
var sheltered := false
var focus_world := Vector2.ZERO
var _drift := Vector2.ZERO
var _elapsed := 1.0
var _initialized := false
var _stream: Node
var _mountain: Node2D
var _player: Node2D
var _target: Dictionary = {}

func _ready() -> void:
	name = "RegionalAtmosphere"
	layer = 1
	process_priority = 20
	weather = get_parent()
	add_to_group(&"regional_atmosphere")
	var noise := FastNoiseLite.new()
	noise.seed = 14092026
	noise.frequency = 0.035
	noise.fractal_octaves = 2
	var texture := NoiseTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.seamless = true
	texture.noise = noise
	effect = ShaderMaterial.new()
	effect.shader = EFFECT
	effect.set_shader_parameter("mist_texture", texture)
	# Explicit copy also composes correctly after existing world screen shaders.
	copy = BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	screen = ColorRect.new()
	screen.name = "WorldAtmosphere"
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.material = effect
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh_context()
	current = _target.duplicate()
	_initialized = true
	_apply(0.0)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		_refresh_context()
	current = PALETTE.blend(current, _target, 1.0 - exp(-delta * 3.0))
	_apply(delta)

func _refresh_context() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if not is_instance_valid(_stream):
		_stream = get_tree().get_first_node_in_group(&"continuous_world")
	if not is_instance_valid(_cemetery):
		_cemetery = get_tree().get_first_node_in_group(&"cemetery") as Node2D
	var camera := get_viewport().get_camera_2d()
	if is_instance_valid(_stream):
		focus_world = _stream.exterior_position()
		_mountain = _stream.mountain
		mountain_weight = PALETTE.mountain_weight(focus_world, _stream.MOUNTAIN_OFFSET)
	elif weather.get_parent().get("region_ready") != null:
		_mountain = weather.get_parent()
		focus_world = _player.global_position if is_instance_valid(_player) else Vector2.ZERO
		mountain_weight = 1.0
	else:
		focus_world = _player.global_position if is_instance_valid(_player) else (camera.global_position if camera else Vector2.ZERO)
		mountain_weight = 0.0
	var snow := 0.0
	resort_weight = 0.0
	sheltered = false
	if is_instance_valid(_mountain):
		summit_weight = PALETTE.summit_weight(_mountain.to_local(focus_world))
		resort_weight = PALETTE.resort_weight(_mountain.to_local(focus_world)) * mountain_weight
		if _mountain.get("region_ready") == true:
			snow = clampf(_mountain.storm_manager.storm_intensity, 0, 1)
			var local_point: Vector2 = _mountain.tunnel.to_local(focus_world)
			sheltered = Rect2(0, -_mountain.tunnel.tunnel_width * 0.5, _mountain.tunnel.tunnel_length, _mountain.tunnel.tunnel_width).has_point(local_point)
			if is_instance_valid(_player): sheltered = sheltered or bool(_player.get_meta("mountain_shelter", false))
	var cloud := 0.0
	match int(weather.weather_state):
		1: cloud = 0.65
		2: cloud = 1.0
		3: cloud = 0.45
	_target = PALETTE.sample(weather.current_biome, weather.time_of_day, cloud, mountain_weight, summit_weight, snow)
	if resort_weight > 0.0:
		_target = PALETTE.resort_sample(_target, resort_weight)
	cemetery_weight = 0.0
	if is_instance_valid(_cemetery):
		cemetery_weight = PALETTE.cemetery_weight(_cemetery.to_local(focus_world), _cemetery.LOT_SIZE) * (1.0 - mountain_weight)
		if cemetery_weight > 0.0:
			_target = PALETTE.cemetery_sample(_target, cemetery_weight)
	# City rain fades before snow takes over, without overwriting saved weather IDs.
	weather.set_regional_rain_exposure(1.0 - mountain_weight)
	if is_instance_valid(_mountain) and _mountain.get("region_ready") == true:
		var mixer: Node = _mountain.storm_manager.get_node_or_null("SnowWindAudio")
		if mixer: mixer.regional_weight = mountain_weight
		var backdrop: Node = _mountain.parallax
		if backdrop.has_method("set_atmosphere"):
			backdrop.set_atmosphere(_target.fog_color, _target.distant_haze)

func _apply(delta: float) -> void:
	if not _initialized: return
	var inside: bool = weather.is_inside_interior
	visible = not inside
	copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED if inside else BackBufferCopy.COPY_MODE_VIEWPORT
	if inside: return
	for key in ["shadow_tint", "sunlight_tint", "fog_color", "saturation", "contrast"]:
		effect.set_shader_parameter(key, current[key])
	effect.set_shader_parameter("haze", 0.0 if sheltered else current.haze)
	_drift += Vector2(current.wind) * delta
	effect.set_shader_parameter("drift", _drift)
	var view := get_viewport()
	var inverse := view.get_canvas_transform().affine_inverse()
	var size := view.get_visible_rect().size
	effect.set_shader_parameter("world_origin", inverse.origin)
	effect.set_shader_parameter("world_axis_x", inverse.basis_xform(Vector2(size.x, 0)))
	effect.set_shader_parameter("world_axis_y", inverse.basis_xform(Vector2(0, size.y)))
	effect.set_shader_parameter("focus_world", focus_world)

func refresh_immediately() -> void:
	_refresh_context()
	current = _target.duplicate()
	_apply(0.0)
