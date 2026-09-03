extends CharacterBody2D

const BULLET_SCENE: PackedScene = preload("res://Bullet.tscn")
const WEAPON_CATALOG = preload("res://WeaponCatalog.gd")
const WEAPON_WHEEL_SCRIPT = preload("res://WeaponWheel.gd")

@export var speed: float = 125.0
@export var max_health: int = 100
@export var max_armor: int = 100
@export var fire_interval: float = 0.18
@export var starting_money: int = 3000

@onready var camera = $Camera

var health: int
var armor: int = 0
var fire_cooldown: float = 0.0
var walk_clock: float = 0.0
var is_recovering: bool = false
var is_dead: bool = false
var is_arrested: bool = false
var money: int = 0
var active_weapon_id: String = "pistol"
var weapon_inventory: Dictionary = {"pistol": true, "smg": false, "shotgun": false}
var weapon_ammo: Dictionary = {
	"pistol": {"clip": 12, "reserve": 60},
	"smg": {"clip": 0, "reserve": 0},
	"shotgun": {"clip": 0, "reserve": 0}
}
var weapon_wheel: WeaponWheel
var primary_fire_was_pressed: bool = false

# --- 3D DANTE RIG & VIEWPORT ---
var viewport_3d: SubViewport
var sprite_3d_display: Sprite2D

var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var left_upper_leg: Node3D
var left_lower_leg: Node3D
var right_upper_leg: Node3D
var right_lower_leg: Node3D

var weapon_mount_node: Node3D
var current_gun_mesh: Node3D
var muzzle_flash_3d: MeshInstance3D
var muzzle_light_3d: OmniLight3D
var mat_black_jacket: StandardMaterial3D
var _flamethrower_audio: AudioStreamPlayer2D = null

# --- SISTEMA DE TRAJES & GUARDA-ROUPA ---
var current_outfit_id: String = "dante_classic"
var owned_outfits: Dictionary = {"dante_classic": true}
var clothing_store_ui: ClothingStore = null

func _ready() -> void:
	add_to_group("player")
	z_index = 10
	health = max_health
	
	for child in get_children():
		if child is ColorRect:
			child.hide()

	_build_dante_3d_viewport()
	_setup_weapons()

	var dyn_cam = load("res://DynamicCamera.gd")
	if dyn_cam and camera:
		camera.set_script(dyn_cam)
		camera.set_process(true)
	if camera:
		camera.make_current()

func _build_dante_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(96, 96) # Proporção perfeita 1:1 com os pedestres e carros
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport_3d)

	var cam = Camera3D.new()
	cam.position = Vector3(0.0, 3.2, 1.4)
	cam.fov = 30.0
	viewport_3d.add_child(cam)
	cam.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

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

	# Sombra 3D no chão sob os pés do Dante
	var shadow_mat = StandardMaterial3D.new()
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.02, 0.02, 0.05, 0.50)
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var shadow_mesh = MeshInstance3D.new()
	var cyl_shadow = CylinderMesh.new()
	cyl_shadow.top_radius = 0.28
	cyl_shadow.bottom_radius = 0.28
	cyl_shadow.height = 0.01
	shadow_mesh.mesh = cyl_shadow
	shadow_mesh.material_override = shadow_mat
	shadow_mesh.position = Vector3(0.0, 0.01, 0.0)
	model_root.add_child(shadow_mesh)

	_rebuild_dante_costume()

	# Exibição 2D do Sprite na Escala Exata dos Pedestres
	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.texture = viewport_3d.get_texture()
	sprite_3d_display.scale = Vector2(0.38, 0.38)
	sprite_3d_display.position = Vector2(0.0, 0.0)
	add_child(sprite_3d_display)

func apply_outfit(outfit_id: String) -> void:
	current_outfit_id = outfit_id
	owned_outfits[outfit_id] = true
	_rebuild_dante_costume()

func open_clothing_store() -> void:
	if not clothing_store_ui or not is_instance_valid(clothing_store_ui):
		clothing_store_ui = ClothingStore.new()
		get_tree().root.add_child(clothing_store_ui)
	clothing_store_ui.open_store(self)

