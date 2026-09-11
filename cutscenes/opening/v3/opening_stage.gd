extends Node3D
## Palco cinematográfico independente: animação determinística, sem física do mundo.
## A mesma textura da fotografia acompanha Dante em todas as cenas.
const Rig = preload("res://scripts/player/DantePreviewRig.gd")
const Adapter = preload("res://scripts/player/DanteVisualAdapter.gd")
const PHOTO = preload("res://cutscenes/opening/v3/assets/brothers_photo.png")
var camera: Camera3D
var environment: Environment
var room: Node3D
var road: Node3D
var cabin: Node3D
var terminal: Node3D
var actor: Node3D
var host: CharacterBody2D
var key: DirectionalLight3D
var fill: DirectionalLight3D
var practical: OmniLight3D
var passing: OmniLight3D
var mug: Node3D
var pot: Node3D
var pour: Node3D
var coffee: RefCounted
var steam: Array[MeshInstance3D] = []
var phone: Node3D
var phone_gallery: MeshInstance3D
var screen: StandardMaterial3D
var phone_label: Label3D
var frame_photo: MeshInstance3D
var loose_photo: Node3D
var lid: Node3D
var backpack: Node3D
var flap: Node3D
var door: Node3D
var bus: Node3D
var terminal_bus: Node3D
var lamps: Array[Node3D] = []
var rain: MultiMeshInstance3D
var glass_material: ShaderMaterial
var lip: MeshInstance3D
var eyes: Array[Node3D] = []
var brows: Array[Node3D] = []
var pupils: Array[Node3D] = []
var clock_time := 0.0
var voice_envelope := 0.0
var lang := "pt"
var _wood: StandardMaterial3D
var _metal: StandardMaterial3D
var _dark: StandardMaterial3D
var window_key: SpotLight3D
var eye_scales: Dictionary={}
var lip_scale:=Vector3.ONE
var road_wheels: RefCounted
var terminal_wheels: RefCounted
var photo_frame: Node3D
var hands: Array[Node3D] = []
var palms: Array[Node3D] = []
var performance: RefCounted

func _ready() -> void:
	physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	_wood = mat("584333", .86)
	var grain:=NoiseTexture2D.new(); var wood_noise:=FastNoiseLite.new()
	wood_noise.frequency=.07; wood_noise.fractal_octaves=4
	grain.noise=wood_noise; grain.width=256; grain.height=256
	var colors:=Gradient.new(); colors.set_color(0,Color("32251b")); colors.set_color(1,Color("927356"))
	grain.color_ramp=colors
	_wood.albedo_color=Color.WHITE; _wood.albedo_texture=grain
	_wood.uv1_scale=Vector3(3,24,3)
	_metal = mat("55575b", .40, .65)
	_dark = mat("151b24", .86)
	_build_environment()
	room = Node3D.new(); add_child(room)
	road = Node3D.new(); add_child(road)
	cabin = Node3D.new(); add_child(cabin)
	terminal = Node3D.new(); add_child(terminal)
	_build_room()
	_build_actor()
	performance=preload("res://cutscenes/opening/v3/opening_performance.gd").new(self)
	_build_road()
	_build_cabin()
	_build_terminal()
	_build_rain()
	set_time(0.0)

func _exit_tree() -> void:
	if is_instance_valid(host): host.free()

func mat(hex: String, rough := .8, metal := 0.0, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex); m.roughness = rough; m.metallic = metal
	if emission > 0:
		m.emission_enabled = true; m.emission = Color(hex); m.emission_energy_multiplier = emission
	return m

func box(parent: Node3D, pos: Vector3, dims: Vector3, material: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new(); var mesh := BoxMesh.new()
	mesh.size = dims; n.mesh = mesh; n.material_override = material; n.position = pos
	parent.add_child(n); return n

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material, top := -1.0) -> MeshInstance3D:
	var n := MeshInstance3D.new(); var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top < 0 else top; mesh.bottom_radius = radius
	mesh.height = height; mesh.radial_segments = 24; n.mesh = mesh
	n.material_override = material; n.position = pos; parent.add_child(n); return n

