class_name DanteProductionComparisonModel
extends Node2D

## Reprodução visual exata do Dante Atual em produção (dante_classic de Player.gd)
## Para comparação lado a lado sem instanciar Player.gd (sem dependências de gameplay).

@export var render_scale: Vector2 = Vector2(0.38, 0.38)
@export var facing_angle: float = 0.0

var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_display: Sprite2D
var model_root: Node3D

func _ready() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(128, 128)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport_3d)

	camera_3d = Camera3D.new()
	camera_3d.position = Vector3(0.0, 3.2, 1.4)
	camera_3d.fov = 30.0
	viewport_3d.add_child(camera_3d)
	camera_3d.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, 35.0, 0.0)
	light.light_energy = 1.40
	viewport_3d.add_child(light)

	var env = WorldEnvironment.new()
	var env_res = Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0, 0, 0, 0)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.72, 0.72, 0.82)
	env.environment = env_res
	viewport_3d.add_child(env)

	model_root = Node3D.new()
	viewport_3d.add_child(model_root)

	_build_classic_mesh()

	sprite_display = Sprite2D.new()
	sprite_display.texture = viewport_3d.get_texture()
	sprite_display.scale = render_scale
	add_child(sprite_display)

func _process(_delta: float) -> void:
	if model_root:
		model_root.rotation.y = facing_angle

