extends Node2D
## Elevated industrial hardware. Deliberately has no physics body or damage API.
## The game composites 3D models onto a 2D world: the matching canvas light
## illuminates its road, pedestrians and vehicles outside the model viewport.

@export_enum("flood", "strip") var fixture_kind := "flood"
@export var target_offset := Vector2(0, 100)
@export var tangent := Vector2.RIGHT
@export var always_on := false
@export var emits_ground_light := true
var is_lit := false
var pool: PointLight2D
var hardware: Sprite2D
var beam: Polygon2D
var _near_view := false
var _cache_key := ""
static var _models: Dictionary = {}
static var _pool_texture: GradientTexture2D
static var _beam_shader: Shader

func _ready() -> void:
	add_to_group("road_luminaire")
	add_to_group("elevated_road_light")
	hardware = Sprite2D.new()
	hardware.z_as_relative = false
	hardware.z_index = 24
	var hardware_material := CanvasItemMaterial.new()
	hardware_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	hardware.material = hardware_material
	add_child(hardware)
	pool = PointLight2D.new()
	pool.name = "RoadWash"
	pool.texture = wash_texture()
	pool.position = target_offset
	pool.color = Color("e2efff") if fixture_kind == "strip" else Color("fff0d8")
	pool.energy = 0.50 if fixture_kind == "strip" else 0.75
	pool.height = 85
	pool.scale = Vector2(1.25, 0.85) if fixture_kind == "strip" else Vector2(1.65, 1.20)
	pool.rotation = tangent.angle()
	pool.shadow_enabled = false
	pool.enabled = emits_ground_light
	add_child(pool)
	_build_beam()
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(Vector2(-330,-330),Vector2(660,660)).expand(target_offset + Vector2(330,330)).expand(target_offset - Vector2(330,330))
	add_child(notifier)
	notifier.screen_entered.connect(func(): _near_view = true; _refresh_visibility())
	notifier.screen_exited.connect(func(): _near_view = false; _refresh_visibility())
	set_lit(always_on)
	_bind_weather.call_deferred()

func _bind_weather() -> void:
	var weather := get_tree().get_first_node_in_group("day_night_manager")
	if weather and not always_on:
		if not weather.time_changed.is_connected(set_lit): weather.time_changed.connect(set_lit)
		set_lit(weather.is_dark)
	elif weather == null:
		set_lit(true) # Standalone mountain scene has its own winter atmosphere.

static func wash_texture() -> GradientTexture2D:
	if _pool_texture: return _pool_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0,0.25,0.55,0.80,1])
	gradient.colors = PackedColorArray([Color(1,1,1,.90),Color(1,1,1,.76),Color(1,1,1,.40),Color(1,1,1,.10),Color(1,1,1,0)])
	_pool_texture = GradientTexture2D.new()
	_pool_texture.width = 256
	_pool_texture.height = 256
	_pool_texture.gradient = gradient
	_pool_texture.fill = GradientTexture2D.FILL_RADIAL
	_pool_texture.fill_from = Vector2(.5,.5)
	_pool_texture.fill_to = Vector2(1,.5)
	return _pool_texture

func _build_beam() -> void:
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = "shader_type canvas_item; render_mode unshaded, blend_add; void fragment(){ float edge = pow(max(0.0,1.0-abs(UV.x*2.0-1.0)),2.0); float fade = sin(UV.y*3.14159); COLOR = vec4(0.78,0.87,1.0,edge*fade*0.045); }"
	beam = Polygon2D.new()
	beam.z_index = 7
	beam.uv = PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	var material := ShaderMaterial.new()
	material.shader = _beam_shader
	beam.material = material
	add_child(beam)

func _align_hardware() -> void:
	var data: Dictionary = _models[_cache_key]
	var center := Vector2(data.view.size)*.5
	hardware.scale = Vector2.ONE*.72 if fixture_kind == "flood" else Vector2.ONE
	hardware.rotation = tangent.angle() if fixture_kind == "strip" else 0.0
	# Anchor the projected mounting foot, not the center of the image. Transparent
	# viewport margins must never lift a pole or LED bracket off its bridge rail.
	hardware.position = -((data.mount_pixel-center)*hardware.scale).rotated(hardware.rotation)
	var origin: Vector2 = hardware.position+((data.emitter_pixel-center)*hardware.scale).rotated(hardware.rotation)
	var across := tangent.normalized()
	var narrow := 19.0 if fixture_kind == "flood" else 58.0
	beam.polygon = PackedVector2Array([origin-across*narrow,origin+across*narrow,target_offset+across*110,target_offset-across*110])