func sphere(parent: Node3D, pos: Vector3, dims: Vector3, material: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new(); var mesh := SphereMesh.new()
	mesh.radius = .5; mesh.height = 1; mesh.radial_segments = 20; mesh.rings = 10
	n.mesh = mesh; n.material_override = material; n.position = pos; n.scale = dims
	parent.add_child(n); return n

func quad(parent: Node3D, pos: Vector3, dims: Vector2, material: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new(); var mesh := QuadMesh.new(); mesh.size = dims
	n.mesh = mesh; n.material_override = material; n.position = pos; n.rotation.y = PI
	parent.add_child(n); return n

func _build_environment() -> void:
	var world_env := WorldEnvironment.new(); environment = Environment.new(); world_env.environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("151d2b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9aa9c0"); environment.ambient_light_energy = .18
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world_env)
	key = DirectionalLight3D.new(); key.rotation_degrees = Vector3(-38,-38,0)
	key.light_color = Color("ffdbac"); key.light_energy = 1.5
	key.shadow_enabled = true; key.directional_shadow_max_distance = 65; add_child(key)
	fill = DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-18,155,0)
	fill.light_color = Color("a9c8f1"); fill.light_energy = .65; add_child(fill)
	practical = OmniLight3D.new(); practical.light_color = Color("ffc989")
	practical.omni_range = 4; practical.light_energy = .65; practical.position = Vector3(1.35,1.25,.5); add_child(practical)
	passing = OmniLight3D.new(); passing.light_color = Color("ffd19a")
	passing.omni_range = 4; add_child(passing)
	window_key=SpotLight3D.new(); add_child(window_key)
	window_key.position=Vector3(-1.7,2.1,-1.2); window_key.look_at(Vector3(0,.8,0))
	window_key.light_color=Color("ffdfac"); window_key.light_energy=4
	window_key.spot_range=7; window_key.spot_angle=56; window_key.shadow_enabled=true
	camera = Camera3D.new(); camera.fov = 34; camera.near = .035; camera.far = 150; add_child(camera)
	camera.make_current()

