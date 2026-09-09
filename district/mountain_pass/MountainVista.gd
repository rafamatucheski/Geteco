extends Node2D
## The next city is a distant vista, not an unlocked desert level.
var layer: CanvasLayer
var actor: Node2D
var previous_disabled := false
var previous_dialogue := false
var previous_paused := false
var hint: Label
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2(6770,-2940)
	var rail := Line2D.new()
	rail.points = PackedVector2Array([Vector2(-45,-12),Vector2(45,-12)])
	rail.width = 4
	rail.default_color = Color("a5b7bb")
	add_child(rail)
	hint = Label.new()
	hint.position = Vector2(-115,20)
	hint.add_theme_font_size_override("font_size",12)
	hint.text = "[F] MIRANTE / CIDADE DAS LUZES"
	add_child(hint)

func _process(_delta: float) -> void:
	actor = get_tree().get_first_node_in_group("player") as Node2D
	hint.visible = actor != null and actor.visible and actor.global_position.distance_to(global_position)<150

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if layer != null:
		if event.physical_keycode in [KEY_ESCAPE,KEY_F]:
			_close()
			get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F and hint.visible:
		_open()
		get_viewport().set_input_as_handled()

func _open() -> void:
	actor = get_tree().get_first_node_in_group("player") as Node2D
	if actor == null or layer != null: return
	previous_disabled = actor.is_control_disabled
	previous_dialogue = actor.is_in_dialogue
	previous_paused = get_tree().paused
	actor.is_control_disabled = true
	actor.is_in_dialogue = true
	get_tree().paused = true
	layer = CanvasLayer.new()
	layer.layer = 150
	add_child(layer)
	var panel := SubViewportContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.stretch = true
	layer.add_child(panel)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	panel.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0,21,52)
	camera.look_at(Vector3(0,2,-35))
	camera.fov = 62
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("253954")
	sky_material.sky_horizon_color = Color("c49b8e")
	sky_material.ground_horizon_color = Color("b79788")
	sky_material.ground_bottom_color = Color("796861")
	sky.sky_material = sky_material
	environment.environment.sky = sky
	environment.environment.fog_enabled = true
	environment.environment.fog_light_color = Color("ada0ad")
	environment.environment.fog_density = 0.002
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a7b0cf")
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-15,-40,0)
	sun.light_color = Color("eebc8c")
	viewport.add_child(sun)
	_box(viewport,Vector3(0,-2,-35),Vector3(900,1,900),Color("877c71"))
	_box(viewport,Vector3(0,-1.4,-30),Vector3(3,0.05,160),Color("454951"))
	for i in 24:
		var x := float((i*31)%97)-48
		var z := -68.0-float((i*19)%45)
		var height := 3.0+float((i*13)%14)
		_box(viewport,Vector3(x,height*0.5,z),Vector3(3.8,height,4),Color("555570"))
		for row in int(height/1.6):
			_box(viewport,Vector3(x,1+row*1.6,z+2.02),Vector3(2.6,0.16,0.05),Color("efc885"),0.8)
		_box(viewport,Vector3(x,height+0.1,z),Vector3(4,0.12,4.2),Color("83b4be") if i%2 else Color("c88bae"),0.8)
	# Distinct casino landmarks: a tall needle and a distant observation wheel.
	_box(viewport,Vector3(8,12,-84),Vector3(0.65,26,0.65),Color("bfc5cf"))
	_box(viewport,Vector3(8,21,-84),Vector3(4.2,1.2,4.2),Color("b9b8db"),0.3)
	var wheel := MeshInstance3D.new()
	wheel.mesh = TorusMesh.new()
	wheel.mesh.inner_radius = 5.4
	wheel.mesh.outer_radius = 5.65
	wheel.rotation.x = PI*0.5
	wheel.position = Vector3(-19,6,-65)
	wheel.material_override = StandardMaterial3D.new()
	wheel.material_override.albedo_color = Color("dba8c6")
	viewport.add_child(wheel)
	for side in [-1.0,1.0]:
		_peak(viewport,Vector3(side*34,-1,40),29,19,Color("536577"))
		_peak(viewport,Vector3(side*34,12,40),9,6,Color("ced8df"))
	for i in 8:
		_peak(viewport,Vector3(-130+i*38,-2,-170),31,19+float(i%3)*7,Color("807e91"))
	for i in 5:
		_peak(viewport,Vector3((-75+i*34) if absf(-75+i*34)>20 else 32,-2,-20-float(i%2)*30),14,4,Color("927c72"))
	var caption := Label.new()
	caption.text = "CIDADE DAS LUZES\nAlém da serra, a rodovia corta o deserto. Os pilotos chamam aquele brilho de promessa.\n[F / ESC] Voltar ao mirante"
	caption.position = Vector2(28,600)
	caption.add_theme_font_size_override("font_size",18)
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",2)
	caption.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(caption)

func _box(parent: Node, point: Vector3, size: Vector3, color: Color, glow := 0.0) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.position = point
	mesh.material_override = StandardMaterial3D.new()
	mesh.material_override.albedo_color = color
	mesh.material_override.emission_enabled = glow>0
	mesh.material_override.emission = color
	mesh.material_override.emission_energy_multiplier = glow
	parent.add_child(mesh)

func _close() -> void:
	if layer == null: return
	if is_instance_valid(actor):
		actor.is_control_disabled = previous_disabled
		actor.is_in_dialogue = previous_dialogue
	get_tree().paused = previous_paused
	layer.queue_free()
	layer = null

func _peak(parent: Node, base: Vector3, radius: float, height: float, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = CylinderMesh.new()
	mesh.mesh.top_radius = 0
	mesh.mesh.bottom_radius = radius
	mesh.mesh.height = height
	mesh.mesh.radial_segments = 7
	mesh.mesh.rings = 1
	mesh.position = base+Vector3(0,height*0.5,0)
	mesh.material_override = StandardMaterial3D.new()
	mesh.material_override.albedo_color = color
	mesh.material_override.roughness = 1
	parent.add_child(mesh)
