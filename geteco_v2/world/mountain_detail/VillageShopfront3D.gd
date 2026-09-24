extends Node3D
class_name VillageShopfront3D

## 3D exterior model of the Mountain Village winter outfitters ("Casacos da Vila").
## Reconstructs the facade from MountainTransitArchitecture3D.gd while strictly obeying AGENTS.md rules:
## 1. Facade signage displays exclusively the proper name: "Casacos da Vila".
## 2. Display window features mannequins with natural human proportions dressed in winter apparel.
## 3. Native StaticBody3D collision on layer 1, mask 0, preserving open entrance steps.

@export var shop_size: Vector2 = Vector2(10.1, 4.1) # ~162 x 66 px
@export var shop_height: float = 3.8

func _ready() -> void:
	build()

func build() -> void:
	for child in get_children():
		child.queue_free()
	
	var wall_mat := MountainMaterials.get_mat("outfitters_timber", Color("#6e4f3a"), 0.86)
	var trim_mat := MountainMaterials.wood_beam()
	var stone_mat := MountainMaterials.stone_river()
	var roof_mat := MountainMaterials.wood_shingle()
	var snow_mat := MountainMaterials.snow_fresh()
	var glass_mat := MountainMaterials.glass_clear()
	var brass_mat := MountainMaterials.metal_brass()
	var awning_mat := MountainMaterials.mannequin_cloth(Color("#934336"))
	
	var half_w := shop_size.x * 0.5
	var half_d := shop_size.y * 0.5
	var body_h := 3.0
	
	# Solid StaticBody3D for shop building body
	var body := StaticBody3D.new()
	body.name = "ShopCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(shop_size.x, body_h, shop_size.y)
	col.shape = box_shape
	col.position = Vector3(0, body_h * 0.5 + 0.15, 0)
	body.add_child(col)
	add_child(body)
	
	# 1. Stone Foundation Slab
	_add_box("FoundationPlinth", Vector3(0, 0.10, 0), Vector3(shop_size.x + 0.4, 0.20, shop_size.y + 0.4), stone_mat)
	
	# 2. Main Timber Walls
	_add_box("TimberWalls", Vector3(0, body_h * 0.5 + 0.20, 0), Vector3(shop_size.x, body_h, shop_size.y), wall_mat)
	
	# Corner pillars
	for cx in [-half_w, half_w]:
		_add_box("CornerPillar", Vector3(cx, body_h * 0.5 + 0.20, half_d), Vector3(0.20, body_h, 0.20), trim_mat)
		_add_box("CornerPillarRear", Vector3(cx, body_h * 0.5 + 0.20, -half_d), Vector3(0.20, body_h, 0.20), trim_mat)
	
	# 3. Customer Entrance Door (Center front: +Z)
	var door_w := 1.20
	var door_h := 2.25
	
	# Stone entrance step
	_add_box("EntranceStep", Vector3(0, 0.08, half_d + 0.40), Vector3(1.8, 0.16, 0.60), stone_mat)
	
	# Recessed doorway
	_add_box("DoorFrame", Vector3(0, door_h * 0.5 + 0.20, half_d + 0.02), Vector3(door_w + 0.20, door_h + 0.14, 0.10), trim_mat)
	_add_box("DoorWood", Vector3(0, door_h * 0.5 + 0.20, half_d + 0.04), Vector3(door_w, door_h, 0.06), trim_mat)
	var door_glass := _add_box("DoorGlass", Vector3(0, door_h * 0.6 + 0.20, half_d + 0.06), Vector3(door_w * 0.65, door_h * 0.5, 0.02), glass_mat)
	door_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_box("DoorHandle", Vector3(door_w * 0.38, 1.10 + 0.20, half_d + 0.08), Vector3(0.04, 0.22, 0.06), brass_mat)
	
	# 4. Flanking Large Display Windows (Left and Right)
	var win_w := 3.2
	var win_h := 1.9
	var win_y := 1.65 + 0.20
	
	for side in [-1.0, 1.0]:
		var wx: float = side * (half_w * 0.55)
		# Window surround frame
		_add_box("DisplayFrame", Vector3(wx, win_y, half_d + 0.03), Vector3(win_w + 0.16, win_h + 0.16, 0.12), trim_mat)
		# Display window glass
		var win_glass := _add_box("DisplayGlass", Vector3(wx, win_y, half_d + 0.06), Vector3(win_w, win_h, 0.02), glass_mat)
		win_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Display stage platform inside window
		_add_box("DisplayStage", Vector3(wx, 0.35 + 0.20, half_d - 0.35), Vector3(win_w - 0.2, 0.30, 0.70), trim_mat)
	
	# 5. Natural Human Proportion Mannequins in Display Windows
	# Obeying AGENTS.md rule: "Vitrines de roupas devem usar manequins vestidos com proporções naturais, em vez de peças de roupa gigantes e isoladas."
	_build_display_mannequin(Vector3(-half_w * 0.55, 0.50 + 0.20, half_d - 0.35), Color("#8c3830"), Color("#2c3e50"))
	_build_display_mannequin(Vector3(half_w * 0.55, 0.50 + 0.20, half_d - 0.35), Color("#3e6b5c"), Color("#4a3b32"))
	
	# 6. Overhead Awning / Canopy with Snow Layer
	var awning_y := body_h + 0.15
	var awning_w := shop_size.x + 0.4
	var awning_d := 1.8
	var awning := _add_box("AwningFabric", Vector3(0, awning_y, half_d + awning_d * 0.45), Vector3(awning_w, 0.10, awning_d), awning_mat)
	awning.rotation.x = 0.12
	var awning_snow := _add_box("AwningSnow", Vector3(0, awning_y + 0.06, half_d + awning_d * 0.45), Vector3(awning_w + 0.04, 0.08, awning_d + 0.04), snow_mat)
	awning_snow.rotation.x = 0.12
	
	# Cantilever brackets supporting awning
	for side in [-1.0, 1.0]:
		var bx: float = side * (half_w - 0.35)
		_add_box("Bracket", Vector3(bx, awning_y - 0.25, half_d + 0.45), Vector3(0.12, 0.15, 1.10), trim_mat)
	
	# 7. Facade Signage: ONLY PROPER NAME ("Casacos da Vila")
	# Strictly obeying AGENTS.md: "Em fachadas, deixe somente o nome próprio do estabelecimento. Não acrescente categorias, slogans, legendas..."
	var sign_board := _add_box("SignBoard", Vector3(0, awning_y + 0.55, half_d + 0.12), Vector3(minf(shop_size.x * 0.65, 5.2), 0.70, 0.08), MountainMaterials.sign_timber())
	_add_box("SignBorder", Vector3(0, awning_y + 0.55, half_d + 0.10), Vector3(minf(shop_size.x * 0.65, 5.2) + 0.08, 0.76, 0.06), trim_mat)
	
	var label := Label3D.new()
	label.name = "ShopSignLabel"
	label.text = "Casacos da Vila"
	label.font_size = 46
	label.pixel_size = 0.007
	label.outline_size = 0
	label.modulate = Color("#f4ede0")
	label.position = Vector3(0, awning_y + 0.55, half_d + 0.18)
	add_child(label)
	
	# 8. Main Pitched Roof with Snow
	var pitch := 0.42
	var roof_overhang_w := shop_size.x + 0.8
	var roof_overhang_d := shop_size.y + 0.8
	var ridge_y := body_h + 0.20 + 1.25
	
	for side in [-1.0, 1.0]:
		var panel_w := roof_overhang_d * 0.56
		var offset_z: float = side * (roof_overhang_d * 0.26)
		var roof_y := body_h + 0.20 + 0.60
		
		var deck := _add_box("RoofDeck", Vector3(0, roof_y, offset_z), Vector3(roof_overhang_w, 0.12, panel_w), roof_mat)
		deck.rotation.x = -side * pitch
		
		var snow := _add_box("RoofSnow", Vector3(0, roof_y + 0.08, offset_z), Vector3(roof_overhang_w + 0.06, 0.14, panel_w + 0.04), snow_mat)
		snow.rotation.x = -side * pitch
	
	_add_box("RidgeCap", Vector3(0, ridge_y + 0.12, 0), Vector3(roof_overhang_w + 0.08, 0.14, 0.35), snow_mat)

