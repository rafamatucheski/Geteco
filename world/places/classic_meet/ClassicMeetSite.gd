extends Node3D
## Exterior local, geometria agrupada por material e fontes fixas de alcance local.
const ANCHOR := Vector3(420, 0, 124)
const LOT := Rect2(409, 109, 22, 30)
const DRIVEWAY := Rect2(416, 108.65, 8, 3.35)
const GROUND := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")
var _surfaces: Dictionary = {}
var _materials: Dictionary = {}
var _body: StaticBody3D
var _lamps: Array[SpotLight3D] = []
var _event_lamps: Array[SpotLight3D] = []
var _night_material: StandardMaterial3D
var _party_material: StandardMaterial3D
var _lighting_initialized := false
var _night_enabled := false
var _celebration_enabled := false

func _ready() -> void:
	name = "TorqueClassicMeetSite"
	position = ANCHOR
	_body = StaticBody3D.new()
	_body.name = "TorqueSolids"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_build_materials()
	_build_paving()
	_build_store()
	_build_furniture()
	_build_lighting()
	_flush_meshes()
	set_night_lighting(false, false)

func parking_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for z in [-9.5, 1.0]:
		for x in [-7.0, -2.0, 3.0]:
			result.append({"position":Vector3(x,.055,z),"yaw":PI if z<0 else 0.0})
	return result

func pedestrian_spots() -> Array[Dictionary]:
	return [
		{"position":Vector3(-7.55,.055,-6.6),"yaw":0.0,"activity":"inspect"},
		{"position":Vector3(-5.6,.055,-4.9),"yaw":-.8,"activity":"talk"},
		{"position":Vector3(-3.9,.055,-4.3),"yaw":1.6,"activity":"talk"},
		{"position":Vector3(2.4,.055,-2.25),"yaw":PI,"activity":"inspect"},
		{"position":Vector3(.8,.055,-4.1),"yaw":-1.3,"activity":"talk"},
		{"position":Vector3(3.0,.055,-4.3),"yaw":1.5,"activity":"talk"},
	]

func customer_routes() -> Array[PackedVector3Array]:
	return [
		PackedVector3Array([Vector3(-8.9,.055,-13),Vector3(-8.9,.055,-3),Vector3(-8.9,.055,3.6),Vector3(-.5,.055,3.6),Vector3(-.5,.055,4.6)]),
		PackedVector3Array([Vector3(5.3,.055,-13),Vector3(5.3,.055,-8),Vector3(5.3,.055,-3.2),Vector3(5.3,.055,4.6),Vector3(1,.055,4.6)]),
	]

func set_night_lighting(night: bool, event_active: bool) -> void:
	if _night_material == null: return
	var celebration := night and event_active
	if _lighting_initialized and _night_enabled == night and _celebration_enabled == celebration: return
	_lighting_initialized = true
	_night_enabled = night
	_celebration_enabled = celebration
	_night_material.emission_energy_multiplier = 1.4 if night else 0.0
	_party_material.emission_energy_multiplier = 2.3 if celebration else 0.0
	for index in _lamps.size():
		var lamp := _lamps[index] as SpotLight3D
		lamp.visible = night
		var event_gain := 3.0 if index<2 else 2.0
		lamp.light_energy = float(lamp.get_meta("meet_base_energy"))*(event_gain if celebration else 1.0)
	for lamp in _event_lamps:
		lamp.visible = celebration
		lamp.light_energy = float(lamp.get_meta("meet_base_energy"))*(3.0 if celebration else 1.0)

func _build_materials() -> void:
	_material("asphalt",Color("454a49"),"gravel")
	_material("concrete",Color("b4b1a0"),"concrete")
	_material("wall",Color("dedbd2"),"concrete")
	_material("brick",Color("555253"),"brick")
	for entry in [["red","c92c27"],["orange","ef7928"],["roof","35383c"],["metal","30363c"],["chrome","b5bdc5"],["glass","22353e"],["white","efeae0"],["rubber","1e2227"],["soil","555345"]]:
		_material(entry[0],Color(entry[1]))
	_materials.chrome.metallic = .65
	_materials.chrome.roughness = .38
	_night_material = _material("lamp",Color("e9ddad"))
	_night_material.emission_enabled = true
	_night_material.emission = Color("ffe1b6")
	_party_material = _material("party",Color("e5c88f"))
	_party_material.emission_enabled = true
	_party_material.emission = Color("ffe2a4")

func _material(key: String, color: Color, texture := "") -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	if not texture.is_empty():
		material.albedo_texture = GROUND.texture(texture)
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE*.4
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = material
	return material