func _build_classic_mesh() -> void:
	var mat_jacket = _make_mat(Color("121214"), 0.5)
	var mat_pants = _make_mat(Color("18181b"), 0.6)
	var mat_skin = _make_mat(Color(0.86, 0.70, 0.56), 0.5)
	var mat_hair = _make_mat(Color(0.08, 0.08, 0.10), 0.8)
	var mat_head = _make_mat(Color("1a1a1e"), 0.4)
	var mat_shoes = _make_mat(Color(0.06, 0.06, 0.08), 0.3)
	var mat_dark_shades = _make_mat(Color(0.05, 0.05, 0.07), 0.1)
	var mat_silver = _make_mat(Color(0.85, 0.88, 0.92), 0.2)
	var mat_white = _make_mat(Color(0.98, 0.98, 1.0), 0.3)

	# Sombra
	var shadow_mesh = MeshInstance3D.new()
	var cyl_s = CylinderMesh.new()
	cyl_s.top_radius = 0.28
	cyl_s.bottom_radius = 0.28
	cyl_s.height = 0.01
	shadow_mesh.mesh = cyl_s
	var shadow_mat = StandardMaterial3D.new()
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.02, 0.02, 0.05, 0.50)
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mesh.material_override = shadow_mat
	shadow_mesh.position = Vector3(0.0, 0.01, 0.0)
	model_root.add_child(shadow_mesh)

	# Torso
	var torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	model_root.add_child(torso_node)

	var neck = MeshInstance3D.new()
	var cyl_nk = CylinderMesh.new()
	cyl_nk.top_radius = 0.09
	cyl_nk.bottom_radius = 0.10
	cyl_nk.height = 0.14
	neck.mesh = cyl_nk
	neck.material_override = mat_skin
	neck.position = Vector3(0.0, 0.26, 0.0)
	torso_node.add_child(neck)

	var torso_mesh = MeshInstance3D.new()
	var cap_t = CapsuleMesh.new()
	cap_t.radius = 0.175
	cap_t.height = 0.48
	torso_mesh.mesh = cap_t
	torso_mesh.material_override = mat_jacket
	torso_node.add_child(torso_mesh)

	# Lapelas
	for side in [-1, 1]:
		var lapel = MeshInstance3D.new()
		var box_l = BoxMesh.new()
		box_l.size = Vector3(0.045, 0.28, 0.02)
		lapel.mesh = box_l
		lapel.material_override = mat_jacket
		lapel.position = Vector3(float(side) * 0.06, 0.05, -0.175)
		lapel.rotation_degrees = Vector3(0, 0, float(side) * 8)
		torso_node.add_child(lapel)

	# Zíper
	var zipper = MeshInstance3D.new()
	var box_z = BoxMesh.new()
	box_z.size = Vector3(0.02, 0.34, 0.02)
	zipper.mesh = box_z
	zipper.material_override = mat_silver
	zipper.position = Vector3(0.0, 0.05, -0.175)
	torso_node.add_child(zipper)

	# Cinto
	var belt = MeshInstance3D.new()
	var box_b = BoxMesh.new()
	box_b.size = Vector3(0.35, 0.045, 0.33)
	belt.mesh = box_b
	belt.material_override = _make_mat(Color("0d0d10"), 0.4)
	belt.position = Vector3(0.0, -0.18, 0.0)
	torso_node.add_child(belt)

	var buckle = MeshInstance3D.new()
	var box_bk = BoxMesh.new()
	box_bk.size = Vector3(0.06, 0.05, 0.025)
	buckle.mesh = box_bk
	buckle.material_override = mat_silver
	buckle.position = Vector3(0.0, -0.18, -0.172)
	torso_node.add_child(buckle)

	# Cabeça com boné e óculos escuros (shades + cap)
	var head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.25, 0.0)
	model_root.add_child(head_node)

	var head_mesh = MeshInstance3D.new()
	var sph_h = SphereMesh.new()
	sph_h.radius = 0.17
	sph_h.height = 0.32
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	# Boné preto
	var cap_body = MeshInstance3D.new()
	var sph_cp = SphereMesh.new()
	sph_cp.radius = 0.185
	sph_cp.height = 0.22
	cap_body.mesh = sph_cp
	cap_body.material_override = mat_head
	cap_body.position = Vector3(0.0, 0.08, -0.01)
	head_node.add_child(cap_body)

	var cap_brim = MeshInstance3D.new()
	var box_br = BoxMesh.new()
	box_br.size = Vector3(0.24, 0.020, 0.16)
	cap_brim.mesh = box_br
	cap_brim.material_override = mat_head
	cap_brim.position = Vector3(0.0, 0.07, -0.19)
	cap_brim.rotation_degrees = Vector3(12, 0, 0)
	head_node.add_child(cap_brim)

	# Óculos escuros
	for side in [-1, 1]:
		var lens = MeshInstance3D.new()
		var box_ls = BoxMesh.new()
		box_ls.size = Vector3(0.048, 0.028, 0.012)
		lens.mesh = box_ls
		lens.material_override = mat_dark_shades
		lens.position = Vector3(float(side) * 0.060, 0.038, -0.182)
		head_node.add_child(lens)

	var g_bridge = MeshInstance3D.new()
	var box_gb = BoxMesh.new()
	box_gb.size = Vector3(0.035, 0.006, 0.010)
	g_bridge.mesh = box_gb
	g_bridge.material_override = mat_silver
	g_bridge.position = Vector3(0.0, 0.042, -0.184)
	head_node.add_child(g_bridge)

	# Cabelo traseiro
	var hair_back = MeshInstance3D.new()
	var box_hb = BoxMesh.new()
	box_hb.size = Vector3(0.24, 0.30, 0.10)
	hair_back.mesh = box_hb
	hair_back.material_override = mat_hair
	hair_back.position = Vector3(0.0, -0.06, 0.12)
	head_node.add_child(hair_back)

	# Braços
	for side in [-1, 1]:
		var uarm = MeshInstance3D.new()
		var cap_ua = CapsuleMesh.new()
		cap_ua.radius = 0.050
		cap_ua.height = 0.22
		uarm.mesh = cap_ua
		uarm.material_override = mat_jacket
		uarm.position = Vector3(float(side) * 0.24, 0.94, 0.0)
		model_root.add_child(uarm)

		var larm = MeshInstance3D.new()
		var cap_la = CapsuleMesh.new()
		cap_la.radius = 0.042
		cap_la.height = 0.18
		larm.mesh = cap_la
		larm.material_override = mat_jacket
		larm.position = Vector3(float(side) * 0.24, 0.72, 0.0)
		model_root.add_child(larm)

		# Luvas
		var glv = MeshInstance3D.new()
		var box_gl = BoxMesh.new()
		box_gl.size = Vector3(0.05, 0.06, 0.06)
		glv.mesh = box_gl
		glv.material_override = mat_head
		glv.position = Vector3(float(side) * 0.24, 0.55, 0.0)
		model_root.add_child(glv)

	# Pernas cargo e tênis
	for side in [-1, 1]:
		var uleg = MeshInstance3D.new()
		var cap_ul = CapsuleMesh.new()
		cap_ul.radius = 0.065
		cap_ul.height = 0.30
		uleg.mesh = cap_ul
		uleg.material_override = mat_pants
		uleg.position = Vector3(float(side) * 0.10, 0.50, 0.0)
		model_root.add_child(uleg)

		var lleg = MeshInstance3D.new()
		var cap_ll = CapsuleMesh.new()
		cap_ll.radius = 0.055
		cap_ll.height = 0.28
		lleg.mesh = cap_ll
		lleg.material_override = mat_pants
		lleg.position = Vector3(float(side) * 0.10, 0.25, 0.0)
		model_root.add_child(lleg)

		var shoe = MeshInstance3D.new()
		var box_sh = BoxMesh.new()
		box_sh.size = Vector3(0.08, 0.08, 0.14)
		shoe.mesh = box_sh
		shoe.material_override = mat_shoes
		shoe.position = Vector3(float(side) * 0.10, 0.05, -0.02)
		model_root.add_child(shoe)

func _make_mat(albedo: Color, roughness: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	return mat