func _photo_material() -> StandardMaterial3D:
	var m := mat("ffffff", .95)
	m.albedo_texture = PHOTO; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _build_room() -> void:
	var plaster := mat("b6a28b",.97)
	# A câmera vê um apartamento completo, com janelas reais entre pilares.
	box(room,Vector3(0,-.055,0),Vector3(6,.10,7),_wood)
	for x in 24:
		box(room,Vector3(-2.95+x*.25,.001,0),Vector3(.008,.006,7),mat("342e29"))
	# Vão real da saída, com corredor atrás; o ator não atravessa a parede.
	box(room,Vector3(-.76,1.5,1.4),Vector3(4.48,3,.12),plaster)
	box(room,Vector3(2.63,1.5,1.4),Vector3(.74,3,.12),plaster)
	box(room,Vector3(1.87,2.5,1.4),Vector3(.78,1,.12),plaster)
	box(room,Vector3(2.8,1.5,-.7),Vector3(.12,3,4.3),plaster)
	box(room,Vector3(-2.35,.37,-.2),Vector3(.12,.74,3.3),plaster)
	box(room,Vector3(-2.35,2.6,-.2),Vector3(.12,.8,3.3),plaster)
	for z in [-1.8,.1,1.35]: box(room,Vector3(-2.35,1.55,z),Vector3(.16,1.7,.10),_wood)
	box(room,Vector3(-2.25,.77,-.2),Vector3(.30,.07,3.2),mat("ddd0b9"))
	for z in [-1.2,-.4,.4]:
		box(room,Vector3(-3.5,1.2,z-1),Vector3(.9,2.4,.7),mat("6d7580"))
		for y in [.7,1.3,1.9]: box(room,Vector3(-3.02,y,z-1),Vector3(.012,.22,.2),mat("a5afaf"))
	# Cozinha ao fundo, puxadores e rejuntes em escala discreta.
	var cabinet := mat("5c5147")
	for x in [-1.65,-.95,-.25]:
		box(room,Vector3(x,.42,1.05),Vector3(.67,.82,.50),cabinet)
		box(room,Vector3(x,.82,1.0),Vector3(.71,.045,.65),mat("b3a797"))
		box(room,Vector3(x,.62,.782),Vector3(.19,.018,.025),_metal)
		box(room,Vector3(x,1.91,1.1),Vector3(.65,.7,.37),cabinet)
		box(room,Vector3(x+.22,1.84,.9),Vector3(.012,.12,.025),_metal)
	for x in 15:
		for y in 3: box(room,Vector3(-2+x*.14,1.0+y*.16,1.322),Vector3(.135,.155,.012),mat("c0b39b"))
	box(room,Vector3(.6,.88,1.03),Vector3(.66,1.76,.60),mat("b0b0a5",.5))
	box(room,Vector3(.83,1.08,.711),Vector3(.023,.32,.037),_metal)
	box(room,Vector3(.6,1.25,.72),Vector3(.62,.018,.008),_dark)
	# Mesa e cadeira com proporção consistente ao personagem do jogo.
	box(room,Vector3(0,.62,-.56),Vector3(1.62,.065,.83),_wood)
	for x in [-.65,.65]:
		for z in [-.85,-.28]: box(room,Vector3(x,.30,z),Vector3(.055,.6,.055),_wood)
	box(room,Vector3(0,.39,.08),Vector3(.45,.05,.40),_wood)
	box(room,Vector3(0,.69,.27),Vector3(.45,.58,.035),_wood)
	for x in [-.17,.17]:
		for z in [-.08,.23]: box(room,Vector3(x,.2,z),Vector3(.035,.4,.035),_wood)
	# Porta-retrato: moldura física, vidro discreto e uma só fotografia.
	var frame := Node3D.new(); frame.position=Vector3(-.29,.66,-.32); room.add_child(frame)
	photo_frame=frame
	var brass := mat("9c8060",.5,.2)
	box(frame,Vector3(0,.118,0),Vector3(.280,.203,.022),brass)
	box(frame,Vector3(0,.118,-.014),Vector3(.254,.179,.009),mat("857764"))
	loose_photo=Node3D.new(); add_child(loose_photo)
	frame_photo=quad(loose_photo,Vector3.ZERO,Vector2(.230,.153),_photo_material())
	# Caixa: a farda é guardada, a foto fica fora.
	var cardboard:=mat("756653")
	box(room,Vector3(-.62,.73,-.25),Vector3(.36,.16,.24),cardboard)
	box(room,Vector3(-.62,.818,-.25),Vector3(.31,.025,.2),mat("17283d"))
	box(room,Vector3(-.68,.835,-.255),Vector3(.035,.008,.036),brass)
	lid=Node3D.new(); lid.position=Vector3(-.62,.824,-.125); room.add_child(lid)
	box(lid,Vector3(0,0,-.13),Vector3(.38,.022,.27),cardboard)
	_build_cup()
	_build_phone()
	_build_bag()
	# Abajur acende durante a elipse.
	cylinder(room,Vector3(1.35,.38,.5),.05,.76,_metal)
	cylinder(room,Vector3(1.35,.85,.5),.22,.30,mat("d6b77c",.85),.13)
	# Porta de saída vista no plano do porta-retrato vazio.
	box(room,Vector3(1.88,1.0,2.6),Vector3(1.1,2.0,.08),_dark)
	door=Node3D.new(); door.position=Vector3(1.48,0,1.20); room.add_child(door)
	box(door,Vector3(.39,1,0),Vector3(.78,2,.045),mat("534532"))
	sphere(door,Vector3(.68,1,-.05),Vector3(.055,.035,.055),brass)

func _build_cup() -> void:
	mug=Node3D.new(); room.add_child(mug)
	var ceramic:=mat("b7afa0",.28)
	cylinder(mug,Vector3(0,.059,0),.045,.115,ceramic)
	cylinder(mug,Vector3(0,.118,0),.040,.004,mat("281d13",.24))
	var handle:=MeshInstance3D.new(); var torus:=TorusMesh.new()
	torus.inner_radius=.017; torus.outer_radius=.029
	handle.mesh=torus; handle.material_override=ceramic
	handle.rotation.x=PI/2; handle.position=Vector3(.046,.064,0); mug.add_child(handle)
	pot=Node3D.new(); room.add_child(pot)
	coffee=preload("res://cutscenes/opening/v3/opening_coffee.gd").new(self)
	var vapor_shader:=Shader.new()
	vapor_shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
