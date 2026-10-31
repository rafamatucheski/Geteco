extends SubViewportContainer
## O mesmo veículo e pintura numa baia estática de oficina. Um único viewport isolado;
## a órbita gira o modelo exibido, mantendo a sala e a iluminação paradas.
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PAINT := preload("res://runtime/VehiclePaint.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const SPIN_RATE := .14
const IDLE_RESUME := 2.5
var _viewport: SubViewport
var _camera: Camera3D
var _model: Node3D
var _glow_light: OmniLight3D
var _glow_disc: MeshInstance3D
var _glow_material: StandardMaterial3D
var _archetype := ""
var _yaw := 2.35
var _idle := 0.0
var _distance := 6.5
var _focus := Vector3(0,.6,0)
var _dragging := false
var _zoom := 1.2
var _pitch := .28
var _auto_rotate := true
var _bay: Node3D
var _painter: RefCounted
var _appearance: RefCounted
var _paint_color := Color.WHITE

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Segue o MSAA do jogo: 4x fixo recompilava os materiais do carro na primeira vista da oficina.
	_viewport.msaa_3d = preload("res://runtime/RenderPolicy.gd").subviewport_msaa(Viewport.MSAA_4X)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("303b3e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8d9aa8")
	environment.ambient_light_energy = .65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_camera = Camera3D.new()
	_camera.environment = environment
	_camera.fov = 37.0
	_camera.near = .1
	_camera.far = 60.0
	_viewport.add_child(_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38,38,0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18,-150,0)
	rim.light_color = Color("a9c4ff")
	rim.light_energy = .8
	_viewport.add_child(rim)
	_build_neon()
	set_process(false)

func _build_neon() -> void:
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.albedo_color = Color(1,1,1,.0)
	# Brilho redondo que some nas bordas, sem cantos de quadrado sobre o palco.
	var falloff := Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0,.62,1.0])
	falloff.colors = PackedColorArray([Color(1,1,1,.95),Color(1,1,1,.4),Color(1,1,1,0.0)])
	var radial := GradientTexture2D.new()
	radial.gradient = falloff
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(.5,.5)
	radial.fill_to = Vector2(1.0,.5)
	radial.width = 256
	radial.height = 256
	_glow_material.albedo_texture = radial
	_glow_disc = MeshInstance3D.new()
	var disc := PlaneMesh.new()
	disc.size = Vector2(2.8,4.8)
	_glow_disc.mesh = disc
	_glow_disc.position.y = .02
	_glow_disc.material_override = _glow_material
	_glow_disc.visible = false
	_viewport.add_child(_glow_disc)
	_glow_light = OmniLight3D.new()
	_glow_light.position.y = .25
	_glow_light.omni_range = 3.6
	_glow_light.light_energy = 0.0
	_viewport.add_child(_glow_light)

## Põe o carro na vitrine. Carro já exibido só troca as peças (sem recriar o modelo).
func show_car(archetype: String, paint: Color, parts: Dictionary) -> void:
	if not is_instance_valid(_bay):
		_bay = preload("res://gameplay/desert_cars/TuningWorkshopBay.gd").new().build()
		_viewport.add_child(_bay)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
	if archetype != _archetype or not is_instance_valid(_model):
		_clear_model()
		_archetype = archetype
		_model = FLEET.create(archetype)
		if _model != null:
			_painter = PAINT.new()
			_painter.bind(_model,archetype)
			_appearance = preload("res://gameplay/desert_cars/TuningAppearance.gd").new()
			_appearance.bind(_model,_painter)
			_viewport.add_child(_model)
		var dimensions: Array = FLEET.spec(archetype).get("bounds_size",[1.9,1.4,4.4])
		var length := float(dimensions[2])
		_distance = maxf(7.0,length*1.95)
		_focus = Vector3(0,float(dimensions[1])*.42,0)
		reset_view()
	_paint_color = paint
	apply_parts(parts)
	_update_view()

func apply_parts(parts: Dictionary) -> void:
	if _appearance != null: _appearance.apply(parts,_paint_color)
	var neon := ""
	for id in TUNING.clean_parts(parts).values():
		if TUNING.PARTS[id].has("neon"): neon = str(TUNING.PARTS[id].neon)
	_glow_disc.visible = not neon.is_empty()
	if neon.is_empty():
		_glow_light.light_energy = 0.0
		return
	var color := Color(neon)
	_glow_material.albedo_color = Color(color.r,color.g,color.b,1.0)
	_glow_light.light_color = color
	_glow_light.light_energy = 2.2

func hide_showroom() -> void:
	set_process(false)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_clear_model()
	_archetype = ""
	_dragging = false

func has_model() -> bool:
	return is_instance_valid(_model)

func yaw() -> float:
	return _yaw

func _clear_model() -> void:
	if is_instance_valid(_model):
		_viewport.remove_child(_model)
		_model.queue_free()
	_model = null
	_painter = null
	_appearance = null

func reset_view() -> void:
	_yaw = 2.35
	_zoom = 1.2
	_pitch = .28
	_idle = 0.0
	_auto_rotate = true
	_update_view()

func zoom_by(amount: float) -> void:
	_zoom = clampf(_zoom+amount,.80,1.38)
	_update_view()

func set_auto_rotate(enabled: bool) -> void:
	_auto_rotate = enabled

func _update_view() -> void:
	if not is_instance_valid(_camera): return
	# Sala parada: o modelo gira no próprio eixo em vez de as paredes orbitarem.
	if is_instance_valid(_model): _model.rotation.y = .75-_yaw
	_glow_disc.rotation.y = .75-_yaw
	var offset := Vector3(sin(.75)*cos(_pitch),sin(_pitch),cos(.75)*cos(_pitch))*_distance/_zoom
	_camera.position = _focus+offset
	_camera.look_at(_focus)

func _process(delta: float) -> void:
	_idle = maxf(0.0,_idle-delta)
	if _auto_rotate and not _dragging and _idle <= 0.0: _yaw = wrapf(_yaw+SPIN_RATE*delta,-PI,PI)
	_update_view()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_by(.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -.08)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_idle = IDLE_RESUME
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw = wrapf(_yaw-event.relative.x*.01,-PI,PI)
		_pitch = clampf(_pitch+event.relative.y*.003,.16,.55)
		_idle = IDLE_RESUME
		accept_event()