func _rebuild_dante_costume() -> void:
	if not model_root:
		return
	
	# Preservar a sombra (primeiro filho) e limpar nós anteriores do corpo
	var children := model_root.get_children()
	for i in range(1, children.size()):
		children[i].queue_free()

	var data := OutfitCatalog.get_outfit(current_outfit_id)
	var col_jacket: Color = data.get("jacket_color", Color("121214"))
	var col_pants: Color = data.get("pants_color", Color("18181b"))
	var col_skin: Color = data.get("skin_color", Color(0.86, 0.70, 0.56))
	var col_hair: Color = data.get("hair_color", Color(0.08, 0.08, 0.10))
	var col_head: Color = data.get("headwear_color", Color("1a1a1e"))
	var col_shoes: Color = data.get("shoes_color", Color(0.06, 0.06, 0.08))
	var col_trim: Color = data.get("trim_color", Color.WHITE)
	var headwear_type: String = data.get("headwear_type", "cap")
	var accessory_type: String = data.get("accessory_type", "shades")

	mat_black_jacket = _make_mat(col_jacket, 0.5)
	var mat_pants = _make_mat(col_pants, 0.6)
	var mat_skin = _make_mat(col_skin, 0.5)
	var mat_hair = _make_mat(col_hair, 0.8)
	var mat_head = _make_mat(col_head, 0.4)
	var mat_shoes = _make_mat(col_shoes, 0.3)
	var mat_trim = _make_mat(col_trim, 0.2)
	var mat_dark_shades = _make_mat(Color(0.05, 0.05, 0.07), 0.1)
	var mat_gold = _make_mat(Color(0.95, 0.80, 0.25), 0.2)
	var mat_silver = _make_mat(Color(0.85, 0.88, 0.92), 0.2)
	var mat_watch = _make_mat(Color(0.08, 0.10, 0.12), 0.18)
	var mat_white = _make_mat(Color(0.98, 0.98, 1.0), 0.3)
	var mat_pupil = _make_mat(Color(0.05, 0.05, 0.05), 0.1)
	var mat_lips = _make_mat(col_skin.darkened(0.20), 0.6)

	# --- PESCOÇO & TORSO ---
	torso_node = Node3D.new()
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
	var cap_torso = CapsuleMesh.new()
	cap_torso.radius = 0.175
	cap_torso.height = 0.48
	torso_mesh.mesh = cap_torso
	torso_mesh.material_override = mat_black_jacket
	torso_node.add_child(torso_mesh)

	# Lapelas / Abertura da Roupa
	var lapel_l = MeshInstance3D.new()
	var box_ll = BoxMesh.new()
	box_ll.size = Vector3(0.045, 0.28, 0.02)
	lapel_l.mesh = box_ll
	lapel_l.material_override = mat_black_jacket
	lapel_l.position = Vector3(-0.06, 0.05, -0.175)
	lapel_l.rotation_degrees = Vector3(0, 0, -8)
	torso_node.add_child(lapel_l)

	var lapel_r = MeshInstance3D.new()
	var box_lr = BoxMesh.new()
	box_lr.size = Vector3(0.045, 0.28, 0.02)
	lapel_r.mesh = box_lr
	lapel_r.material_override = mat_black_jacket
	lapel_r.position = Vector3(0.06, 0.05, -0.175)
	lapel_r.rotation_degrees = Vector3(0, 0, 8)
	torso_node.add_child(lapel_r)

	if accessory_type == "tie_red":
		var shirt = MeshInstance3D.new()
		var box_sh = BoxMesh.new()
		box_sh.size = Vector3(0.08, 0.26, 0.015)
		shirt.mesh = box_sh
		shirt.material_override = mat_white
		shirt.position = Vector3(0.0, 0.06, -0.172)
		torso_node.add_child(shirt)

		var tie_knot = MeshInstance3D.new()
		var box_tk = BoxMesh.new()
		box_tk.size = Vector3(0.04, 0.04, 0.02)
		tie_knot.mesh = box_tk
		tie_knot.material_override = mat_trim
		tie_knot.position = Vector3(0.0, 0.17, -0.18)
		torso_node.add_child(tie_knot)

		var tie = MeshInstance3D.new()
		var box_tie = BoxMesh.new()
		box_tie.size = Vector3(0.038, 0.26, 0.016)
		tie.mesh = box_tie
		tie.material_override = mat_trim
		tie.position = Vector3(0.0, 0.03, -0.182)
		torso_node.add_child(tie)

	elif accessory_type == "scarf_red":
		var scarf_collar = MeshInstance3D.new()
		var cyl_sc = CylinderMesh.new()
		cyl_sc.top_radius = 0.17
		cyl_sc.bottom_radius = 0.19
		cyl_sc.height = 0.08
		scarf_collar.mesh = cyl_sc
		scarf_collar.material_override = mat_trim
		scarf_collar.position = Vector3(0.0, 0.20, 0.0)
		torso_node.add_child(scarf_collar)

		var scarf_knot = MeshInstance3D.new()
		var box_sk = BoxMesh.new()
		box_sk.size = Vector3(0.07, 0.08, 0.05)
		scarf_knot.mesh = box_sk
		scarf_knot.material_override = mat_trim
		scarf_knot.position = Vector3(0.03, 0.16, -0.18)
		torso_node.add_child(scarf_knot)

		var scarf_tail = MeshInstance3D.new()
		var box_st = BoxMesh.new()
		box_st.size = Vector3(0.06, 0.26, 0.025)
		scarf_tail.mesh = box_st
		scarf_tail.material_override = mat_trim
		scarf_tail.position = Vector3(0.03, 0.02, -0.185)
		scarf_tail.rotation_degrees = Vector3(-4, 0, -2)
		torso_node.add_child(scarf_tail)

	elif accessory_type == "fur_hood":
		var fur = MeshInstance3D.new()
		var cyl_fur = CylinderMesh.new()
		cyl_fur.top_radius = 0.21
		cyl_fur.bottom_radius = 0.23
		cyl_fur.height = 0.09
		fur.mesh = cyl_fur
		fur.material_override = mat_trim
		fur.position = Vector3(0.0, 0.20, 0.0)
		torso_node.add_child(fur)

	elif accessory_type == "bandana":
		var bandana = MeshInstance3D.new()
		var box_bn = BoxMesh.new()
		box_bn.size = Vector3(0.12, 0.14, 0.03)
		bandana.mesh = box_bn
		bandana.material_override = mat_trim
		bandana.position = Vector3(0.0, 0.16, -0.16)
		bandana.rotation_degrees = Vector3(-16, 0, 0)
		torso_node.add_child(bandana)

	elif accessory_type == "shoulder_pad":
		var pad = MeshInstance3D.new()
		var sph_p = SphereMesh.new()
		sph_p.radius = 0.09
		pad.mesh = sph_p
		pad.material_override = mat_silver
		pad.scale = Vector3(0.9, 0.6, 1.2)
		pad.position = Vector3(-0.24, 0.20, 0.0)
		torso_node.add_child(pad)

		var strap = MeshInstance3D.new()
		var box_str = BoxMesh.new()
		box_str.size = Vector3(0.04, 0.36, 0.015)
		strap.mesh = box_str
		strap.material_override = _make_mat(Color("2d3436"), 0.4)
		strap.position = Vector3(-0.04, 0.05, -0.176)
		strap.rotation_degrees = Vector3(0, 0, -38)
		torso_node.add_child(strap)

	else:
		var zipper = MeshInstance3D.new()
		var box_z = BoxMesh.new()
		box_z.size = Vector3(0.02, 0.34, 0.02)
		zipper.mesh = box_z
		zipper.material_override = mat_silver
		zipper.position = Vector3(0.0, 0.05, -0.175)
		torso_node.add_child(zipper)

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
	buckle.material_override = mat_silver if accessory_type != "tie_red" else mat_gold
	buckle.position = Vector3(0.0, -0.18, -0.172)
	torso_node.add_child(buckle)

	# --- CABEÇA & ROSTO HIPER-DETALHADO DO DANTE ---
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.25, 0.0)
	model_root.add_child(head_node)

	var head_mesh = MeshInstance3D.new()
	var sph_h = SphereMesh.new()
	sph_h.radius = 0.17
	sph_h.height = 0.32
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	var jaw = MeshInstance3D.new()
	var box_jaw = BoxMesh.new()
	box_jaw.size = Vector3(0.18, 0.09, 0.14)
	jaw.mesh = box_jaw
	jaw.material_override = mat_skin
	jaw.position = Vector3(0.0, -0.10, -0.06)
	jaw.rotation_degrees = Vector3(-16, 0, 0)
	head_node.add_child(jaw)

	# Orelhas 3D
	var ear_l = MeshInstance3D.new()
	var box_el = BoxMesh.new()
	box_el.size = Vector3(0.02, 0.06, 0.04)
	ear_l.mesh = box_el
	ear_l.material_override = mat_skin
	ear_l.position = Vector3(-0.175, 0.0, 0.0)
	head_node.add_child(ear_l)

	var ear_r = MeshInstance3D.new()
	var box_er = BoxMesh.new()
	box_er.size = Vector3(0.02, 0.06, 0.04)
	ear_r.mesh = box_er
	ear_r.material_override = mat_skin
	ear_r.position = Vector3(0.175, 0.0, 0.0)
	head_node.add_child(ear_r)

	# Olhos Expressivos (Esclera Branca + Íris Escura + Destaque Frontal)
	var eye_l = MeshInstance3D.new()
	var box_eyl = BoxMesh.new()
	box_eyl.size = Vector3(0.046, 0.026, 0.018)
	eye_l.mesh = box_eyl
	eye_l.material_override = mat_white
	eye_l.position = Vector3(-0.060, 0.038, -0.170)
	head_node.add_child(eye_l)

	var pupil_l = MeshInstance3D.new()
	var box_pl = BoxMesh.new()
	box_pl.size = Vector3(0.022, 0.022, 0.015)
	pupil_l.mesh = box_pl
	pupil_l.material_override = mat_pupil
	pupil_l.position = Vector3(-0.060, 0.038, -0.178)
	head_node.add_child(pupil_l)

	var eye_r = MeshInstance3D.new()
	var box_eyr = BoxMesh.new()
	box_eyr.size = Vector3(0.046, 0.026, 0.018)
	eye_r.mesh = box_eyr
	eye_r.material_override = mat_white
	eye_r.position = Vector3(0.060, 0.038, -0.170)
	head_node.add_child(eye_r)

	var pupil_r = MeshInstance3D.new()
	var box_pr = BoxMesh.new()
	box_pr.size = Vector3(0.022, 0.022, 0.015)
	pupil_r.mesh = box_pr
	pupil_r.material_override = mat_pupil
	pupil_r.position = Vector3(0.060, 0.038, -0.178)
	head_node.add_child(pupil_r)

	# Sobrancelhas Estilizadas & Expressivas
	var brow_l = MeshInstance3D.new()
	var box_brl = BoxMesh.new()
	box_brl.size = Vector3(0.052, 0.014, 0.016)
	brow_l.mesh = box_brl
	brow_l.material_override = mat_hair
	brow_l.position = Vector3(-0.060, 0.065, -0.172)
	brow_l.rotation_degrees = Vector3(0, 0, 8)
	head_node.add_child(brow_l)

	var brow_r = MeshInstance3D.new()
	var box_brr = BoxMesh.new()
	box_brr.size = Vector3(0.052, 0.014, 0.016)
	brow_r.mesh = box_brr
	brow_r.material_override = mat_hair
	brow_r.position = Vector3(0.060, 0.065, -0.172)
	brow_r.rotation_degrees = Vector3(0, 0, -8)
	head_node.add_child(brow_r)

	# Nariz Esculpido em 3D
	var nose_bridge = MeshInstance3D.new()
	var box_nb = BoxMesh.new()
	box_nb.size = Vector3(0.022, 0.050, 0.026)
	nose_bridge.mesh = box_nb
	nose_bridge.material_override = mat_skin
	nose_bridge.position = Vector3(0.0, 0.022, -0.176)
	nose_bridge.rotation_degrees = Vector3(-12, 0, 0)
	head_node.add_child(nose_bridge)

	var nose_tip = MeshInstance3D.new()
	var box_nt = BoxMesh.new()
	box_nt.size = Vector3(0.034, 0.024, 0.028)
	nose_tip.mesh = box_nt
	nose_tip.material_override = mat_skin
	nose_tip.position = Vector3(0.0, -0.008, -0.188)
	head_node.add_child(nose_tip)

	# Boca e Lábios Definidos
	var lips = MeshInstance3D.new()
	var box_lp = BoxMesh.new()
	box_lp.size = Vector3(0.054, 0.014, 0.016)
	lips.mesh = box_lp
	lips.material_override = mat_lips
	lips.position = Vector3(0.0, -0.060, -0.168)
	head_node.add_child(lips)

	# Óculos Escuros Elegantes (Apenas quando o traje solicitar shades!)
	if accessory_type == "shades":
		var lens_l = MeshInstance3D.new()
		var box_llens = BoxMesh.new()
		box_llens.size = Vector3(0.048, 0.028, 0.012)
		lens_l.mesh = box_llens
		lens_l.material_override = mat_dark_shades
		lens_l.position = Vector3(-0.060, 0.038, -0.182)
		head_node.add_child(lens_l)

		var lens_r = MeshInstance3D.new()
		var box_rlens = BoxMesh.new()
		box_rlens.size = Vector3(0.048, 0.028, 0.012)
		lens_r.mesh = box_rlens
		lens_r.material_override = mat_dark_shades
		lens_r.position = Vector3(0.060, 0.038, -0.182)
		head_node.add_child(lens_r)

		var glasses_bridge = MeshInstance3D.new()
		var box_gbr = BoxMesh.new()
		box_gbr.size = Vector3(0.035, 0.006, 0.010)
		glasses_bridge.mesh = box_gbr
		glasses_bridge.material_override = mat_silver
		glasses_bridge.position = Vector3(0.0, 0.042, -0.184)
		head_node.add_child(glasses_bridge)

		var temple_l = MeshInstance3D.new()
		var box_tmpl = BoxMesh.new()
		box_tmpl.size = Vector3(0.008, 0.008, 0.16)
		temple_l.mesh = box_tmpl
		temple_l.material_override = mat_silver
		temple_l.position = Vector3(-0.115, 0.038, -0.08)
		head_node.add_child(temple_l)

		var temple_r = MeshInstance3D.new()
		var box_tmpr = BoxMesh.new()
		box_tmpr.size = Vector3(0.008, 0.008, 0.16)
		temple_r.mesh = box_tmpr
		temple_r.material_override = mat_silver
		temple_r.position = Vector3(0.115, 0.038, -0.08)
		head_node.add_child(temple_r)

	# Chapéus, Bonés e Cabelos Estilizados
	if headwear_type == "cowboy_hat":
		var hat_crown = MeshInstance3D.new()
		var cyl_c = CylinderMesh.new()
		cyl_c.top_radius = 0.16
		cyl_c.bottom_radius = 0.18
		cyl_c.height = 0.16
		hat_crown.mesh = cyl_c
		hat_crown.material_override = mat_head
		hat_crown.position = Vector3(0.0, 0.18, -0.01)
		head_node.add_child(hat_crown)

		var hat_band = MeshInstance3D.new()
		var cyl_bnd = CylinderMesh.new()
		cyl_bnd.top_radius = 0.182
		cyl_bnd.bottom_radius = 0.182
		cyl_bnd.height = 0.025
		hat_band.mesh = cyl_bnd
		hat_band.material_override = mat_trim
		hat_band.position = Vector3(0.0, 0.11, -0.01)
		head_node.add_child(hat_band)

		var hat_brim = MeshInstance3D.new()
		var cyl_br = CylinderMesh.new()
		cyl_br.top_radius = 0.32
		cyl_br.bottom_radius = 0.32
		cyl_br.height = 0.02
		hat_brim.mesh = cyl_br
		hat_brim.material_override = mat_head
		hat_brim.position = Vector3(0.0, 0.10, -0.01)
		head_node.add_child(hat_brim)

	elif headwear_type == "beanie":
		var beanie = MeshInstance3D.new()
		var sph_bn = SphereMesh.new()
		sph_bn.radius = 0.185
		sph_bn.height = 0.24
		beanie.mesh = sph_bn
		beanie.material_override = mat_head
		beanie.position = Vector3(0.0, 0.09, 0.0)
		head_node.add_child(beanie)

	elif headwear_type == "cap":
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

		var logo = MeshInstance3D.new()
		var box_lg = BoxMesh.new()
		box_lg.size = Vector3(0.06, 0.05, 0.01)
		logo.mesh = box_lg
		logo.material_override = mat_white
		logo.position = Vector3(0.0, 0.11, -0.16)
		head_node.add_child(logo)

	elif headwear_type == "cap_backwards":
		var cap_b = MeshInstance3D.new()
		var sph_cpb = SphereMesh.new()
		sph_cpb.radius = 0.185
		sph_cpb.height = 0.22
		cap_b.mesh = sph_cpb
		cap_b.material_override = mat_head
		cap_b.position = Vector3(0.0, 0.08, -0.01)
		head_node.add_child(cap_b)

		var brim_b = MeshInstance3D.new()
		var box_brb = BoxMesh.new()
		box_brb.size = Vector3(0.22, 0.020, 0.14)
		brim_b.mesh = box_brb
		brim_b.material_override = mat_head
		brim_b.position = Vector3(0.0, 0.07, 0.16)
		brim_b.rotation_degrees = Vector3(-12, 0, 0)
		head_node.add_child(brim_b)

	elif headwear_type == "tactical_helmet":
		var helmet = MeshInstance3D.new()
		var sph_hl = SphereMesh.new()
		sph_hl.radius = 0.195
		sph_hl.height = 0.24
		helmet.mesh = sph_hl
		helmet.material_override = mat_head
		helmet.position = Vector3(0.0, 0.09, 0.0)
		head_node.add_child(helmet)

	elif headwear_type == "goggles":
		var gog = MeshInstance3D.new()
		var box_gg = BoxMesh.new()
		box_gg.size = Vector3(0.24, 0.06, 0.06)
		gog.mesh = box_gg
		gog.material_override = mat_head
		gog.position = Vector3(0.0, 0.04, -0.16)
		head_node.add_child(gog)

	# Cabelo do Dante (Mechas e Caimento Natural)
	if headwear_type in ["hair_only", "goggles", "cowboy_hat"]:
		var hair_top = MeshInstance3D.new()
		var sph_ht = SphereMesh.new()
		sph_ht.radius = 0.180
		sph_ht.height = 0.20
		hair_top.mesh = sph_ht
		hair_top.material_override = mat_hair
		hair_top.position = Vector3(0.0, 0.09, 0.01)
		head_node.add_child(hair_top)

	var hair_back = MeshInstance3D.new()
	var box_hb = BoxMesh.new()
	box_hb.size = Vector3(0.24, 0.30, 0.10)
	hair_back.mesh = box_hb
	hair_back.material_override = mat_hair
	hair_back.position = Vector3(0.0, -0.06, 0.12)
	head_node.add_child(hair_back)

	var hair_l = MeshInstance3D.new()
	var box_hl = BoxMesh.new()
	box_hl.size = Vector3(0.06, 0.24, 0.08)
	hair_l.mesh = box_hl
	hair_l.material_override = mat_hair
	hair_l.position = Vector3(-0.155, -0.05, 0.02)
	head_node.add_child(hair_l)

	var hair_r = MeshInstance3D.new()
	var box_hr = BoxMesh.new()
	box_hr.size = Vector3(0.06, 0.24, 0.08)
	hair_r.mesh = box_hr
	hair_r.material_override = mat_hair
	hair_r.position = Vector3(0.155, -0.05, 0.02)
	head_node.add_child(hair_r)

	# 3. BRAÇO ESQUERDO
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.24, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb_mesh(0.050, 0.22, mat_black_jacket, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb_mesh(0.042, 0.18, mat_black_jacket, Vector3(0, -0.09, 0)))

	var watch = MeshInstance3D.new()
	var box_w = BoxMesh.new()
	box_w.size = Vector3(0.05, 0.04, 0.05)
	watch.mesh = box_w
	watch.material_override = mat_watch
	watch.position = Vector3(-0.02, -0.14, 0.0)
	left_lower_arm.add_child(watch)

	var glove_l = MeshInstance3D.new()
	var box_glv_l = BoxMesh.new()
	box_glv_l.size = Vector3(0.05, 0.06, 0.06)
	glove_l.mesh = box_glv_l
	glove_l.material_override = mat_head
	glove_l.position = Vector3(0.0, -0.17, 0.0)
	left_lower_arm.add_child(glove_l)

	# 4. BRAÇO DIREITO
	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.24, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb_mesh(0.050, 0.22, mat_black_jacket, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb_mesh(0.042, 0.18, mat_black_jacket, Vector3(0, -0.09, 0)))

	var glove_r = MeshInstance3D.new()
	var box_glv_r = BoxMesh.new()
	box_glv_r.size = Vector3(0.05, 0.06, 0.06)
	glove_r.mesh = box_glv_r
	glove_r.material_override = mat_head
	glove_r.position = Vector3(0.0, -0.17, 0.0)
	right_lower_arm.add_child(glove_r)

	weapon_mount_node = Node3D.new()
	weapon_mount_node.position = Vector3(0.0, -0.18, -0.08)
	right_lower_arm.add_child(weapon_mount_node)
	_update_equipped_weapon_3d_mesh()

	# 5. PERNA ESQUERDA
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.65, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb_mesh(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0)))

	var cargo_pocket_l = MeshInstance3D.new()
	var box_p_l = BoxMesh.new()
	box_p_l.size = Vector3(0.03, 0.10, 0.08)
	cargo_pocket_l.mesh = box_p_l
	cargo_pocket_l.material_override = mat_pants
	cargo_pocket_l.position = Vector3(-0.06, -0.14, 0.0)
	left_upper_leg.add_child(cargo_pocket_l)

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.28, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb_mesh(0.058, 0.26, mat_pants, Vector3(0, -0.13, 0)))
	left_lower_leg.add_child(_create_shoe_mesh(mat_shoes, Vector3(0, -0.26, -0.02)))

	# 6. PERNA DIREITA
	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.65, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb_mesh(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0)))

	var cargo_pocket_r = MeshInstance3D.new()
	var box_p_r = BoxMesh.new()
	box_p_r.size = Vector3(0.03, 0.10, 0.08)
	cargo_pocket_r.mesh = box_p_r
	cargo_pocket_r.material_override = mat_pants
	cargo_pocket_r.position = Vector3(0.06, -0.14, 0.0)
	right_upper_leg.add_child(cargo_pocket_r)

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.28, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb_mesh(0.058, 0.26, mat_pants, Vector3(0, -0.13, 0)))
	right_lower_leg.add_child(_create_shoe_mesh(mat_shoes, Vector3(0, -0.26, -0.02)))