func set_lit(value: bool) -> void:
	is_lit = value or always_on
	if hardware:
		var key := "%s_%s" % [fixture_kind,is_lit]
		if key != _cache_key:
			_release_model()
			if not _models.has(key): _models[key] = _make_model(is_lit)
			_models[key].users += 1
			_cache_key = key
			hardware.texture = _models[key].view.get_texture()
		_align_hardware()
	_refresh_visibility()

func _refresh_visibility() -> void:
	if pool: pool.visible = is_lit and _near_view
	if beam: beam.visible = is_lit and _near_view

func _make_model(lit: bool) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "SharedRoadHardware_" + fixture_kind + ("Night" if lit else "Day")
	viewport.size = Vector2i(192,192) if fixture_kind == "flood" else Vector2i(160,48)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	get_tree().root.add_child.call_deferred(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("596a75")
	steel.metallic = .65
	steel.roughness = .42
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color("24353f")
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color("f0f3ec") if lit else Color("a0afae")
	lens.emission_enabled = lit
	lens.emission = Color("d9edff") if fixture_kind == "strip" else Color("ffe7b8")
	lens.emission_energy_multiplier = 2.0
	if fixture_kind == "flood":
		_box(stage,Vector3(0,.12,0),Vector3(.55,.24,.55),steel)
		_box(stage,Vector3(0,3.5,0),Vector3(.16,7,.16),steel)
		_box(stage,Vector3(0,6.95,0),Vector3(2.6,.15,.22),steel)
		_box(stage,Vector3(0,1,.15),Vector3(.3,.45,.18),rim)
		for side in [-1,1]:
			var head := Node3D.new()
			head.position = Vector3(side*.9,6.9,.15)
			head.rotation_degrees.x = -30
			stage.add_child(head)
			_box(head,Vector3.ZERO,Vector3(.96,.24,.80),rim)
			_box(head,Vector3(0,-.14,0),Vector3(.79,.035,.63),lens)
			# A beveled front diffuser remains visible from the overhead camera.
			_box(head,Vector3(0,-.08,.415),Vector3(.79,.13,.04),lens)
			for rib in 5: _box(head,Vector3(-.36+rib*.18,.18,0),Vector3(.045,.16,.70),steel)
			var spot := SpotLight3D.new()
			spot.rotation_degrees.x = -90
			spot.light_color = lens.emission
			spot.light_energy = 1.6 if lit else 0.0
			spot.spot_range = 12
			spot.spot_angle = 62
			head.add_child(spot)
	else:
		# Long enclosed linear luminaire, mounting brackets and segmented lenses.
		_box(stage,Vector3.ZERO,Vector3(6.8,.22,.34),rim)
		for x in [-2.7,0.0,2.7]:
			_box(stage,Vector3(x,-.18,.25),Vector3(.16,.48,.32),steel)
		for i in 12:
			_box(stage,Vector3(-3.08+i*.56,.015,.19),Vector3(.48,.13,.06),lens)
		_box(stage,Vector3(0,.15,0),Vector3(6.9,.07,.42),steel)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35,-25,0)
	sun.light_energy = .8
	viewport.add_child(sun)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10 if fixture_kind == "flood" else 7.6
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.look_at_from_position(Vector3(0,11,9),Vector3(0,3.5,0)) if fixture_kind == "flood" else camera.look_at_from_position(Vector3(0,5,8),Vector3.ZERO)
	var mount := Vector3.ZERO if fixture_kind == "flood" else Vector3(0,-.42,.25)
	var emitter := Vector3(0,6.9,.15) if fixture_kind == "flood" else Vector3(0,.015,.19)
	return {"view":viewport,"users":0,"mount_pixel":_project_hardware(camera,viewport,mount),"emitter_pixel":_project_hardware(camera,viewport,emitter)}

static func _project_hardware(camera: Camera3D, viewport: SubViewport, point: Vector3) -> Vector2:
	# Orthographic KEEP_WIDTH projection, valid before the cached viewport enters
	# the tree. Use the same camera basis and pixel scale as the actual model.
	var relative := point-camera.position
	return Vector2(viewport.size)*.5+Vector2(relative.dot(camera.basis.x),-relative.dot(camera.basis.y))*float(viewport.size.x)/camera.size

static func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material
	parent.add_child(mesh)

func _release_model() -> void:
	if _cache_key.is_empty() or not _models.has(_cache_key): return
	_models[_cache_key].users -= 1
	if int(_models[_cache_key].users) == 0:
		_models[_cache_key].view.queue_free()
		_models.erase(_cache_key)
	_cache_key = ""

func _exit_tree() -> void:
	_release_model()