void fragment(){vec2 p=(UV-.5)*2.0; ALBEDO=vec3(.83,.81,.77); ALPHA=exp(-dot(p,p)*4.5)*.035;}"""
	var vapor:=ShaderMaterial.new(); vapor.shader=vapor_shader
	for i in 9: steam.append(quad(room,Vector3.ZERO,Vector2(1,1),vapor))

func _build_phone() -> void:
	phone=Node3D.new(); add_child(phone)
	box(phone,Vector3.ZERO,Vector3(.060,.123,.018),mat("171c23",.32))
	screen=mat("a1b7b0",.55,0,.4)
	quad(phone,Vector3(0,.024,-.010),Vector2(.049,.052),screen)
	phone_gallery=quad(phone,Vector3(0,.024,-.0115),Vector2(.047,.0313),_photo_material())
	phone_gallery.hide()
	# Base inclinada mantém o telefone ao alcance e espaço para a pegada lateral.
	box(room,Vector3(.34,.660,-.20),Vector3(.095,.014,.075),_dark)
	cylinder(room,Vector3(.34,.697,-.188),.008,.073,_metal)
	var cradle:=box(room,Vector3(.34,.743,-.180),Vector3(.066,.100,.010),_dark)
	cradle.rotation.x=PI/3
	for y in 4:
		for x in 3: box(phone,Vector3((x-1)*.015,-.018-y*.016,-.010),Vector3(.012,.009,.003),mat("63696a",.6))
	phone_label=Label3D.new(); phone_label.font_size=32; phone_label.pixel_size=.00022
	phone_label.position=Vector3(0,.025,-.012); phone_label.rotation.y=PI
	phone_label.modulate=Color("14221e"); phone_label.outline_size=0; phone.add_child(phone_label)

func _build_bag() -> void:
	backpack=Node3D.new(); add_child(backpack)
	var canvas:=mat("635640",.96)
	# Interior aberto: o papel entra e fica oculto pelas paredes, sem hide() por tempo.
	var front:=box(backpack,Vector3(0,.175,-.083),Vector3(.36,.35,.026),canvas)
	front.mesh=_rounded_panel(Vector3(.36,.35,.026))
	var back:=box(backpack,Vector3(0,.175,.083),Vector3(.36,.35,.026),canvas)
	back.mesh=_rounded_panel(Vector3(.36,.35,.026))
	for side in [-1,1]:
		sphere(backpack,Vector3(side*.17,.17,0),Vector3(.035,.35,.17),canvas)
	box(backpack,Vector3(0,.015,0),Vector3(.34,.03,.17),canvas)
	box(backpack,Vector3(0,.105,-.109),Vector3(.27,.15,.028),canvas)
	var handle:=MeshInstance3D.new(); var loop:=TorusMesh.new()
	loop.inner_radius=.030; loop.outer_radius=.042; handle.mesh=loop
	handle.material_override=canvas; handle.rotation.x=PI/2
	handle.position=Vector3(0,.355,.038); backpack.add_child(handle)
	for s in [-1,1]:
		box(backpack,Vector3(s*.08,.23,.10),Vector3(.035,.31,.025),mat("302a21"))
		box(backpack,Vector3(s*.065,.10,-.123),Vector3(.017,.035,.008),_metal)
	flap=Node3D.new(); flap.position=Vector3(0,.36,.055); backpack.add_child(flap)
	sphere(flap,Vector3(0,-.015,-.055),Vector3(.38,.045,.20),canvas)

func _build_actor() -> void:
	actor=Node3D.new(); add_child(actor)
	host=Rig.new(); host.model_root=actor
	actor.add_child(Node3D.new())
	host.build("dante_classic")
	host.mat_black_jacket.albedo_color=Color(.72,.72,.72)
	# Gola em V e cantos suaves evitam blocos aparentes nos planos próximos.
	for part in host.torso_node.get_children():
		if part is MeshInstance3D and part.mesh is BoxMesh:
			var size: Vector3=part.mesh.size
			if size.is_equal_approx(Vector3(.040,.060,.02)):
				var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				for point in [Vector3(-.020,.030,-.011),Vector3(0,-.024,-.011),Vector3(.020,.030,-.011)]:
					surface.set_normal(Vector3.FORWARD); surface.add_vertex(point)
				part.mesh=surface.commit()
			else:
				part.mesh=_rounded_panel(size)
	for lower in [host.left_lower_arm,host.right_lower_arm]:
		var palm: Node3D=lower.get_node("Palm")
		# Antebraço e carpo com comprimento suficiente para dobrar sob o ombro.
		for part in lower.get_children():
			if part is MeshInstance3D:
				part.position.y*=1.2; part.scale.y*=1.2
		palm.position.y=-.24
		var skin: StandardMaterial3D=palm.get_child(0).material_override
		for child in palm.get_children(): child.hide()
		var hand:=preload("res://cutscenes/opening/v3/opening_hand.gd").new()
		palm.add_child(hand); hand.build(-1.0 if lower==host.left_lower_arm else 1.0,skin)
		hands.append(hand); palms.append(palm)
	for child in host.head_node.get_children():
		if child is MeshInstance3D:
			if absf(child.position.y-.019)<.001:
				child.scale.y*=.65; child.scale.z*=.72
			if absf(child.position.y-.020)<.001: child.scale.y*=.55
			if child.name=="ShortBeard":
				var beard_mat: StandardMaterial3D=child.material_override.duplicate()
				beard_mat.albedo_color=Color("30251f"); child.material_override=beard_mat
			eye_scales[child]=child.scale
			if absf(child.position.y-.019)<.001:
				eyes.append(child)
				if child.position.z<-.093: pupils.append(child)
			if absf(child.position.y-.039)<.001: brows.append(child)
			if absf(child.position.y+.065)<.001: lip=child; lip_scale=child.scale

func _rounded_panel(size: Vector3) -> ArrayMesh:
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x:=size.x*.5; var y:=size.y*.5; var z:=size.z*.5
	var bevel:=minf(x,y)*.17
	var outline: Array[Vector2]=[Vector2(-x+bevel,-y),Vector2(x-bevel,-y),Vector2(x,-y+bevel),Vector2(x,y-bevel),Vector2(x-bevel,y),Vector2(-x+bevel,y),Vector2(-x,y-bevel),Vector2(-x,-y+bevel)]
	for i in outline.size():
		var a:=outline[i]; var b:=outline[(i+1)%outline.size()]
		for point in [Vector3(0,0,-z),Vector3(a.x,a.y,-z),Vector3(b.x,b.y,-z),Vector3(0,0,z),Vector3(b.x,b.y,z),Vector3(a.x,a.y,z),Vector3(a.x,a.y,-z),Vector3(b.x,b.y,z),Vector3(b.x,b.y,-z),Vector3(a.x,a.y,-z),Vector3(a.x,a.y,z),Vector3(b.x,b.y,z)]:
			surface.set_uv(Vector2(point.x/size.x+.5,.5-point.y/size.y)); surface.add_vertex(point)
	surface.generate_normals(); return surface.commit()

func _build_road() -> void:
	var asphalt:=mat("1b2635",.24,.15)
	box(road,Vector3(0,-.035,0),Vector3(12,.06,110),asphalt)
	var marking:=mat("b8b4a2",.7)
	for i in 32: box(road,Vector3(0,.003,-52+i*3.3),Vector3(.10,.008,1.4),marking)
	for x in [-4.2,4.2]: box(road,Vector3(x,.005,0),Vector3(.09,.008,110),marking)
	for s in [-1,1]:
		box(road,Vector3(s*4.9,.45,0),Vector3(.07,.20,110),_metal)
		for i in 14:
			box(road,Vector3(s*5.0,.22,-48+i*8),Vector3(.10,.6,.10),_metal)
			var hill:=sphere(road,Vector3(s*(10+i%3*3),-.8,-55+i*9),Vector3(14,4+i%4,15),mat("293442"))
			hill.rotation.y=float(i)
	bus=preload("res://world/harbor/HarborTransitBusModel.gd").new(); road.add_child(bus)
	road_wheels=preload("res://prototypes/living_cast/VehicleWheelRig.gd").new(); road_wheels.mount(bus)
	for s in [-.85,.85]:
		var headlamp:=SpotLight3D.new(); bus.add_child(headlamp)
		headlamp.position=Vector3(s,.83,-4.9); headlamp.light_color=Color("e9e3c7")
		headlamp.light_energy=3; headlamp.spot_range=28; headlamp.spot_angle=33

func _build_cabin() -> void:
	var upholstery:=mat("283e55",.97)
	box(cabin,Vector3(0,-.04,0),Vector3(2.5,.08,9),_dark)
	box(cabin,Vector3(0,1.8,0),Vector3(2.5,.07,9),mat("a3a5a0"))
	for z in [-3.5,-2.4,.15,1.3,2.4,3.5]:
		for x in [-.58,.62]:
			box(cabin,Vector3(x,.40,z),Vector3(.52,.12,.48),upholstery)
			var seat:=box(cabin,Vector3(x,.75,z+.24),Vector3(.52,.66,.10),upholstery)
			seat.rotation.x=-.09
			box(cabin,Vector3(x,.36,z),Vector3(.07,.65,.07),_metal)
		box(cabin,Vector3(-1.18,1.0,z+.52),Vector3(.06,1.5,.055),mat("8b939c"))
	box(cabin,Vector3(-1.22,.39,0),Vector3(.06,.8,9),mat("485565"))
	box(cabin,Vector3(-1.18,.77,0),Vector3(.14,.06,9),mat("626b6d"))
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float age = 0.0;
void fragment(){
 vec2 p=UV*vec2(35.0,8.0);
 float col=floor(p.x); float speed=.35+fract(sin(col*43.7)*125.8)*.4;
 vec2 q=vec2(fract(p.x)-.5,fract(p.y+age*speed+sin(col*34.0))-.5);
 float drop=exp(-q.x*q.x*330.0-q.y*q.y*23.0);
 float glow=pow(max(0.0,sin(UV.x*10.0-age*1.9)),24.0);
 ALBEDO=mix(vec3(.22,.35,.51),vec3(.88,.63,.30),glow);
 ALPHA=.09+drop*.30+glow*.15;
}"""
	glass_material=ShaderMaterial.new(); glass_material.shader=shader
	var pane:=quad(cabin,Vector3(-1.20,1.18,0),Vector2(8.8,.8),glass_material); pane.rotation.y=PI/2
	for i in 12:
		var p:=Node3D.new(); p.position=Vector3(-2.4,0,-6+i); cabin.add_child(p); lamps.append(p)
		box(p,Vector3(0,1,0),Vector3(.065,2,.065),_metal)
		box(p,Vector3(0,1.8,0),Vector3(.14,.08,.10),mat("ffc780",.5,0,1.5))
		box(p,Vector3(-1.7,.8,0),Vector3(1.4,1.6,.65),mat("202f42"))

func _build_terminal() -> void:
	box(terminal,Vector3(0,-.04,0),Vector3(45,.08,38),mat("283342",.23,.15))
	box(terminal,Vector3(-4,.12,0),Vector3(3,.24,25),mat("59616b",.6))
	box(terminal,Vector3(-4,3,0),Vector3(4.8,.2,26),mat("333f4e"))
	for z in [-11,-6,-1,4,9]:
		box(terminal,Vector3(-4.7,1.5,z),Vector3(.17,3,.17),_metal)
		box(terminal,Vector3(-4,2.87,z),Vector3(1,.025,.13),mat("ffe3ac",.5,0,1.5))
		box(terminal,Vector3(-4.3,.55,z+1),Vector3(.48,.075,1.6),_wood)
		box(terminal,Vector3(-4.6,.8,z+1),Vector3(.05,.48,1.6),_wood)
		var lamp:=OmniLight3D.new(); terminal.add_child(lamp)
		lamp.position=Vector3(-3.6,2.5,z); lamp.omni_range=5
		lamp.light_color=Color("ffdaa0"); lamp.light_energy=.55
	for i in 10:
		var h:=3.0+float(i%4)*1.2
		box(terminal,Vector3(-14+i*3.4,h/2,16),Vector3(3,h,3),mat("344250"))
		for y in 3: box(terminal,Vector3(-14+i*3.4,.8+y*1.1,14.48),Vector3(.45,.6,.01),mat("9b9176",.7,0,.1))
	for z in range(-10,12,3): box(terminal,Vector3(-1.9,.01,z),Vector3(.08,.01,1.4),mat("c0aa73"))
	terminal_bus=preload("res://world/harbor/HarborTransitBusModel.gd").new(); terminal.add_child(terminal_bus)
	terminal_wheels=preload("res://prototypes/living_cast/VehicleWheelRig.gd").new(); terminal_wheels.mount(terminal_bus)
	for s in [-.85,.85]:
		var headlamp:=SpotLight3D.new(); terminal_bus.add_child(headlamp)
		headlamp.position=Vector3(s,.83,-4.9); headlamp.light_color=Color("e9e3c7")
		headlamp.light_energy=2.5; headlamp.spot_range=18; headlamp.spot_angle=35