func _update_equipped_weapon_3d_mesh() -> void:
	if not weapon_mount_node:
		return
	for child in weapon_mount_node.get_children():
		child.queue_free()

	current_gun_mesh = Node3D.new()
	weapon_mount_node.add_child(current_gun_mesh)

	var mat_chrome := StandardMaterial3D.new()
	mat_chrome.albedo_color = Color(0.84, 0.86, 0.90)
	mat_chrome.metallic = 0.92
	mat_chrome.roughness = 0.18

	var mat_gunmetal := StandardMaterial3D.new()
	mat_gunmetal.albedo_color = Color(0.18, 0.20, 0.24)
	mat_gunmetal.metallic = 0.85
	mat_gunmetal.roughness = 0.35

	var mat_polymer := StandardMaterial3D.new()
	mat_polymer.albedo_color = Color(0.08, 0.08, 0.10)
	mat_polymer.roughness = 0.70

	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.55, 0.28, 0.14)
	mat_wood.roughness = 0.55

	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.92, 0.78, 0.22)
	mat_brass.metallic = 0.88
	mat_brass.roughness = 0.25

	var flash_pos := Vector3(0.0, 0.0, -0.15)

	match active_weapon_id:
		"shotgun":
			# 1. Cano Principal Superior de Aço
			var barrel = MeshInstance3D.new()
			var cyl_b = CylinderMesh.new()
			cyl_b.top_radius = 0.020
			cyl_b.bottom_radius = 0.020
			cyl_b.height = 0.44
			barrel.mesh = cyl_b
			barrel.material_override = mat_chrome
			barrel.rotation_degrees = Vector3(90, 0, 0)
			barrel.position = Vector3(0.0, 0.03, -0.18)
			current_gun_mesh.add_child(barrel)

			# 2. Tubo do Carregador Inferior
			var mag_tube = MeshInstance3D.new()
			var cyl_mt = CylinderMesh.new()
			cyl_mt.top_radius = 0.016
			cyl_mt.bottom_radius = 0.016
			cyl_mt.height = 0.32
			mag_tube.mesh = cyl_mt
			mag_tube.material_override = mat_gunmetal
			mag_tube.rotation_degrees = Vector3(90, 0, 0)
			mag_tube.position = Vector3(0.0, -0.01, -0.12)
			current_gun_mesh.add_child(mag_tube)

			# 3. Abraçadeira do Cano / Mira de Esfera Dourada
			var band = MeshInstance3D.new()
			var box_bd = BoxMesh.new()
			box_bd.size = Vector3(0.045, 0.065, 0.02)
			band.mesh = box_bd
			band.material_override = mat_gunmetal
			band.position = Vector3(0.0, 0.01, -0.34)
			current_gun_mesh.add_child(band)

			var front_bead = MeshInstance3D.new()
			var sph_bd = SphereMesh.new()
			sph_bd.radius = 0.012
			sph_bd.height = 0.024
			front_bead.mesh = sph_bd
			front_bead.material_override = mat_brass
			front_bead.position = Vector3(0.0, 0.055, -0.38)
			current_gun_mesh.add_child(front_bead)

			# 4. Telha de Bombeamento Estriada de Madeira
			var pump = MeshInstance3D.new()
			var box_p = BoxMesh.new()
			box_p.size = Vector3(0.052, 0.052, 0.14)
			pump.mesh = box_p
			pump.material_override = mat_wood
			pump.position = Vector3(0.0, -0.01, -0.16)
			current_gun_mesh.add_child(pump)

			# 5. Caixa da Culatra (Receptor) com Janela de Ejeção
			var receiver = MeshInstance3D.new()
			var box_rc = BoxMesh.new()
			box_rc.size = Vector3(0.048, 0.075, 0.16)
			receiver.mesh = box_rc
			receiver.material_override = mat_gunmetal
			receiver.position = Vector3(0.0, 0.01, 0.0)
			current_gun_mesh.add_child(receiver)

			# 6. Coronha Clássica de Madeira com Soleira
			var stock = MeshInstance3D.new()
			var box_s = BoxMesh.new()
			box_s.size = Vector3(0.042, 0.085, 0.20)
			stock.mesh = box_s
			stock.material_override = mat_wood
			stock.position = Vector3(0.0, -0.04, 0.16)
			current_gun_mesh.add_child(stock)

			var pad = MeshInstance3D.new()
			var box_pd = BoxMesh.new()
			box_pd.size = Vector3(0.044, 0.090, 0.02)
			pad.mesh = box_pd
			pad.material_override = mat_polymer
			pad.position = Vector3(0.0, -0.04, 0.26)
			current_gun_mesh.add_child(pad)

			flash_pos = Vector3(0.0, 0.03, -0.42)

		"sawed_off":
			# Cano Duplo Curto Serrado (Side-by-side)
			var barrel_l = MeshInstance3D.new()
			var cyl_bl = CylinderMesh.new()
			cyl_bl.top_radius = 0.018
			cyl_bl.bottom_radius = 0.018
			cyl_bl.height = 0.22
			barrel_l.mesh = cyl_bl
			barrel_l.material_override = mat_chrome
			barrel_l.rotation_degrees = Vector3(90, 0, 0)
			barrel_l.position = Vector3(-0.018, 0.02, -0.10)
			current_gun_mesh.add_child(barrel_l)

			var barrel_r = MeshInstance3D.new()
			var cyl_br = CylinderMesh.new()
			cyl_br.top_radius = 0.018
			cyl_br.bottom_radius = 0.018
			cyl_br.height = 0.22
			barrel_r.mesh = cyl_br
			barrel_r.material_override = mat_chrome
			barrel_r.rotation_degrees = Vector3(90, 0, 0)
			barrel_r.position = Vector3(0.018, 0.02, -0.10)
			current_gun_mesh.add_child(barrel_r)

			# Receptor Basculante
			var receiver_so = MeshInstance3D.new()
			var box_rso = BoxMesh.new()
			box_rso.size = Vector3(0.062, 0.065, 0.12)
			receiver_so.mesh = box_rso
			receiver_so.material_override = mat_gunmetal
			receiver_so.position = Vector3(0.0, 0.01, 0.01)
			current_gun_mesh.add_child(receiver_so)

			# Cabo Pistola Serrado de Madeira
			var grip_so = MeshInstance3D.new()
			var box_gso = BoxMesh.new()
			box_gso.size = Vector3(0.038, 0.10, 0.06)
			grip_so.mesh = box_gso
			grip_so.material_override = mat_wood
			grip_so.position = Vector3(0.0, -0.05, 0.05)
			grip_so.rotation_degrees = Vector3(-20, 0, 0)
			current_gun_mesh.add_child(grip_so)

			flash_pos = Vector3(0.0, 0.02, -0.23)

		"magnum":
			# Revólver Magnum .44 com cano longo de 8", nervura superior e tambor
			var barrel_mg = MeshInstance3D.new()
			var box_bmg = BoxMesh.new()
			box_bmg.size = Vector3(0.032, 0.045, 0.22)
			barrel_mg.mesh = box_bmg
			barrel_mg.material_override = mat_chrome
			barrel_mg.position = Vector3(0.0, 0.03, -0.11)
			current_gun_mesh.add_child(barrel_mg)

			var front_sight_mg = MeshInstance3D.new()
			var box_fsm = BoxMesh.new()
			box_fsm.size = Vector3(0.012, 0.018, 0.018)
			front_sight_mg.mesh = box_fsm
			front_sight_mg.material_override = mat_brass
			front_sight_mg.position = Vector3(0.0, 0.06, -0.21)
			current_gun_mesh.add_child(front_sight_mg)

			# Tambor Giratório
			var cylinder_mg = MeshInstance3D.new()
			var cyl_mg = CylinderMesh.new()
			cyl_mg.top_radius = 0.028
			cyl_mg.bottom_radius = 0.028
			cyl_mg.height = 0.08
			cylinder_mg.mesh = cyl_mg
			cylinder_mg.material_override = mat_gunmetal
			cylinder_mg.rotation_degrees = Vector3(90, 0, 0)
			cylinder_mg.position = Vector3(0.0, 0.01, 0.0)
			current_gun_mesh.add_child(cylinder_mg)

			# Cabo de Madeira Nobre
			var grip_mg = MeshInstance3D.new()
			var box_gmg = BoxMesh.new()
			box_gmg.size = Vector3(0.034, 0.10, 0.055)
			grip_mg.mesh = box_gmg
			grip_mg.material_override = mat_wood
			grip_mg.position = Vector3(0.0, -0.05, 0.03)
			grip_mg.rotation_degrees = Vector3(-18, 0, 0)
			current_gun_mesh.add_child(grip_mg)

			flash_pos = Vector3(0.0, 0.03, -0.24)

		"ak47":
			# Fuzil AK-47 com madeira clássica, quebra-chamas e carregador curvo
			var barrel_ak = MeshInstance3D.new()
			var cyl_ak = CylinderMesh.new()
			cyl_ak.top_radius = 0.015
			cyl_ak.bottom_radius = 0.015
			cyl_ak.height = 0.36
			barrel_ak.mesh = cyl_ak
			barrel_ak.material_override = mat_chrome
			barrel_ak.rotation_degrees = Vector3(90, 0, 0)
			barrel_ak.position = Vector3(0.0, 0.02, -0.22)
			current_gun_mesh.add_child(barrel_ak)

			# Guarda-mão de Madeira
			var hguard_ak = MeshInstance3D.new()
			var box_hg = BoxMesh.new()
			box_hg.size = Vector3(0.048, 0.060, 0.16)
			hguard_ak.mesh = box_hg
			hguard_ak.material_override = mat_wood
			hguard_ak.position = Vector3(0.0, 0.01, -0.15)
			current_gun_mesh.add_child(hguard_ak)

			# Receptor de Aço Estampado
			var receiver_ak = MeshInstance3D.new()
			var box_rak = BoxMesh.new()
			box_rak.size = Vector3(0.046, 0.075, 0.20)
			receiver_ak.mesh = box_rak
			receiver_ak.material_override = mat_gunmetal
			receiver_ak.position = Vector3(0.0, 0.01, 0.0)
			current_gun_mesh.add_child(receiver_ak)

			# Carregador Banana Curvo
			var mag_ak = MeshInstance3D.new()
			var box_mak = BoxMesh.new()
			box_mak.size = Vector3(0.028, 0.18, 0.06)
			mag_ak.mesh = box_mak
			mag_ak.material_override = mat_gunmetal
			mag_ak.position = Vector3(0.0, -0.11, -0.05)
			mag_ak.rotation_degrees = Vector3(22, 0, 0)
			current_gun_mesh.add_child(mag_ak)

			# Coronha de Madeira Clássica
			var stock_ak = MeshInstance3D.new()
			var box_sak = BoxMesh.new()
			box_sak.size = Vector3(0.040, 0.080, 0.22)
			stock_ak.mesh = box_sak
			stock_ak.material_override = mat_wood
			stock_ak.position = Vector3(0.0, -0.02, 0.18)
			current_gun_mesh.add_child(stock_ak)

			flash_pos = Vector3(0.0, 0.02, -0.42)

		"m4a1":
			# Fuzil M4A1 Tático Militar com Mira Holográfica
			var barrel_m4 = MeshInstance3D.new()
			var cyl_m4 = CylinderMesh.new()
			cyl_m4.top_radius = 0.015
			cyl_m4.bottom_radius = 0.015
			cyl_m4.height = 0.34
			barrel_m4.mesh = cyl_m4
			barrel_m4.material_override = mat_chrome
			barrel_m4.rotation_degrees = Vector3(90, 0, 0)
			barrel_m4.position = Vector3(0.0, 0.02, -0.22)
			current_gun_mesh.add_child(barrel_m4)

			# Guarda-mão Quad-Rail Preto
			var rail_m4 = MeshInstance3D.new()
			var box_rm4 = BoxMesh.new()
			box_rm4.size = Vector3(0.046, 0.055, 0.16)
			rail_m4.mesh = box_rm4
			rail_m4.material_override = mat_polymer
			rail_m4.position = Vector3(0.0, 0.015, -0.15)
			current_gun_mesh.add_child(rail_m4)

			# Receptor Preto com Mira Holográfica
			var receiver_m4 = MeshInstance3D.new()
			var box_rcm4 = BoxMesh.new()
			box_rcm4.size = Vector3(0.046, 0.075, 0.20)
			receiver_m4.mesh = box_rcm4
			receiver_m4.material_override = mat_gunmetal
			receiver_m4.position = Vector3(0.0, 0.01, 0.0)
			current_gun_mesh.add_child(receiver_m4)

			var holo_sight = MeshInstance3D.new()
			var box_hs = BoxMesh.new()
			box_hs.size = Vector3(0.035, 0.035, 0.07)
			holo_sight.mesh = box_hs
			holo_sight.material_override = mat_polymer
			holo_sight.position = Vector3(0.0, 0.065, -0.02)
			current_gun_mesh.add_child(holo_sight)

			# Carregador STANAG 30 Tiros
			var mag_m4 = MeshInstance3D.new()
			var box_mm4 = BoxMesh.new()
			box_mm4.size = Vector3(0.026, 0.16, 0.055)
			mag_m4.mesh = box_mm4
			mag_m4.material_override = mat_polymer
			mag_m4.position = Vector3(0.0, -0.10, -0.04)
			mag_m4.rotation_degrees = Vector3(10, 0, 0)
			current_gun_mesh.add_child(mag_m4)

			# Coronha Tática Retrátil Crane
			var stock_m4 = MeshInstance3D.new()
			var box_sm4 = BoxMesh.new()
			box_sm4.size = Vector3(0.038, 0.080, 0.18)
			stock_m4.mesh = box_sm4
			stock_m4.material_override = mat_polymer
			stock_m4.position = Vector3(0.0, 0.0, 0.16)
			current_gun_mesh.add_child(stock_m4)

			flash_pos = Vector3(0.0, 0.02, -0.40)

		"rpg":
			# Lança-Foguetes RPG-7 apoiado diretamente sobre o ombro direito
			var launcher_tube = MeshInstance3D.new()
			var cyl_tube = CylinderMesh.new()
			cyl_tube.top_radius = 0.034
			cyl_tube.bottom_radius = 0.034
			cyl_tube.height = 0.74
			launcher_tube.mesh = cyl_tube
			launcher_tube.material_override = _make_mat(Color(0.22, 0.28, 0.18), 0.4)
			launcher_tube.rotation_degrees = Vector3(90, 0, 0)
			launcher_tube.position = Vector3(0.0, 0.08, 0.05)
			current_gun_mesh.add_child(launcher_tube)

			# Cone Exaustor Traseiro
			var exhaust = MeshInstance3D.new()
			var cyl_ex = CylinderMesh.new()
			cyl_ex.top_radius = 0.048
			cyl_ex.bottom_radius = 0.034
			cyl_ex.height = 0.12
			exhaust.mesh = cyl_ex
			exhaust.material_override = mat_gunmetal
			exhaust.rotation_degrees = Vector3(90, 0, 0)
			exhaust.position = Vector3(0.0, 0.08, 0.44)
			current_gun_mesh.add_child(exhaust)

			# Ogiva Cônica RPG Frontal
			var warhead = MeshInstance3D.new()
			var cyl_wh = CylinderMesh.new()
			cyl_wh.top_radius = 0.008
			cyl_wh.bottom_radius = 0.056
			cyl_wh.height = 0.18
			warhead.mesh = cyl_wh
			warhead.material_override = _make_mat(Color(0.32, 0.42, 0.20), 0.3)
			warhead.rotation_degrees = Vector3(90, 0, 0)
			warhead.position = Vector3(0.0, 0.08, -0.40)
			current_gun_mesh.add_child(warhead)

			# Escudo Térmico de Madeira
			var shield_rpg = MeshInstance3D.new()
			var cyl_sh = CylinderMesh.new()
			cyl_sh.top_radius = 0.042
			cyl_sh.bottom_radius = 0.042
			cyl_sh.height = 0.24
			shield_rpg.mesh = cyl_sh
			shield_rpg.material_override = mat_wood
			shield_rpg.rotation_degrees = Vector3(90, 0, 0)
			shield_rpg.position = Vector3(0.0, 0.08, 0.0)
			current_gun_mesh.add_child(shield_rpg)

			# Empunhadura e Gatilho do RPG
			var grip_rpg = MeshInstance3D.new()
			var box_grpg = BoxMesh.new()
			box_grpg.size = Vector3(0.032, 0.09, 0.045)
			grip_rpg.mesh = box_grpg
			grip_rpg.material_override = mat_gunmetal
			grip_rpg.position = Vector3(0.0, 0.0, -0.10)
			current_gun_mesh.add_child(grip_rpg)

			flash_pos = Vector3(0.0, 0.08, -0.50)

		"flamethrower":
			# Lança-Chamas com Bico Lança-Jato e Garrafa de Combustível
			var flame_tube = MeshInstance3D.new()
			var cyl_ft = CylinderMesh.new()
			cyl_ft.top_radius = 0.024
			cyl_ft.bottom_radius = 0.024
			cyl_ft.height = 0.42
			flame_tube.mesh = cyl_ft
			flame_tube.material_override = mat_gunmetal
			flame_tube.rotation_degrees = Vector3(90, 0, 0)
			flame_tube.position = Vector3(0.0, 0.02, -0.16)
			current_gun_mesh.add_child(flame_tube)

			# Botijão de Combustível Vermelho no Corpo da Arma
			var fuel_tank = MeshInstance3D.new()
			var cyl_tk = CylinderMesh.new()
			cyl_tk.top_radius = 0.045
			cyl_tk.bottom_radius = 0.045
			cyl_tk.height = 0.16
			fuel_tank.mesh = cyl_tk
			fuel_tank.material_override = _make_mat(Color(0.85, 0.15, 0.12), 0.3)
			fuel_tank.rotation_degrees = Vector3(90, 0, 0)
			fuel_tank.position = Vector3(0.0, -0.05, -0.12)
			current_gun_mesh.add_child(fuel_tank)

			flash_pos = Vector3(0.0, 0.02, -0.38)

		"grenade":
			# Granada de Mão de Fragmentação Tipo Abacaxi
			var grenade_body = MeshInstance3D.new()
			var sph_gn = SphereMesh.new()
			sph_gn.radius = 0.045
			sph_gn.height = 0.09
			grenade_body.mesh = sph_gn
			grenade_body.material_override = _make_mat(Color(0.25, 0.35, 0.18), 0.4)
			grenade_body.position = Vector3(0.0, 0.0, -0.10)
			current_gun_mesh.add_child(grenade_body)

			var pin = MeshInstance3D.new()
			var cyl_pn = CylinderMesh.new()
			cyl_pn.top_radius = 0.015
			cyl_pn.bottom_radius = 0.015
			cyl_pn.height = 0.03
			pin.mesh = cyl_pn
			pin.material_override = mat_brass
			pin.position = Vector3(0.0, 0.055, -0.10)
			current_gun_mesh.add_child(pin)

			flash_pos = Vector3(0.0, 0.0, -0.12)

		"smg", "micro_smg":
			# 1. Receptor Tático com Trilho Superior
			var receiver = MeshInstance3D.new()
			var box_r = BoxMesh.new()
			box_r.size = Vector3(0.046, 0.072, 0.24)
			receiver.mesh = box_r
			receiver.material_override = mat_gunmetal
			receiver.position = Vector3(0.0, 0.01, -0.06)
			current_gun_mesh.add_child(receiver)

			var rail = MeshInstance3D.new()
			var box_rl = BoxMesh.new()
			box_rl.size = Vector3(0.035, 0.015, 0.18)
			rail.mesh = box_rl
			rail.material_override = mat_polymer
			rail.position = Vector3(0.0, 0.052, -0.06)
			current_gun_mesh.add_child(rail)

			# 2. Cano com Quebra-Chamas / Compensador Tático
			var barrel = MeshInstance3D.new()
			var cyl_smg = CylinderMesh.new()
			cyl_smg.top_radius = 0.016
			cyl_smg.bottom_radius = 0.016
			cyl_smg.height = 0.16
			barrel.mesh = cyl_smg
			barrel.material_override = mat_chrome
			barrel.rotation_degrees = Vector3(90, 0, 0)
			barrel.position = Vector3(0.0, 0.01, -0.24)
			current_gun_mesh.add_child(barrel)

			var comp = MeshInstance3D.new()
			var cyl_cp = CylinderMesh.new()
			cyl_cp.top_radius = 0.022
			cyl_cp.bottom_radius = 0.022
			cyl_cp.height = 0.05
			comp.mesh = cyl_cp
			comp.material_override = mat_gunmetal
			comp.rotation_degrees = Vector3(90, 0, 0)
			comp.position = Vector3(0.0, 0.01, -0.32)
			current_gun_mesh.add_child(comp)

			# 3. Carregador Curvo Banana de 30 Tiros
			var mag = MeshInstance3D.new()
			var box_m = BoxMesh.new()
			box_m.size = Vector3(0.028, 0.16, 0.05)
			mag.mesh = box_m
			mag.material_override = mat_polymer
			mag.position = Vector3(0.0, -0.10, -0.07)
			mag.rotation_degrees = Vector3(18, 0, 0)
			current_gun_mesh.add_child(mag)

			# 4. Empunhadura e Coronha Tática Rebatível Dobrada
			var grip = MeshInstance3D.new()
			var box_gp = BoxMesh.new()
			box_gp.size = Vector3(0.034, 0.09, 0.05)
			grip.mesh = box_gp
			grip.material_override = mat_polymer
			grip.position = Vector3(0.0, -0.05, 0.03)
			grip.rotation_degrees = Vector3(-12, 0, 0)
			current_gun_mesh.add_child(grip)

			var wire_stock = MeshInstance3D.new()
			var box_ws = BoxMesh.new()
			box_ws.size = Vector3(0.038, 0.03, 0.14)
			wire_stock.mesh = box_ws
			wire_stock.material_override = mat_chrome
			wire_stock.position = Vector3(0.0, 0.03, 0.12)
			current_gun_mesh.add_child(wire_stock)

			flash_pos = Vector3(0.0, 0.01, -0.36)

		_: # "pistol" (9mm Beretta / Glock)
			# 1. Ferrolho de Aço Usinado Cromado com Ranhuras
			var slide = MeshInstance3D.new()
			var box_g = BoxMesh.new()
			box_g.size = Vector3(0.038, 0.055, 0.17)
			slide.mesh = box_g
			slide.material_override = mat_chrome
			slide.position = Vector3(0.0, 0.03, -0.05)
			current_gun_mesh.add_child(slide)

			# Miras Dianteira e Traseira
			var front_sight = MeshInstance3D.new()
			var box_fs = BoxMesh.new()
			box_fs.size = Vector3(0.012, 0.015, 0.015)
			front_sight.mesh = box_fs
			front_sight.material_override = mat_gunmetal
			front_sight.position = Vector3(0.0, 0.062, -0.12)
			current_gun_mesh.add_child(front_sight)

			var rear_sight = MeshInstance3D.new()
			var box_rs = BoxMesh.new()
			box_rs.size = Vector3(0.024, 0.015, 0.015)
			rear_sight.mesh = box_rs
			rear_sight.material_override = mat_gunmetal
			rear_sight.position = Vector3(0.0, 0.062, 0.025)
			current_gun_mesh.add_child(rear_sight)

			# 2. Armação e Empunhadura de Polímero Preto
			var frame = MeshInstance3D.new()
			var box_fr = BoxMesh.new()
			box_fr.size = Vector3(0.036, 0.035, 0.15)
			frame.mesh = box_fr
			frame.material_override = mat_gunmetal
			frame.position = Vector3(0.0, 0.0, -0.04)
			current_gun_mesh.add_child(frame)

			var grip = MeshInstance3D.new()
			var box_grp = BoxMesh.new()
			box_grp.size = Vector3(0.034, 0.09, 0.05)
			grip.mesh = box_grp
			grip.material_override = mat_polymer
			grip.position = Vector3(0.0, -0.04, 0.01)
			grip.rotation_degrees = Vector3(-16, 0, 0)
			current_gun_mesh.add_child(grip)

			# 3. Base do Carregador Alargada
			var mag_base = MeshInstance3D.new()
			var box_mb = BoxMesh.new()
			box_mb.size = Vector3(0.038, 0.015, 0.058)
			mag_base.mesh = box_mb
			mag_base.material_override = mat_gunmetal
			mag_base.position = Vector3(0.0, -0.09, 0.02)
			mag_base.rotation_degrees = Vector3(-16, 0, 0)
			current_gun_mesh.add_child(mag_base)

			# 4. Gatilho Dourado / Latão
			var trigger = MeshInstance3D.new()
			var box_tr = BoxMesh.new()
			box_tr.size = Vector3(0.01, 0.025, 0.015)
			trigger.mesh = box_tr
			trigger.material_override = mat_brass
			trigger.position = Vector3(0.0, -0.01, -0.02)
			current_gun_mesh.add_child(trigger)

			flash_pos = Vector3(0.0, 0.03, -0.16)

	muzzle_flash_3d = MeshInstance3D.new()
	var sph_f = SphereMesh.new()
	sph_f.radius = 0.08
	sph_f.height = 0.16
	muzzle_flash_3d.mesh = sph_f
	var mat_flash = StandardMaterial3D.new()
	mat_flash.albedo_color = Color(1.0, 0.85, 0.2)
	mat_flash.emission_enabled = true
	mat_flash.emission = Color(1.0, 0.6, 0.1)
	mat_flash.emission_energy_multiplier = 4.5
	mat_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash_3d.material_override = mat_flash
	muzzle_flash_3d.position = flash_pos
	muzzle_flash_3d.visible = false
	current_gun_mesh.add_child(muzzle_flash_3d)

	muzzle_light_3d = OmniLight3D.new()
	muzzle_light_3d.light_color = Color(1.0, 0.7, 0.2)
	muzzle_light_3d.light_energy = 2.8
	muzzle_light_3d.omni_range = 2.5
	muzzle_light_3d.visible = false
	muzzle_light_3d.position = flash_pos
	current_gun_mesh.add_child(muzzle_light_3d)

func _make_mat(col: Color, roughness: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = roughness
	return mat

func _create_limb_mesh(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.85
	cyl.height = height
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat
	mesh_inst.position = offset
	return mesh_inst

func _create_shoe_mesh(mat: Material, offset: Vector3) -> MeshInstance3D:
	var shoe = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.09, 0.065, 0.16)
	shoe.mesh = box
	shoe.material_override = mat
	shoe.position = offset
	return shoe

func _physics_process(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	var input_vector: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var is_sprinting: bool = Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT)
	var current_speed: float = speed * 1.50 if is_sprinting else speed

	var is_moving: bool = input_vector != Vector2.ZERO
	if is_moving:
		velocity = input_vector * current_speed
		walk_clock += delta * (8.0 if is_sprinting else 4.8)
		_handle_footsteps(true, is_sprinting)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		walk_clock += delta * 1.8

	rotation = 0.0
	move_and_slide()

	# --- ROTAÇÃO 3D E ANIMAÇÃO ARTICULADA DO DANTE ---
	var mouse_pos: Vector2 = get_global_mouse_position()
	var is_aiming: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var aim_dir: Vector2 = (mouse_pos - global_position).normalized() if is_aiming else (input_vector.normalized() if is_moving else (mouse_pos - global_position).normalized())

	if model_root and aim_dir.length_squared() > 0.01:
		var target_angle_3d: float = -atan2(aim_dir.y, aim_dir.x) - PI * 0.5
		model_root.rotation.y = lerp_angle(model_root.rotation.y, target_angle_3d, 15.0 * delta)

	# Ciclo de Passos & Articulações com Cadência Suave
	var step_angle: float = (sin(walk_clock) * (0.50 if is_sprinting else 0.36)) if is_moving else 0.0
	var arm_swing: float = -step_angle * 0.65
	var bobbing: float = (absf(cos(walk_clock)) * (0.022 if is_sprinting else 0.012)) if is_moving else (sin(walk_clock) * 0.005)

	if left_upper_leg and right_upper_leg:
		left_upper_leg.rotation.x = step_angle
		right_upper_leg.rotation.x = -step_angle
		if left_lower_leg and right_lower_leg:
			left_lower_leg.rotation.x = maxf(0.0, -step_angle * 0.70)
			right_lower_leg.rotation.x = maxf(0.0, step_angle * 0.70)

	# Posturas de Braço 3D Differentiated de acordo com a Arma e Stance
	var wdata := WEAPON_CATALOG.get_weapon(active_weapon_id)
	var stance: String = String(wdata.get("stance", "pistol"))

	if right_upper_arm and left_upper_arm:
		match stance:
			"shoulder_rpg":
				# Bazuca / RPG apoiado diretamente sobre o ombro direito em postura firme
				var breath := sin(walk_clock * 0.5) * (0.04 if is_moving else 0.015)
				right_upper_arm.rotation = Vector3(1.18 + breath, -0.22, 0.08)
				right_lower_arm.rotation = Vector3(0.35, -0.08, 0.0)
				left_upper_arm.rotation = Vector3(1.08 + breath, 0.42, -0.26)
				left_lower_arm.rotation = Vector3(0.62, 0.18, 0.0)
			"rifle":
				# Fuzil AK-47 / M4A1 / SMG / Escopeta 12G com Pegada Tática de DUAS MÃOS
				var recoil_bob := sin(walk_clock * 0.8) * (0.04 if is_moving else 0.015)
				right_upper_arm.rotation = Vector3(1.42 + recoil_bob, -0.12, 0.0)
				right_lower_arm.rotation = Vector3(0.08, -0.05, 0.0)
				left_upper_arm.rotation = Vector3(1.24 + recoil_bob, 0.46, -0.24)
				left_lower_arm.rotation = Vector3(0.48, 0.14, 0.0)
			"hip_heavy":
				# Lança-chamas com empunhadura dupla pesada no quadril
				var flame_bob := sin(walk_clock * 0.8) * (0.03 if is_moving else 0.012)
				right_upper_arm.rotation = Vector3(0.92 + flame_bob, -0.18, 0.0)
				right_lower_arm.rotation = Vector3(0.38, 0.0, 0.0)
				left_upper_arm.rotation = Vector3(1.15 + flame_bob, 0.36, -0.16)
				left_lower_arm.rotation = Vector3(0.35, 0.10, 0.0)
			"grenade":
				# Granada erguida na mão direita pronta para o arremesso
				right_upper_arm.rotation = Vector3(0.85, 0.15, 0.28)
				right_lower_arm.rotation = Vector3(0.65, 0.0, 0.0)
				left_upper_arm.rotation = Vector3(-arm_swing * 0.4, 0.0, 0.0)
				left_lower_arm.rotation = Vector3(0.12, 0.0, 0.0)
			_:
				# Pistola 9mm / Magnum .44 / Sawed-Off de empunhadura frontal firme
				var hand_sw := sin(walk_clock * 0.6) * (0.025 if is_moving else 0.01)
				right_upper_arm.rotation = Vector3(1.40 + hand_sw, -0.05, 0.0)
				right_lower_arm.rotation = Vector3(0.05, 0.0, 0.0)
				left_upper_arm.rotation = Vector3(-arm_swing * 0.4, 0.0, 0.0)
				left_lower_arm.rotation = Vector3(0.12, 0.0, 0.0)

	if torso_node and head_node:
		torso_node.position.y = 0.85 + bobbing
		head_node.position.y = 1.25 + bobbing

	_handle_weapon_fire()
	if Input.is_action_just_pressed("interact"):
		if get_tree().get_nodes_in_group("weapon_store_open").is_empty():
			try_enter_vehicle()

func _trigger_muzzle_flash_3d() -> void:
	if muzzle_flash_3d and muzzle_light_3d:
		muzzle_flash_3d.visible = true
		muzzle_light_3d.visible = true
		var t = create_tween()
		t.tween_interval(0.05)
		t.tween_callback(func():
			if muzzle_flash_3d: muzzle_flash_3d.visible = false
			if muzzle_light_3d: muzzle_light_3d.visible = false
		)

var _last_step_side: int = 0

func _handle_footsteps(moving: bool, is_sprinting: bool) -> void:
	if not moving:
		return
	var current_side: int = 1 if sin(walk_clock) > 0.0 else -1
	if current_side != _last_step_side:
		_last_step_side = current_side
		_play_footstep(is_sprinting)

func _play_footstep(is_sprinting: bool) -> void:
	var footstep_player := AudioStreamPlayer2D.new()
	footstep_player.stream = ProceduralAudio.get_footstep_stream("concrete")
	footstep_player.volume_db = -20.0 if not is_sprinting else -16.0
	footstep_player.pitch_scale = randf_range(0.92, 1.08)
	footstep_player.max_distance = 450.0
	add_child(footstep_player)
	footstep_player.play()
	footstep_player.finished.connect(footstep_player.queue_free)

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	if is_dead or is_arrested:
		return
	var absorbed := mini(armor, amount)
	armor -= absorbed
	health = maxi(0, health - (amount - absorbed))
	_refresh_weapon_ui()
	
	if mat_black_jacket:
		mat_black_jacket.albedo_color = Color(1.0, 0.2, 0.2)
		var tween = create_tween()
		tween.tween_property(mat_black_jacket, "albedo_color", Color("121214"), 0.25)
	
	_play_audio(ProceduralAudio.get_squish_stream(), -4.0)
	
	if health <= 0:
		_wasted()

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	if is_recovering:
		return
	is_recovering = true
	var damage = clampi(int(impact_velocity.length() * 0.25), 35, 100)
	_spawn_blood_burst(impact_velocity.normalized())
	_create_3d_blood_puddle()
	velocity = impact_velocity.normalized() * maxf(320.0, impact_velocity.length() * 1.0)
	take_damage(damage)
	
	if health > 0:
		await get_tree().create_timer(0.8).timeout
		is_recovering = false

func add_armor(amount: int) -> void:
	armor = clampi(armor + amount, 0, max_armor)
	_refresh_weapon_ui()
	_show_weapon_notice("COLETE %d%%" % armor)

func add_weapon_loot(id: StringName, ammo_amount: int) -> bool:
	var weapon_id := String(id)
	var data := WEAPON_CATALOG.get_weapon(weapon_id)
	if data.is_empty():
		return false
	if not (weapon_inventory.get(weapon_id, false) == true):
		weapon_inventory[weapon_id] = true
		weapon_ammo[weapon_id] = {"clip": 0, "reserve": 0}
	var ammo: Dictionary = weapon_ammo.get(weapon_id, {"clip": 0, "reserve": 0})
	ammo["reserve"] = int(ammo.get("reserve", 0)) + maxi(0, ammo_amount)
	weapon_ammo[weapon_id] = ammo
	active_weapon_id = weapon_id
	_update_equipped_weapon_3d_mesh()
	_refresh_weapon_ui()
	_show_weapon_notice("PEGOU " + String(data.get("label", weapon_id)))
	return true

func _spawn_blood_burst(dir: Vector2) -> void:
	var blood_particles := CPUParticles2D.new()
	blood_particles.emitting = true
	blood_particles.one_shot = true
	blood_particles.explosiveness = 0.9
	blood_particles.amount = 30
	blood_particles.lifetime = 0.7
	blood_particles.spread = 45.0
	blood_particles.direction = dir
	blood_particles.initial_velocity_min = 80.0
	blood_particles.initial_velocity_max = 220.0
	blood_particles.gravity = Vector2(0, 180)
	blood_particles.scale_amount_min = 2.0
	blood_particles.scale_amount_max = 5.0
	blood_particles.color = Color(0.75, 0.05, 0.05, 0.95)
	add_child(blood_particles)
	_play_audio(ProceduralAudio.get_scream_stream(), -4.0)

func _create_3d_blood_puddle() -> void:
	var puddle_root := Node2D.new()
	puddle_root.name = "3DBloodPuddle"
	puddle_root.global_position = global_position
	puddle_root.z_index = -1
	
	var base_poly := Polygon2D.new()
	base_poly.polygon = PackedVector2Array([
		Vector2(-14, -4), Vector2(-9, -11), Vector2(0, -13),
		Vector2(10, -9), Vector2(15, -1), Vector2(13, 8),
		Vector2(5, 12), Vector2(-6, 11), Vector2(-13, 5)
	])
	base_poly.color = Color(0.24, 0.01, 0.015, 0.92)
	puddle_root.add_child(base_poly)
	
	var core_poly := Polygon2D.new()
	core_poly.polygon = PackedVector2Array([
		Vector2(-11, -3), Vector2(-7, -8), Vector2(0, -10),
		Vector2(8, -7), Vector2(12, -1), Vector2(10, 6),
		Vector2(4, 9), Vector2(-5, 8), Vector2(-10, 4)
	])
	core_poly.color = Color(0.68, 0.04, 0.04, 0.95)
	puddle_root.add_child(core_poly)
	
	var gloss_poly := Polygon2D.new()
	gloss_poly.polygon = PackedVector2Array([
		Vector2(-5, -6), Vector2(-1, -8), Vector2(4, -5),
		Vector2(1, -4), Vector2(-4, -4)
	])
	gloss_poly.color = Color(1.0, 0.65, 0.65, 0.45)
	puddle_root.add_child(gloss_poly)
	
	var drops := [Vector2(16, -9), Vector2(-15, 8), Vector2(8, 14), Vector2(-12, -11)]
	for drop_pos in drops:
		var drop := Polygon2D.new()
		drop.polygon = PackedVector2Array([
			Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(1.2, 1.2), Vector2(-1.2, 1.2)
		])
		drop.position = drop_pos
		drop.color = Color(0.45, 0.02, 0.02, 0.85)
		puddle_root.add_child(drop)
		
	if get_parent():
		get_parent().add_child(puddle_root)
	else:
		get_tree().current_scene.add_child(puddle_root)
		
	puddle_root.scale = Vector2(0.1, 0.1)
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(puddle_root, "scale", Vector2(0.7, 0.7), 0.55)
	
	var fade_tween = puddle_root.create_tween()
	fade_tween.tween_interval(7.0)
	fade_tween.tween_property(puddle_root, "modulate:a", 0.0, 2.5)
	fade_tween.tween_callback(puddle_root.queue_free)

func _wasted() -> void:
	if is_dead or is_arrested:
		return
	is_dead = true
	_release_controlled_vehicle()
	
	show()
	is_recovering = true
	_create_3d_blood_puddle()
	set_physics_process(false)
	_play_audio(ProceduralAudio.get_wasted_stream(), 0.0)
	
	var wm = get_node_or_null("/root/WantedManager")
	if wm:
		wm.dismiss_all_police()
	
	var flash := CanvasLayer.new()
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.8, 0.1, 0.1, 0.45)
	flash.add_child(rect)
	
	var wasted_label := Label.new()
	wasted_label.text = "SE FODEU"
	wasted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wasted_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wasted_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	wasted_label.add_theme_font_size_override("font_size", 42)
	wasted_label.add_theme_color_override("font_color", Color(1, 0.1, 0.1))
	wasted_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	wasted_label.add_theme_constant_override("shadow_offset_x", 3)
	wasted_label.add_theme_constant_override("shadow_offset_y", 3)
	flash.add_child(wasted_label)
	
	get_tree().get_root().add_child(flash)
	
	await get_tree().create_timer(2.2).timeout
	flash.queue_free()
	
	_respawn_at_hospital()
	await get_tree().create_timer(1.5).timeout
	is_dead = false
	is_recovering = false


func arrest_and_respawn() -> void:
	if is_dead or is_arrested:
		return
	is_arrested = true
	is_recovering = true
	_release_controlled_vehicle()
	show()
	velocity = Vector2.ZERO
	set_physics_process(false)

	var flash := CanvasLayer.new()
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.1, 0.2, 0.8, 0.45)
	flash.add_child(rect)
	var label := Label.new()
	label.text = "PRESO"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 46)
	label.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	flash.add_child(label)
	get_tree().get_root().add_child(flash)

	var wm = get_node_or_null("/root/WantedManager")
	if wm:
		wm.dismiss_all_police()

	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(flash):
		flash.queue_free()
	_respawn_at_hospital()
	await get_tree().create_timer(1.5).timeout
	is_arrested = false
	is_recovering = false


func _release_controlled_vehicle() -> void:
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if not is_instance_valid(vehicle) or vehicle.get("is_driven_by_player") != true:
			continue
		if vehicle.has_method("exit_vehicle"):
			vehicle.exit_vehicle()
		else:
			vehicle.set("is_driven_by_player", false)


func _respawn_at_hospital() -> void:
	health = max_health
	velocity = Vector2.ZERO
	var hospital := _get_nearest_hospital_spawn()
	if hospital:
		global_position = hospital.global_position
	else:
		global_position = Vector2(1125, 375)
	for col in find_children("", "CollisionShape2D", true, false):
		col.set_deferred("disabled", false)
	show()
	set_physics_process(true)
	if camera:
		camera.make_current()
	_refresh_weapon_ui()


func _get_nearest_hospital_spawn() -> Node2D:
	var nearest: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("hospital_spawn"):
		var hospital := node as Node2D
		if not is_instance_valid(hospital):
			continue
		var distance := global_position.distance_squared_to(hospital.global_position)
		if nearest == null or distance < best_distance:
			nearest = hospital
			best_distance = distance
	return nearest

func _play_audio(stream: AudioStream, volume_db: float = -6.0) -> void:
	var player = AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = 600.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _setup_weapons() -> void:
	money = starting_money
	weapon_inventory = {
		"pistol": true,
		"magnum": false,
		"smg": false,
		"shotgun": false,
		"sawed_off": false,
		"ak47": false,
		"m4a1": false,
		"rpg": false,
		"flamethrower": false,
		"grenade": false
	}
	weapon_ammo = {
		"pistol": {"clip": 12, "reserve": 60},
		"magnum": {"clip": 0, "reserve": 0},
		"smg": {"clip": 0, "reserve": 0},
		"shotgun": {"clip": 0, "reserve": 0},
		"sawed_off": {"clip": 0, "reserve": 0},
		"ak47": {"clip": 0, "reserve": 0},
		"m4a1": {"clip": 0, "reserve": 0},
		"rpg": {"clip": 0, "reserve": 0},
		"flamethrower": {"clip": 0, "reserve": 0},
		"grenade": {"clip": 0, "reserve": 0}
	}
	weapon_wheel = WEAPON_WHEEL_SCRIPT.new()
	var ui_parent: Node = get_tree().current_scene
	if ui_parent == null:
		ui_parent = get_tree().root
	ui_parent.call_deferred("add_child", weapon_wheel)
	_update_equipped_weapon_3d_mesh()
	call_deferred("_refresh_weapon_ui")