func _build_paving() -> void:
	# Piso raso sobre o solo existente: não há degrau físico nem planos coplanares.
	# AABB local por painel reduz o risco de associar faróis/postes de ambos
	# os lados da rua ao teto de luzes por objeto no Mobile. Mesmo material e UV
	# mundiais, sem decal, sobreposição, mudança de cota ou costura na textura.
	for x in [-5.5,5.5]:
		for z in [-10.0,0.0,10.0]:
			_paving_panel(Vector3(x,.036,z),Vector3(11,.02,10))
	_paving_panel(Vector3(0,.036,-15.175),Vector3(8,.02,.35))
	_box("concrete",Vector3(-.5,.047,4.9),Vector3(19,.024,2.2))
	for x in [-10.85,10.85]: _box("concrete",Vector3(x,.11,0),Vector3(.3,.2,30),true)
	_box("concrete",Vector3(0,.11,14.85),Vector3(22,.2,.3),true)
	for x in [-7.5,7.5]: _box("concrete",Vector3(x,.11,-14.85),Vector3(7,.2,.3),true)
	for z in [-9.5,1.0]:
		for x in [-9.5,-4.5,.5,5.5]: _box("white",Vector3(x,.055,z),Vector3(.09,.009,5.4))
		_box("white",Vector3(-2,.055,z+(-2.7 if z<0 else 2.7)),Vector3(15,.009,.09))
	# Ilha preserva a árvore existente em (427.5,119.375).
	_box("soil",Vector3(7.5,.058,-4.625),Vector3(2.9,.025,3.6))
	for x in [5.96,9.04]: _box("concrete",Vector3(x,.13,-4.625),Vector3(.18,.24,3.9),true)
	for z in [-6.485,-2.765]: _box("concrete",Vector3(7.5,.13,z),Vector3(3.25,.24,.18),true)
	for z in [-13.7,3.8]:
		_box("metal",Vector3(-9.8,.061,z),Vector3(.34,.016,1.25))
		for i in 7: _box("chrome",Vector3(-9.8,.071,z-.52+i*.17),Vector3(.31,.008,.025))

func _build_store() -> void:
	# Vitrines rasas na fachada fechada, com o mesmo bloqueio integral do prédio.
	_solid(Vector3(-.5,2.05,10),Vector3(19,4.1,8))
	_box("wall",Vector3(-.5,2.05,10.3),Vector3(19,4.1,7.4))
	_box("brick",Vector3(-.5,.48,5.95),Vector3(19,.9,.12))
	_box("roof",Vector3(-.5,4.14,10),Vector3(19.6,.22,8.5))
	_box("white",Vector3(-.5,4.03,5.78),Vector3(19.4,.16,.39))
	_box("red",Vector3(-.5,3.47,5.8),Vector3(19.4,.96,.35))
	_box("orange",Vector3(-.5,2.99,5.59),Vector3(19.4,.065,.07))
	_box("roof",Vector3(-.5,2.86,5.15),Vector3(19.7,.16,1.9))
	_box("red",Vector3(-.5,2.81,4.24),Vector3(19.7,.3,.12))
	_box("lamp",Vector3(-.5,2.645,4.22),Vector3(19.2,.025,.035))
	for x in [-9.62,8.62]:
		_box("red",Vector3(x,1.85,5.92),Vector3(.55,1.9,.2))
	for x in [-5.48,1.78]:
		_box("wall",Vector3(x,1.77,6.19),Vector3(.48,1.8,.78))
	for x in [-7.15,-3.8,3.45,6.8]:
		_box("glass",Vector3(x,1.8,6.46),Vector3(2.8,1.62,.08))
		_box("roof",Vector3(x,.965,6.12),Vector3(2.8,.06,.66))
		for dx in [-1.43,1.43]: _box("chrome",Vector3(x+dx,1.8,5.855),Vector3(.055,1.72,.07))
		for y in [.94,2.65]: _box("chrome",Vector3(x,y,5.855),Vector3(2.9,.06,.07))
		_box("lamp",Vector3(x,2.56,6.11),Vector3(2.55,.035,.06))
	_build_window_displays()
	# Porta fechada com bloqueio do edifício; este cenário não cria interior.
	for x in [-.6,.6]:
		_box("glass",Vector3(x,1.38,5.91),Vector3(1.12,2.56,.11))
		_box("chrome",Vector3(x+(-.48 if x>0 else .48),1.25,5.77),Vector3(.045,.55,.045))
	for x in [-1.21,0,1.21]: _box("chrome",Vector3(x,1.38,5.81),Vector3(.065,2.65,.08))
	var sign := Label3D.new()
	sign.name = "TorqueName"
	sign.text = "TORQUE"
	sign.font = preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
	sign.font_size = 100
	sign.pixel_size = .013
	sign.outline_size = 0
	sign.modulate = Color("fff5e6")
	sign.position = Vector3(.35,3.49,5.59)
	sign.rotation.y = PI
	sign.no_depth_test = false
	add_child(sign)
	# Emblema de velocidade sem slogans ou legendas na fachada.
	for i in 4:
		_angled_box("orange",Vector3(-4.1+i*.37,3.48,5.56),Vector3(.22,.7,.06),-.38)
	for x in [-8.9,7.9]:
		_box("roof",Vector3(x,3.47,5.58),Vector3(1.12,.67,.07))
		for i in 3:
			_angled_box("white",Vector3(x-.32+i*.32,3.47,5.53),Vector3(.13,.43,.025),-.38)
	_box("metal",Vector3(-.5,1.35,14.035),Vector3(2.3,2.6,.09))
	for i in 12: _box("chrome",Vector3(-.5,.2+i*.21,14.09),Vector3(2.2,.035,.045))
	for x in [-5.0,5.0]:
		_box("metal",Vector3(x,4.53,11.3),Vector3(1.5,.62,1.15))
		for i in 5: _box("chrome",Vector3(x-.55+i*.275,4.86,11.3),Vector3(.09,.03,1.0))