## Builds a naturally proportioned human mannequin wearing winter parka and trousers.
func _build_display_mannequin(pos: Vector3, coat_color: Color, pants_color: Color) -> void:
	var mannequin_root := Node3D.new()
	mannequin_root.name = "Mannequin"
	mannequin_root.position = pos
	add_child(mannequin_root)
	
	var coat_mat := MountainMaterials.mannequin_cloth(coat_color)
	var pants_mat := MountainMaterials.mannequin_cloth(pants_color)
	var skin_mat := MountainMaterials.get_mat("mannequin_stand", Color("#d5cec0"), 0.70)
	var boot_mat := MountainMaterials.wood_beam()
	
	# Round stand base
	_add_cylinder_to(mannequin_root, "Stand", Vector3(0, 0.02, 0), 0.24, 0.04, skin_mat)
	
	# Legs / Trousers (natural human height: legs ~0.80m)
	for side in [-1.0, 1.0]:
		var lx: float = side * 0.10
		# Leg
		_add_box_to(mannequin_root, "Leg", Vector3(lx, 0.42, 0), Vector3(0.12, 0.75, 0.12), pants_mat)
		# Winter boots
		_add_box_to(mannequin_root, "Boot", Vector3(lx, 0.08, 0.04), Vector3(0.13, 0.16, 0.22), boot_mat)
	
	# Torso wearing Winter Parka (height ~0.65m, width ~0.42m)
	_add_box_to(mannequin_root, "ParkaTorso", Vector3(0, 1.10, 0), Vector3(0.44, 0.65, 0.28), coat_mat)
	# Fur trim hood collar
	_add_box_to(mannequin_root, "ParkaCollar", Vector3(0, 1.40, -0.02), Vector3(0.32, 0.12, 0.26), MountainMaterials.snow_compact())
	
	# Arms
	for side in [-1.0, 1.0]:
		var ax: float = side * 0.27
		_add_box_to(mannequin_root, "Arm", Vector3(ax, 1.05, 0), Vector3(0.10, 0.55, 0.11), coat_mat)
	
	# Head form (abstract mannequin head)
	_add_cylinder_to(mannequin_root, "Head", Vector3(0, 1.55, 0), 0.10, 0.22, skin_mat)

func _add_box(node_name: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _add_box_to(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _add_cylinder_to(parent: Node3D, node_name: String, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi
