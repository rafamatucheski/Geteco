extends Node3D
class_name UrbanBuildingBase

const V1_PROFILE := preload("res://world/urban_detail/HarborV1BuildingProfile.gd")

## Base class for native 3D urban buildings.
## Builds optimized modular architecture with shared materials, accurate collision,
## and proper architectural features (cornices, roofs, stoops, fenestration).

var data: Dictionary = {}
var building_id: String = ""
var building_kind: String = ""
var building_size: Vector2 = Vector2(10.0, 10.0) # Width (X) and Depth (Z) in meters
var height: float = 4.5
var entrance_north: bool = false
var base_color: Color = Color("8b8d80")
var accent_color: Color = Color("b3955c")
var v1_palette: Dictionary = {}
var variant_seed := 0
var proper_name: String = ""
var visuals_root: Node3D
var collision_root: Node3D

func setup(p_data: Dictionary) -> void:
	data = p_data
	building_id = str(data.get("id", name))
	building_kind = str(data.get("kind", "office"))
	building_size = data.get("size", Vector2(12.0, 10.0))
	entrance_north = bool(data.get("entrance_north", false))
	accent_color = Color(data.get("color", "b3955c"))
	variant_seed = int(data.get("variant_seed", 0))
	v1_palette = V1_PROFILE.palette(building_kind,building_id,variant_seed,accent_color)
	base_color = v1_palette.front
	proper_name = str(data.original_name) if data.has("original_name") else UrbanSignage.extract_proper_name(building_id, str(data.get("name", "")))
	
	height = resolved_height(data)

static func resolved_height(source: Dictionary) -> float:
	var data := source
	var building_id := str(data.get("id",""))
	var building_kind := str(data.get("kind","office"))
	var variant_seed := int(data.get("variant_seed",0))
	var value := 4.5
	# Existing vertical conversion remains unchanged unless V1 publishes an
	# explicit override (Exchange/Civic). Generic heights are still an open
	# fidelity item and are not guessed from screen-space extrusion here.
	if data.has("height_override"):
		value = float(data.height_override)
	elif building_kind in ["brownstone", "rowhouse", "rowhouse_terrace", "l_shaped_block"]:
		value = 6.8
	elif building_kind in ["office", "police_precinct"]:
		value = 7.5
	elif building_kind in ["hospital"]:
		value = 8.0
	elif building_kind in ["warehouse", "warehouse_shop"]:
		value = 5.2
	elif building_kind in ["fire_station"]:
		value = 6.2
	elif building_kind in ["cobra_house"]:
		value = 3.6
	elif building_kind in ["garage"]:
		value = 4.2
	else:
		value = 4.6

	# Sem isso todo prédio do mesmo tipo tinha a mesma altura exata lado a
	# lado, o que lê como fileira repetida em vez de skyline de cidade.
	# Só entra quando a V1 não publicou uma altura autorada explícita.
	if not data.has("height_override"):
		value *= _height_variance_factor(building_id,building_kind,variant_seed)
	return value

## Fator determinístico (mesmo prédio sempre gera o mesmo resultado) que
## varia a altura por tipo: torres comerciais variam bastante (baixinha a
## bem mais alta que a vizinha), residências baixas variam pouco para não
## quebrar a linha de cornija da quadra.
static func _height_variance_factor(building_id: String, building_kind: String, variant_seed: int) -> float:
	var h := hash(building_id + "|height|" + str(variant_seed))
	var t := (h % 1000) / 1000.0 # 0.0..1.0 determinístico
	match building_kind:
		"office", "police_precinct", "hospital", "fire_station":
			return lerpf(0.72, 1.85, t) # mistura prédio baixo e torre alta na mesma rua
		"warehouse", "warehouse_shop", "garage":
			return lerpf(0.85, 1.25, t)
		"brownstone", "rowhouse", "l_shaped_block":
			return lerpf(0.92, 1.12, t) # variação sutil, mantém a fileira legível
		_:
			return lerpf(0.85, 1.30, t)