func _input(event: InputEvent) -> void:
	if not visible or get_tree().get_nodes_in_group("weapon_store_open").size() > 0:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon(-1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_map := {
			KEY_1: "pistol",
			KEY_2: "magnum",
			KEY_3: "smg",
			KEY_4: "shotgun",
			KEY_5: "sawed_off",
			KEY_6: "ak47",
			KEY_7: "m4a1",
			KEY_8: "rpg",
			KEY_9: "flamethrower",
			KEY_0: "grenade"
		}
		if key_map.has(event.keycode):
			var target_weapon: String = key_map[event.keycode]
			if weapon_inventory.get(target_weapon, false) == true:
				active_weapon_id = target_weapon
				_update_equipped_weapon_3d_mesh()
				_show_weapon_notice(String(WEAPON_CATALOG.get_weapon(target_weapon).get("label", target_weapon)))
				_refresh_weapon_ui()
				get_viewport().set_input_as_handled()

func _handle_weapon_fire() -> void:
	var data := WEAPON_CATALOG.get_weapon(active_weapon_id)
	if data.is_empty():
		return
	var primary_pressed: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _flamethrower_audio and _flamethrower_audio.playing and (not primary_pressed or active_weapon_id != "flamethrower"):
		_flamethrower_audio.stop()
	var wants_to_fire: bool = primary_pressed if (data.get("automatic", false) == true) else primary_pressed and not primary_fire_was_pressed
	if wants_to_fire and fire_cooldown <= 0.0:
		_shoot_towards(get_global_mouse_position())
	primary_fire_was_pressed = primary_pressed

func _shoot_towards(target: Vector2) -> void:
	var direction = global_position.direction_to(target)
	if direction.length_squared() < 0.01:
		return
	var data := WEAPON_CATALOG.get_weapon(active_weapon_id)
	var ammo: Dictionary = weapon_ammo.get(active_weapon_id, {})
	if int(ammo.get("clip", 0)) <= 0:
		_reload_active_weapon()
		if int(ammo.get("clip", 0)) <= 0:
			_show_weapon_notice("SEM MUNIÇÃO")
			return
	ammo["clip"] = int(ammo.get("clip", 0)) - 1
	weapon_ammo[active_weapon_id] = ammo
	fire_cooldown = float(data.get("fire_interval", fire_interval))

	# Disparo Especial: Granada de Fragmentação Física com Quique e Fusível
	if (data.get("is_grenade", false) == true) or active_weapon_id == "grenade":
		var grenade_scene = preload("res://GrenadeProjectile.tscn")
		var grenade = grenade_scene.instantiate() as GrenadeProjectile
		get_tree().current_scene.add_child(grenade)
		var throw_dist: float = clampf(global_position.distance_to(target), 120.0, 520.0)
		var throw_speed: float = throw_dist * 1.85
		grenade.setup(global_position + direction * 22.0, direction, throw_speed, self)
		_play_audio(ProceduralAudio.get_grenade_throw_stream(), 0.0)
		_trigger_muzzle_flash_3d()
		_refresh_weapon_ui()
		return

	# Disparo Especial: Jato Contínuo de Fogo de Curto Alcance do Lança-Chamas
	if active_weapon_id == "flamethrower" or (data.get("is_flame", false) == true):
		var flame_scene = preload("res://FlameJet.tscn")
		var flame = flame_scene.instantiate() as FlameJet
		get_tree().current_scene.add_child(flame)
		flame.setup(global_position + direction * 28.0, direction, self)
		if _flamethrower_audio == null:
			_flamethrower_audio = AudioStreamPlayer2D.new()
			_flamethrower_audio.stream = ProceduralAudio.get_flamethrower_stream()
			_flamethrower_audio.volume_db = -15.0
			_flamethrower_audio.max_distance = 600.0
			add_child(_flamethrower_audio)
		if not _flamethrower_audio.playing:
			_flamethrower_audio.play()
		_trigger_muzzle_flash_3d()
		_refresh_weapon_ui()
		return

	var pellets := int(data.get("pellets", 1))
	var spread := float(data.get("spread", 0.0))
	var is_explosive: bool = (data.get("is_explosive", false) == true)
	var is_flame: bool = (data.get("is_flame", false) == true)
	
	for pellet_index in range(pellets):
		var ratio := 0.0 if pellets == 1 else float(pellet_index) / float(pellets - 1) - 0.5
		var shot_direction := direction.rotated(ratio * spread)
		var bullet = BULLET_SCENE.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.owner_body = self
		bullet.direction = shot_direction
		bullet.damage = int(data.get("damage", 15))
		bullet.speed = float(data.get("projectile_speed", 2000.0))
		bullet.tracer_color = data.get("tracer_color", Color.WHITE)
		bullet.is_explosive = is_explosive
		bullet.is_flame = is_flame
		bullet.global_position = global_position + shot_direction * 26.0
	
	_trigger_muzzle_flash_3d()
	
	# Som de tiro realista e encorpado com punch e sub-grave
	var vol: float = float(data.get("audio_volume_db", -2.0))
	_play_audio(ProceduralAudio.get_gunshot_stream(active_weapon_id), vol)
	
	var effects := get_tree().get_first_node_in_group("weapon_effects")
	if effects:
		effects.spawn_muzzle_flash(global_position + direction * 24.0, direction, data)
		if not is_explosive and not is_flame:
			effects.spawn_shell(global_position + direction * 20.0, direction, data)
	_alert_nearby_pedestrians()
	_refresh_weapon_ui()

func _alert_nearby_pedestrians() -> void:
	for ped in get_tree().get_nodes_in_group("pedestrian"):
		if is_instance_valid(ped) and ped != self:
			if global_position.distance_to(ped.global_position) < 450.0:
				if ped.has_method("panic"):
					ped.panic()

func _cycle_weapon(step: int) -> void:
	var order := WEAPON_CATALOG.get_order()
	var current := order.find(active_weapon_id)
	for offset in range(1, order.size() + 1):
		var candidate := WEAPON_CATALOG.get_weapon_id_at(current + step * offset)
		if weapon_inventory.get(candidate, false) == true:
			active_weapon_id = candidate
			_update_equipped_weapon_3d_mesh()
			_show_weapon_notice(String(WEAPON_CATALOG.get_weapon(candidate).get("label", candidate)))
			_refresh_weapon_ui()
			return

func _reload_active_weapon() -> void:
	var data := WEAPON_CATALOG.get_weapon(active_weapon_id)
	var ammo: Dictionary = weapon_ammo.get(active_weapon_id, {})
	var needed := int(data.get("magazine_size", 0)) - int(ammo.get("clip", 0))
	var moved := mini(needed, int(ammo.get("reserve", 0)))
	if moved > 0:
		ammo["clip"] = int(ammo.get("clip", 0)) + moved
		ammo["reserve"] = int(ammo.get("reserve", 0)) - moved
		weapon_ammo[active_weapon_id] = ammo
		_show_weapon_notice("RECARREGOU")

func buy_weapon(id: String) -> String:
	var data := WEAPON_CATALOG.get_weapon(id)
	if data.is_empty():
		return "ARMA INDISPONÍVEL"
	if weapon_inventory.get(id, false) == true:
		return "VOCÊ JÁ POSSUI ESTA ARMA"
	var price := int(data.get("price", 0))
	if money < price:
		return "DINHEIRO INSUFICIENTE"
	money -= price
	weapon_inventory[id] = true
	weapon_ammo[id] = {"clip": int(data.get("magazine_size", 0)), "reserve": int(data.get("starting_reserve", 0))}
	active_weapon_id = id
	_update_equipped_weapon_3d_mesh()
	_refresh_weapon_ui()
	_show_weapon_notice("COMPROU " + String(data.get("label", id)))
	return "COMPRA REALIZADA"

func buy_ammo(price: int) -> String:
	return buy_ammo_for_weapon(active_weapon_id, price)

func buy_ammo_for_weapon(id: String, price: int) -> String:
	var data := WEAPON_CATALOG.get_weapon(id)
	if data.is_empty():
		return "ARMA NÃO ENCONTRADA"
	var rounds := int(data.get("magazine_size", 0)) * 5
	return buy_ammo_amount(id, rounds, price)

func buy_ammo_amount(id: String, rounds: int, price: int) -> String:
	if money < price:
		return "DINHEIRO INSUFICIENTE"
	var data := WEAPON_CATALOG.get_weapon(id)
	if data.is_empty():
		return "ARMA NÃO ENCONTRADA"
	if not (weapon_inventory.get(id, false) == true):
		return "COMPRE A ARMA PRIMEIRO"
	var ammo: Dictionary = weapon_ammo.get(id, {"clip": 0, "reserve": 0})
	money -= price
	ammo["reserve"] = int(ammo.get("reserve", 0)) + rounds
	weapon_ammo[id] = ammo
	_refresh_weapon_ui()
	_show_weapon_notice("+%d BALAS (%s)" % [rounds, String(data.get("short_label", id))])
	return "MUNIÇÃO COMPRADA"

func buy_armor_amount(amount: int, price: int) -> String:
	if money < price:
		return "DINHEIRO INSUFICIENTE"
	if armor >= max_armor:
		return "COLETE JÁ ESTÁ NO MÁXIMO"
	money -= price
	armor = clampi(armor + amount, 0, max_armor)
	_refresh_weapon_ui()
	_show_weapon_notice("COLETE +%d%% (TOTAL: %d%%)" % [amount, armor])
	return "COLETE EQUIPADO"

func _refresh_weapon_ui() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_money(money)
		hud.update_health(health)
		hud.set_weapon_info(active_weapon_id, weapon_ammo.get(active_weapon_id, {}))
		hud.set_armor(armor, max_armor)
	if weapon_wheel:
		weapon_wheel.show_state(active_weapon_id, weapon_inventory, weapon_ammo)

func _show_weapon_notice(message: String) -> void:
	if weapon_wheel:
		weapon_wheel.show_notice(message)

func try_enter_vehicle() -> void:
	var cars = get_tree().get_nodes_in_group("vehicle")
	var closest_car = null
	var min_dist = 100.0
	for car in cars:
		if not car.has_method("enter_vehicle"):
			continue
		var dist = global_position.distance_to(car.global_position)
		if dist < min_dist:
			min_dist = dist
			closest_car = car
	if closest_car:
		closest_car.enter_vehicle(self)
