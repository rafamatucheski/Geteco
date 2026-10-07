extends SubViewportContainer
## Vitrine 3D da oficina: o carro de verdade (mesmo modelo e pintura do jogo) girando
## num palco, num mundo 3D próprio que não toca na cena do jogo. Arrastar com o mouse
## gira; solto, volta a girar sozinho. Só o neon tem aparência própria entre as peças;
## as mecânicas aparecem nas barras de desempenho da tela, não no modelo.
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PAINT := preload("res://runtime/VehiclePaint.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const SPIN_RATE := .38
const IDLE_RESUME := 2.5
var _viewport: SubViewport
var _camera: Camera3D
var _model: Node3D
var _glow_light: OmniLight3D
var _glow_disc: MeshInstance3D
var _glow_material: StandardMaterial3D
var _archetype := ""
var _yaw := .75
var _idle := 0.0
var _distance := 6.5
var _focus := Vector3(0,.6,0)
var _dragging := false

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8d9aa8")
	environment.ambient_light_energy = .75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_camera = Camera3D.new()
	_camera.environment = environment
	_camera.fov = 34.0
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
	_build_stage()
	set_process(false)

func _build_stage() -> void:
	var plate := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 2.9
	cylinder.bottom_radius = 2.9
	cylinder.height = .06
	plate.mesh = cylinder
	plate.position.y = -.03
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color("1b2026")
	finish.metallic = .15
	finish.roughness = .72
	plate.material_override = finish
	_viewport.add_child(plate)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.84
	torus.outer_radius = 2.9
	ring.mesh = torus
	ring.position.y = .02
	var ring_finish := StandardMaterial3D.new()
	ring_finish.albedo_color = Color("d8b45f")
	ring_finish.emission_enabled = true
	ring_finish.emission = Color("d8b45f")
	ring_finish.emission_energy_multiplier = 1.4
	ring.material_override = ring_finish
	_viewport.add_child(ring)
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
	disc.size = Vector2(5.6,5.6)
	_glow_disc.mesh = disc
	_glow_disc.position.y = .035
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
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
	if archetype != _archetype or not is_instance_valid(_model):
		_clear_model()
		_archetype = archetype
		_model = FLEET.create(archetype)
		if _model != null:
			var painter = PAINT.new()
			painter.bind(_model,archetype)
			painter.apply(paint)
			_viewport.add_child(_model)
		var dimensions: Array = FLEET.spec(archetype).get("bounds_size",[1.9,1.4,4.4])
		var length := float(dimensions[2])
		_distance = maxf(6.4,length*2.05)
		_focus = Vector3(0,float(dimensions[1])*.42,0)
		_idle = 0.0
	apply_parts(parts)

func apply_parts(parts: Dictionary) -> void:
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

func has_model() -> bool:
	return is_instance_valid(_model)

func yaw() -> float:
	return _yaw

func _clear_model() -> void:
	if is_instance_valid(_model):
		_viewport.remove_child(_model)
		_model.queue_free()
	_model = null

func _process(delta: float) -> void:
	_idle = maxf(0.0,_idle-delta)
	if not _dragging and _idle <= 0.0: _yaw = wrapf(_yaw+SPIN_RATE*delta,-PI,PI)
	var pitch := deg_to_rad(15.0)
	var offset := Vector3(sin(_yaw)*cos(pitch),sin(pitch),cos(_yaw)*cos(pitch))*_distance
	_camera.position = _focus+offset
	_camera.look_at(_focus)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_idle = IDLE_RESUME
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw = wrapf(_yaw-event.relative.x*.01,-PI,PI)
		_idle = IDLE_RESUME
		accept_event()