func _ready() -> void:
	if visuals_root == null:
		visuals_root = Node3D.new()
		visuals_root.name = "Visuals"
		add_child(visuals_root)
	
	if collision_root == null:
		collision_root = Node3D.new()
		collision_root.name = "Collision"
		add_child(collision_root)
	
	build()
	
	if entrance_north:
		# Mirror/rotate visuals and entrance layout if entrance is on North
		visuals_root.rotation.y = PI
		collision_root.rotation.y = PI

func build() -> void:
	# Overridden by concrete archetype classes
	_build_default_box()

# --- Fenestration & Material Variation ---

## Retorna o material de parede já texturizado (ruído quebra a cor chapada).
func wall_material(color: Color, roughness: float = 0.86) -> StandardMaterial3D:
	return UrbanMaterials.textured_wall(color, roughness)

## Escolhe, de forma determinística (mesmo prédio sempre gera o mesmo
## resultado), se uma janela específica está acesa à noite. `local_key`
## identifica a janela dentro do prédio (ex.: "f1_side-1.2"). `lit_ratio`
## controla a fração de janelas acesas (padrão ~1 em 3).
func is_window_lit(local_key: String, lit_ratio: float = 0.32) -> bool:
	var h := hash(building_id + "|" + local_key + "|" + str(variant_seed))
	return (h % 1000) / 1000.0 < lit_ratio

## Material de vidro pronto para uma janela específica: aceso ou apagado,
## de acordo com is_window_lit(). Usar em vez de UrbanMaterials.glass_window()
## direto para dar vida noturna aos prédios.
func window_glass_material(local_key: String, lit_ratio: float = 0.32) -> StandardMaterial3D:
	if is_window_lit(local_key, lit_ratio):
		var warm := hash(building_id + local_key) % 4 != 0
		return UrbanMaterials.glass_window_lit(warm)
	return UrbanMaterials.glass_window()

func _build_default_box() -> void:
	# Fallback box volume
	var half_h := height * 0.5
	add_solid_box(visuals_root, "MainBody", Vector3(0, half_h, 0), Vector3(building_size.x, height, building_size.y), UrbanMaterials.material_for_color(base_color))
	add_roof_parapet(visuals_root, height)
	add_mesh_box(visuals_root,"V1RoofSurface",Vector3(0,height+.03,0),Vector3(building_size.x-.52,.06,building_size.y-.52),UrbanMaterials.material_for_color(v1_palette.get("roof",Color("5a4840")),.92))

# --- Geometry & Collision Helpers ---

func add_solid_box(parent: Node3D, p_name: String, center: Vector3, size: Vector3, mat: Material = null) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = p_name
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.position = center
	if mat != null:
		mesh_inst.material_override = mat
	parent.add_child(mesh_inst)
	
	# Create physical collision matching exact solid bounds
	var body := StaticBody3D.new()
	body.name = p_name + "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	
	var col_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col_shape.shape = shape
	col_shape.position = center
	body.add_child(col_shape)
	
	collision_root.add_child(body)
	return mesh_inst

func add_mesh_box(parent: Node3D, p_name: String, center: Vector3, size: Vector3, mat: Material = null) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = p_name
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.position = center
	if mat != null:
		mesh_inst.material_override = mat
	parent.add_child(mesh_inst)
	return mesh_inst

# --- Architectural Feature Helpers ---

func add_roof_parapet(parent: Node3D, roof_y: float, rim_h: float = 0.42, rim_thick: float = 0.24, mat: Material = null) -> void:
	var parapet_mat = mat if mat != null else UrbanMaterials.trim_stone()
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	var py := roof_y + rim_h * 0.5
	
	# Front & Back rims
	add_mesh_box(parent, "ParapetSouth", Vector3(0, py, half_d - rim_thick * 0.5), Vector3(building_size.x, rim_h, rim_thick), parapet_mat)
	add_mesh_box(parent, "ParapetNorth", Vector3(0, py, -half_d + rim_thick * 0.5), Vector3(building_size.x, rim_h, rim_thick), parapet_mat)
	
	# Left & Right rims
	var inner_d := building_size.y - rim_thick * 2.0
	add_mesh_box(parent, "ParapetWest", Vector3(-half_w + rim_thick * 0.5, py, 0), Vector3(rim_thick, rim_h, inner_d), parapet_mat)
	add_mesh_box(parent, "ParapetEast", Vector3(half_w - rim_thick * 0.5, py, 0), Vector3(rim_thick, rim_h, inner_d), parapet_mat)

func add_roof_gravel(parent: Node3D, roof_y: float, inset: float = 0.26) -> MeshInstance3D:
	var size := Vector3(building_size.x - inset * 2.0, 0.05, building_size.y - inset * 2.0)
	return add_mesh_box(parent, "RoofSurface", Vector3(0, roof_y + 0.025, 0), size, UrbanMaterials.roof_tar())

func add_cornice(parent: Node3D, y: float, projection: float = 0.35, h: float = 0.38, dentils: bool = true, mat: Material = null) -> void:
	var c_mat = mat if mat != null else UrbanMaterials.trim_stone()
	var front_z := building_size.y * 0.5 + projection * 0.5
	var cornice_w := building_size.x + 0.2
	
	# Main projecting crown molding
	add_mesh_box(parent, "CorniceCrown", Vector3(0, y, front_z), Vector3(cornice_w, h, projection), c_mat)
	# Supporting under-bed molding
	add_mesh_box(parent, "CorniceBed", Vector3(0, y - h * 0.5 - 0.06, front_z - 0.05), Vector3(cornice_w - 0.08, 0.12, projection * 0.7), c_mat)
	
	# Dentil blocks if requested
	if dentils and building_size.x > 3.0:
		var dentil_mat := UrbanMaterials.trim_dark()
		var dentil_w := 0.18
		var dentil_h := 0.14
		var dentil_d := 0.16
		var count := int((building_size.x - 0.4) / 0.45)
		var step := (building_size.x - 0.6) / float(maxi(count - 1, 1))
		for i in count:
			var dx := -building_size.x * 0.5 + 0.3 + float(i) * step
			add_mesh_box(parent, "Dentil_%d" % i, Vector3(dx, y - h * 0.3, front_z + 0.04), Vector3(dentil_w, dentil_h, dentil_d), dentil_mat)

func add_water_tower(parent: Node3D, at: Vector3) -> Node3D:
	var tower := Node3D.new()
	tower.name = "RooftopWaterTower"
	tower.position = at
	
	# Steel trestle legs (4 corner posts)
	var leg_mat := UrbanMaterials.metal_iron()
	var leg_h := 1.8
	var leg_span := 1.4
	for lx in [-leg_span * 0.5, leg_span * 0.5]:
		for lz in [-leg_span * 0.5, leg_span * 0.5]:
			add_mesh_box(tower, "Leg", Vector3(lx, leg_h * 0.5, lz), Vector3(0.10, leg_h, 0.10), leg_mat)
	
	# Cross braces
	add_mesh_box(tower, "PlatformBase", Vector3(0, leg_h, 0), Vector3(leg_span + 0.3, 0.12, leg_span + 0.3), leg_mat)
	
	# Cylindrical/faceted wood tank
	var tank_mat := UrbanMaterials.wood_tank()
	var tank_h := 1.6
	var tank_d := 1.5
	var tank_center_y := leg_h + 0.06 + tank_h * 0.5
	add_mesh_box(tower, "WaterTankBody", Vector3(0, tank_center_y, 0), Vector3(tank_d, tank_h, tank_d), tank_mat)
	
	# Metal hoops
	for hy in [tank_center_y - 0.45, tank_center_y, tank_center_y + 0.45]:
		add_mesh_box(tower, "Hoop", Vector3(0, hy, 0), Vector3(tank_d + 0.05, 0.05, tank_d + 0.05), leg_mat)
	
	# Conical roof cap
	add_mesh_box(tower, "RoofCap", Vector3(0, tank_center_y + tank_h * 0.5 + 0.25, 0), Vector3(tank_d + 0.2, 0.45, tank_d + 0.2), UrbanMaterials.roof_tin_rusty())
	
	parent.add_child(tower)
	return tower