func _build_furniture() -> void:
	# Expositor de pneus e rodas ocupa a antiga área das caixas, fora do corredor.
	for x in [-7.9,-6.6]:
		_solid(Vector3(x,.78,4.85),Vector3(1.12,1.5,.68))
		_box("metal",Vector3(x,.18,4.85),Vector3(1.1,.25,.66))
		for y in [.55,1.22]:
			_display_wheel(Vector3(x,y,4.85),.30)
		for dx in [-.5,.5]: _box("orange",Vector3(x+dx,.72,4.94),Vector3(.035,1.4,.035))
	# Carrinho de ferramentas vermelho: gavetas, puxadores e rodízios reais.
	_solid(Vector3(7.48,.59,4.85),Vector3(1.38,1.05,.8))
	_box("red",Vector3(7.45,.63,4.85),Vector3(1.2,.85,.7))
	_box("roof",Vector3(7.45,1.08,4.85),Vector3(1.3,.07,.8))
	for y in [.35,.52,.69,.86]:
		_box("metal",Vector3(7.45,y,4.485),Vector3(1.08,.025,.025))
		_box("chrome",Vector3(7.45,y+.065,4.46),Vector3(.66,.03,.04))
	for x in [6.94,7.96]:
		for z in [4.59,5.11]: _cylinder("rubber",Vector3(x,.16,z),.105,.065,Vector3(0,0,PI*.5))
	_box("chrome",Vector3(8.11,.96,4.85),Vector3(.035,.06,.55))
	# Proteções junto à porta, sem obstruir os corredores dos clientes.
	for x in [-1.6,1.6]:
		_cylinder("orange",Vector3(x,.45,5.35),.095,.8)
		_solid(Vector3(x,.45,5.35),Vector3(.2,.8,.2))
		_cylinder("chrome",Vector3(x,.75,5.35),.10,.08)
	for x in [-10.25,10.25]:
		_box("roof",Vector3(x,.44,3.9),Vector3(.65,.85,.65),true)
		_box("metal",Vector3(x,.89,3.9),Vector3(.7,.08,.7))

func _build_window_displays() -> void:
	# Produtos em escala real: as janelas comunicam a atividade do estabelecimento.
	for x in [-7.93,-7.15,-6.37]: _display_wheel(Vector3(x,1.59,6.18),.35)
	_box("red",Vector3(-3.8,1.06,6.18),Vector3(2.6,.14,.42))
	for x in [-4.57,-3.8,-3.03]:
		_box("metal",Vector3(x,1.38,6.18),Vector3(.49,.46,.32))
		_box("red",Vector3(x,1.62,6.18),Vector3(.52,.06,.35))
		for dx in [-.15,.15]: _box("chrome",Vector3(x+dx,1.68,6.18),Vector3(.06,.07,.07))
		_box("orange",Vector3(x,1.37,6.003),Vector3(.25,.19,.023))
	for x in [-4.45,-3.8,-3.15]:
		_box("orange",Vector3(x,2.04,6.21),Vector3(.38,.42,.25))
		_box("roof",Vector3(x,2.30,6.21),Vector3(.17,.10,.17))
	_box("chrome",Vector3(-3.8,1.80,6.2),Vector3(2.6,.04,.4))
	_box("red",Vector3(3.45,1.06,6.18),Vector3(2.6,.14,.42))
	for x in [2.7,3.45,4.2]:
		_cylinder("chrome",Vector3(x,1.54,6.18),.28,.12,Vector3(PI*.5,0,0))
		_cylinder("metal",Vector3(x,1.54,6.10),.095,.08,Vector3(PI*.5,0,0))
		_box("red",Vector3(x+.21,1.52,6.06),Vector3(.13,.30,.17))
	for x in [6.0,6.8,7.6]:
		_cylinder("orange",Vector3(x,1.72,6.18),.095,.91)
		_cylinder("chrome",Vector3(x,2.25,6.18),.035,.21)
		for i in 8: _cylinder("metal",Vector3(x,1.4+i*.078,6.18),.14,.025)
	_box("red",Vector3(6.8,1.06,6.18),Vector3(2.6,.14,.42))