func _build_rain() -> void:
	rain=MultiMeshInstance3D.new(); var multi:=MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D; var mesh:=BoxMesh.new(); mesh.size=Vector3(.009,.23,.009)
	multi.mesh=mesh; multi.instance_count=600
	var rng:=RandomNumberGenerator.new(); rng.seed=11926
	for i in 600:
		multi.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3(rng.randf_range(-14,14),rng.randf_range(0,12),rng.randf_range(-24,24))))
	rain.multimesh=multi; rain.material_override=mat("586879",.7); add_child(rain)

func blend(t: float, from: float, to: float) -> float:
	return smoothstep(from,to,t)

func _arm(upper: Node3D, lower: Node3D, target: Vector3, hint: Vector3, forearm := .20) -> void:
	# IK em espaço do ator: mantém cotovelo, punho e objeto unidos durante a ação.
	var origin:=upper.position
	var delta:=target-origin; var dist:=clampf(delta.length(),absf(.22-forearm)+.002,.22+forearm-.003)
	var direction:=delta.normalized()
	var bend:=(hint-direction*hint.dot(direction)).normalized()
	var along:=(.22*.22-forearm*forearm+dist*dist)/(2*dist)
	var elbow:=origin+direction*along+bend*sqrt(maxf(0,.22*.22-along*along))
	upper.basis=Basis(Quaternion(Vector3.DOWN,(elbow-origin).normalized()))
	lower.basis=upper.basis.inverse()*Basis(Quaternion(Vector3.DOWN,(target-elbow).normalized()))