func add_hvac_chiller(parent: Node3D, at: Vector3, size: Vector3 = Vector3(1.8, 0.85, 1.4)) -> Node3D:
	var hvac := Node3D.new()
	hvac.name = "HVAC_Chiller"
	hvac.position = at
	
	var body_mat := UrbanMaterials.metal_steel()
	var dark_mat := UrbanMaterials.trim_dark()
	
	# Chiller base cabinet
	add_mesh_box(hvac, "Cabinet", Vector3(0, size.y * 0.5, 0), size, body_mat)
	
	# Louvered vents on sides
	add_mesh_box(hvac, "LouverLeft", Vector3(-size.x * 0.5 - 0.02, size.y * 0.5, 0), Vector3(0.04, size.y * 0.7, size.z * 0.8), dark_mat)
	add_mesh_box(hvac, "LouverRight", Vector3(size.x * 0.5 + 0.02, size.y * 0.5, 0), Vector3(0.04, size.y * 0.7, size.z * 0.8), dark_mat)
	
	# Top dual exhaust fan cowls
	var fan_r := size.x * 0.24
	for side in [-fan_r * 1.1, fan_r * 1.1]:
		add_mesh_box(hvac, "FanCowling", Vector3(side, size.y + 0.06, 0), Vector3(fan_r * 2.0, 0.12, fan_r * 2.0), dark_mat)
	
	parent.add_child(hvac)
	return hvac

func add_chimney(parent: Node3D, at: Vector3, chim_h: float = 1.5, flues: int = 2) -> Node3D:
	var chim := Node3D.new()
	chim.name = "ChimneyStack"
	chim.position = at
	
	var chim_w := 0.75 + float(flues - 1) * 0.45
	var chim_d := 0.75
	
	# Masonry stack
	add_mesh_box(chim, "BrickShaft", Vector3(0, chim_h * 0.5, 0), Vector3(chim_w, chim_h, chim_d), UrbanMaterials.brick_red())
	# Stone cap
	add_mesh_box(chim, "StoneCap", Vector3(0, chim_h + 0.06, 0), Vector3(chim_w + 0.12, 0.12, chim_d + 0.12), UrbanMaterials.trim_stone())
	
	# Terracotta clay flue pots
	var flue_mat := UrbanMaterials.terracotta_flue()
	var pot_step := (chim_w - 0.4) / float(maxi(flues, 1))
	for i in flues:
		var px := -chim_w * 0.5 + 0.2 + float(i) * pot_step + pot_step * 0.5
		add_mesh_box(chim, "FluePot_%d" % i, Vector3(px, chim_h + 0.25, 0), Vector3(0.24, 0.35, 0.24), flue_mat)
	
	parent.add_child(chim)
	return chim

func add_roof_access_bulkhead(parent: Node3D, at: Vector3, size: Vector3 = Vector3(1.6, 1.8, 2.0)) -> Node3D:
	var bulkhead := Node3D.new()
	bulkhead.name = "RoofAccessBulkhead"
	bulkhead.position = at
	
	add_mesh_box(bulkhead, "Housing", Vector3(0, size.y * 0.5, 0), size, UrbanMaterials.wall_concrete())
	add_mesh_box(bulkhead, "RoofCap", Vector3(0, size.y + 0.06, 0), Vector3(size.x + 0.15, 0.12, size.z + 0.15), UrbanMaterials.roof_tin())
	# Metal access door
	add_mesh_box(bulkhead, "Door", Vector3(0, size.y * 0.45, size.z * 0.5 + 0.02), Vector3(size.x * 0.6, size.y * 0.8, 0.05), UrbanMaterials.metal_steel())
	
	parent.add_child(bulkhead)
	return bulkhead