func _display_wheel(point: Vector3, radius: float) -> void:
	_cylinder("rubber",point,radius,.20,Vector3(PI*.5,0,0))
	_cylinder("chrome",point+Vector3(0,0,-.11),radius*.71,.026,Vector3(PI*.5,0,0))
	_cylinder("metal",point+Vector3(0,0,-.127),radius*.55,.02,Vector3(PI*.5,0,0))
	for i in 5:
		_angled_box("chrome",point+Vector3(0,0,-.142),Vector3(.035,radius*1.1,.018),i*PI/5.0)
	_cylinder("chrome",point+Vector3(0,0,-.155),radius*.17,.025,Vector3(PI*.5,0,0))

func _build_lighting() -> void:
	for point in [Vector3(-10,0,-11.8),Vector3(9.9,0,.7)]:
		_box("metal",point+Vector3(0,2.55,0),Vector3(.15,5.1,.15),true)
		_box("metal",point+Vector3(0,5.05,0),Vector3(1.1,.16,.42))
		_box("lamp",point+Vector3(0,4.94,0),Vector3(.92,.04,.33))
		_lamps.append(_light_source(point+Vector3(0,4.75,0),12.5,2.4,Color("ffe3ba")))
	for x in [-5.5,4.5]: _box("lamp",Vector3(x,2.71,5),Vector3(2.7,.06,.17))
	_lamps.append(_light_source(Vector3(-.5,2.9,4.8),8,1.6,Color("ffdcab")))
	# Vinte lâmpadas visuais, uma fonte de festa compartilhada, sem sombras adicionais.
	for x in [-9.7,9.7]: _box("metal",Vector3(x,2.5,-2.05),Vector3(.09,5,.09),true)
	for i in 20:
		var x := -9.5+float(i)
		var y := 4.83-.65*(1.0-pow(x/9.5,2))
		_box("metal",Vector3(x,y,-2.05),Vector3(1.03,.025,.025))
		_box("party",Vector3(x,y-.13,-2.05),Vector3(.095,.16,.095))
	_event_lamps.append(_light_source(Vector3(-2,4,-2.1),10,2.0,Color("ffe5bc")))

func _light_source(point: Vector3, reach: float, energy: float, color: Color) -> SpotLight3D:
	# O pool urbano prioriza os postes na rua. Fontes próprias garantem continuidade
	# no pátio; não há registro no pool nem seleção que possa piscar ao mover a câmera.
	var source := SpotLight3D.new()
	source.name = "TorqueLightFitting"
	source.position = point
	# Fachada, postes e cordão têm luminárias voltadas ao chão. Além de conter
	# vazamento lateral, os spots não disputam o teto Omni com postes e neons.
	source.rotation.x = -PI*.5
	source.spot_range = reach
	source.spot_angle = 65.0
	source.spot_attenuation = 1.0
	source.spot_angle_attenuation = .7
	source.light_energy = energy
	source.set_meta("meet_base_energy",energy)
	source.light_color = color
	source.light_specular = .25
	source.shadow_enabled = false
	# A câmera ortográfica pode ficar a mais de 50m embora o pátio esteja em primeiro plano.
	source.distance_fade_enabled = false
	add_child(source)
	return source

func _box(material: String, point: Vector3, size: Vector3, solid := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append_mesh(material,mesh,Transform3D(Basis.IDENTITY,point))
	if solid: _solid(point,size)

func _angled_box(material: String, point: Vector3, size: Vector3, angle: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append_mesh(material,mesh,Transform3D(Basis(Vector3.FORWARD,angle),point))

func _cylinder(material: String, point: Vector3, radius: float, height: float, angles := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	_append_mesh(material,mesh,Transform3D(Basis.from_euler(angles),point))

func _append_mesh(material: String, mesh: Mesh, transform: Transform3D) -> void:
	if not _surfaces.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[material] = surface
	_surfaces[material].append_from(mesh,0,transform)

func _paving_panel(point: Vector3, size: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.name = "TorqueAsphaltPanel"
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.material_override = _materials.asphalt
	add_child(node)

func _solid(point: Vector3, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = point
	_body.add_child(collider)

func _flush_meshes() -> void:
	for key in _surfaces:
		var node := MeshInstance3D.new()
		node.name = "Torque_"+str(key)
		node.mesh = _surfaces[key].commit()
		node.material_override = _materials[key]
		add_child(node)
	_surfaces.clear()