func _camera(pos: Vector3, target: Vector3, fov: float) -> void:
	camera.position=pos; camera.look_at(target); camera.fov=fov

func set_time(t: float, mouth := 0.0) -> void:
	clock_time=t; voice_envelope=mouth
	t=preload("res://cutscenes/opening/v3/opening_timeline.gd").stage_time(t)
	room.visible=t<46; road.visible=t>=46 and t<53
	cabin.visible=t>=53 and t<61; terminal.visible=t>=61
	actor.visible=t<42 or (t>=53 and t<61)
	rain.visible=t>=46 and not cabin.visible
	var night:=blend(t,38,43)
	key.light_energy=lerpf(.85,.16,night); fill.light_energy=lerpf(.28,.18,night)
	key.light_color=Color("ffdbac").lerp(Color("98b6d7"),night)
	practical.light_energy=lerpf(.25,1.05,night) if room.visible else 0
	environment.ambient_light_energy=lerpf(.20,.085,night) if room.visible else .24
	window_key.light_energy=lerpf(2.3,.10,night) if room.visible else (.8 if cabin.visible else 0.0)
	environment.background_color=Color("141e30")
	passing.light_energy=0
	rain.position=Vector3(0,-fmod(t*7,10),0)
	var breathe:=sin(clock_time*1.6)*.003
	actor.position=Vector3(0,-.14,0); actor.rotation=Vector3.ZERO
	host.torso_node.rotation=Vector3(.02+breathe,0,0)
	host.head_node.rotation=Vector3(-.07,0,0)
	host.left_upper_leg.rotation=Vector3(1.30,0,0); host.right_upper_leg.rotation=Vector3(1.30,0,0)
	host.left_lower_leg.rotation=Vector3(-1.30,0,0); host.right_lower_leg.rotation=Vector3(-1.30,0,0)
	mug.position=Vector3(.17,.657,-.35)
	phone_label.text="IRMÃO" if lang=="pt" else "BROTHER"
	screen.emission_energy_multiplier=.35 if t>=13 else .02
	lid.rotation.x=-.9*(1-blend(t,10.4,11.1))
	door.rotation.y=-.65*(blend(t,42,43)-blend(t,43.8,44.5))
	coffee.apply(t)
	for i in steam.size():
		var age:=fmod(t*.35+i*.11,1.0)
		steam[i].position=mug.position+Vector3(sin(age*5+i)*.012,.12+age*.15,cos(age*4+i)*.012)
		steam[i].scale=Vector3(.025+age*.02,.08,1)
		steam[i].visible=t<18
	# Olhos, sobrancelhas e lábio têm movimentos limitados e motivados.
	var blink:=maxf(0,1-absf(fmod(clock_time+1.9,4.7)-2.1)/.09)
	for eye in eyes: eye.scale.y=Vector3(eye_scales[eye]).y*(1-.92*blink)
	for brow in brows:
		var side:=signf(brow.position.x)
		brow.rotation.z=side*lerpf(.025,.20,blend(t,20.7,23))
		brow.position.y=.039+blend(t,19,21)*.004-blend(t,26,28)*.002
	if is_instance_valid(lip): lip.scale.y=lip_scale.y*(1+mouth*1.8)
	for pupil in pupils: pupil.position.x=signf(pupil.position.x)*.043+sin(t*.7)*.001
	if t<6:
		host.head_node.rotation.x=-.15
		_camera(Vector3(-.55,1.23,-1.68).lerp(Vector3(-.40,1.17,-1.52),t/6),Vector3(.05,.85,-.30),35)
	elif t<13:
		host.head_node.rotation=Vector3(-.10,-.15,0)
		_camera(Vector3(-.69,1.06,-1.31).lerp(Vector3(-.63,.96,-1.14),(t-6)/7),Vector3(-.49,.79,-.32),31)
	elif t<18:
		if t>=16: phone_label.text="CHAMADA" if lang=="pt" else "CALL"
		if t>15 and t<16: screen.emission_energy_multiplier=0
		_camera(Vector3(-.13,1.20,-.86),Vector3(.02,.68,-.32),29)
	elif t<31:
		host.head_node.rotation=Vector3(-.015-blend(t,22,26)*.025,-.05+blend(t,25,28)*.08,0)
		if t<26.6:
			_camera(Vector3(-.57,1.16,-1.38).lerp(Vector3(-.44,1.13,-1.17),(t-18)/8.6),Vector3(0,1.03,-.015),31)
		else:
			_camera(Vector3(-.25,1.11,-.90),Vector3(0,1.055,-.02),30)
	elif t<38:
		phone_label.text=("CHAMANDO" if lang=="pt" else "DIALING") if t<33 else ("SEM RESPOSTA" if lang=="pt" else "NO ANSWER")
		host.head_node.rotation=Vector3(-.20,-.12,0)
		_camera(Vector3(-.50,1.12,-1.50),Vector3(-.08,.89,-.14),37)
	elif t<42:
		host.head_node.rotation.x=-.18
		_camera(Vector3(.86,1.26,-1.02),Vector3(.34,.85,-.14),36)
	elif t<46:
		_camera(Vector3(-.76,.97,-1.31),Vector3(-.38,.79,-.32),36)
	elif t<53:
		var age:=t-46
		bus.position=Vector3(-2.1,.018+sin(age*5)*.012,8-age*2.6)
		bus.rotation.z=sin(age*2)*.002
		for wheel in road_wheels.spinners: wheel.rotation.x=-age*2.6/.5
		_camera(bus.position+Vector3(-9,3.7,-11),bus.position+Vector3(0,1.0,0),43)
		rain.position.z=bus.position.z
	elif t<61:
		var age:=t-53
		actor.position=Vector3(-.58,-.14+sin(age*6)*.002,.12)
		host.head_node.rotation=Vector3(-.20,0,0).lerp(Vector3(-.02,-.45,0),blend(t,57.2,60))
		passing.position=Vector3(-1.65,1.20,-.8+fmod(age*1.3,3))
		passing.light_energy=.45*pow(maxf(0,sin(age*1.8)),3)
		glass_material.set_shader_parameter("age",age)
		for i in lamps.size(): lamps[i].position.z=-6+fmod(float(i)+age*2.3,12)
		_camera(Vector3(.52,1.08,-1.26).lerp(Vector3(.35,1.08,-1.10),age/8),Vector3(-.56,.96,.02),39)
	else:
		var stop:=blend(t,61,65)
		terminal_bus.position=Vector3(0,0,lerpf(10,0,stop))
		terminal_bus.position.y=-.016*sin(blend(t,64.7,65.5)*PI)
		terminal_bus.set_platform_doors(blend(t,66.45,67.5))
		for i in terminal_bus.platform_leaves.size():
			var side:=-1.0 if i==0 else 1.0
			terminal_bus.platform_leaves[i].position.z=-4.05+side*(.30+blend(t,66.45,67.5)*.32)
		for wheel in terminal_wheels.spinners: wheel.rotation.x=-stop*10/.5
		if t<65.8: _camera(Vector3(10,4.7,-12),Vector3(-.6,1.2,1.2),41)
		else: _camera(Vector3(-3.2,1.6,-7.5),Vector3(-1.15,1.35,-4.05),40)
	performance.apply(t)
