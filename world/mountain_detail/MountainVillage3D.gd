extends Node3D
class_name MountainVillage3D

## Complete 3D exterior settlement presentation of the Mountain Transit Village.
## Located at mountain-local coordinates ORIGIN = (7560, -1650), matching V1 geography at 16 px/metre.
## Assembles the passenger terminal, coach berth 01, outfitters shop ("Casacos da Vila"),
## 4 alpine chalets, central plaza with community brazier, street lamps, wood stores,
## plowed walkways, and rustic post-and-rail fences.
## All doors, pedestrian walkways, and bus approaches remain 100% open and unblocked.

const SCALE := 1.0 / 16.0
const ORIGIN := Vector2(7560.0, -1650.0)

var use_original_sections := false
var terminal: MountainTerminal3D
var shop: VillageShopfront3D
var chalets: Array[MountainChalet3D] = []
var brazier: Node3D
var fences: Node3D

func _ready() -> void:
	build_village()

func build_village() -> void:
	if use_original_sections:
		var original = preload("res://world/mountain_detail/OriginalVillageArchitecture.gd").new()
		original.name = "OriginalVillageArchitecture"
		original.scale = Vector3(18.0/16.0,1,18.0*.76822128/16.0)
		add_child(original)
		return
	for child in get_children():
		child.queue_free()
	
	# 1. Plowed stone/gravel pathways connecting village hubs
	_build_pathways()
	
	# 2. Mini-Terminal Office and Coach Berth 01
	_build_terminal()
	
	# 3. Winter Outfitters ("Casacos da Vila")
	_build_shop()
	
	# 4. Four Alpine Chalets at authentic coordinates
	_build_chalets()
	
	# 5. Central Plaza and Community Brazier (Heat Source)
	_build_plaza_and_brazier()
	
	# 6. Village Amenities (Lamps, Wood Stores, Benches)
	_build_amenities()
	
	# 7. Perimeter and Slope Fences
	_build_fences()

func _at_local(mountain_pt: Vector2) -> Vector3:
	var delta := mountain_pt - ORIGIN
	return Vector3(delta.x * SCALE, 0.0, delta.y * SCALE)

func _build_pathways() -> void:
	# Network of plowed stone and packed snow paths connecting key points
	var paving_mat := MountainMaterials.stone_paving()
	var stone_mat := MountainMaterials.stone_river()
	
	# Central Plaza flagstone slab (7592, -1624, 108, 108)
	var plaza_rect := Rect2(Vector2(7592, -1624), Vector2(108, 108))
	var p_center := _at_local(plaza_rect.get_center())
	var p_size := Vector3(plaza_rect.size.x * SCALE, 0.04, plaza_rect.size.y * SCALE)
	_add_box("PlazaPaving", p_center, p_size, paving_mat)
	
	# Paths from MountainTransitVillageLayout.gd:
	# Bus door (7537, -1730) -> Plaza (7630, -1590)
	_build_path_strip(Vector2(7537, -1730), Vector2(7550, -1718), 2.2, paving_mat)
	_build_path_strip(Vector2(7550, -1718), Vector2(7550, -1590), 2.2, paving_mat)
	_build_path_strip(Vector2(7550, -1590), Vector2(7630, -1590), 2.4, paving_mat)
	
	# Plaza -> Shop door (7790, -1594)
	_build_path_strip(Vector2(7630, -1590), Vector2(7790, -1590), 2.4, paving_mat)
	_build_path_strip(Vector2(7790, -1590), Vector2(7790, -1594), 2.2, paving_mat)
	
	# Plaza -> Waiting area / Terminal door (7460, -1614)
	_build_path_strip(Vector2(7630, -1590), Vector2(7460, -1590), 2.4, paving_mat)
	_build_path_strip(Vector2(7460, -1590), Vector2(7460, -1614), 2.2, paving_mat)
	
	# Plaza -> Chalets 1..4 walkways
	var cabin_doors := [Vector2(7405, -1436), Vector2(7545, -1436), Vector2(7725, -1396), Vector2(7870, -1396)]
	var cabin_centers := [Vector2(7405, -1480), Vector2(7545, -1480), Vector2(7725, -1440), Vector2(7870, -1440)]
	for i in 4:
		var door: Vector2 = cabin_doors[i]
		var side_x: float = cabin_centers[i].x + 70.0
		_build_path_strip(Vector2(7630, -1590), Vector2(side_x, -1590), 2.0, paving_mat)
		_build_path_strip(Vector2(side_x, -1590), Vector2(side_x, door.y + 14), 2.0, paving_mat)
		_build_path_strip(Vector2(side_x, door.y + 14), door + Vector2(0, 14), 1.8, paving_mat)
		_build_path_strip(door + Vector2(0, 14), door, 1.8, stone_mat)

func _build_path_strip(a_m: Vector2, b_m: Vector2, width: float, mat: Material) -> void:
	var a := _at_local(a_m)
	var b := _at_local(b_m)
	var delta := b - a
	var length_value := delta.length()
	if length_value < 0.1:
		return
	var center := (a + b) * 0.5
	var angle := atan2(delta.x, delta.z)
	var strip := _add_box("PathStrip", center + Vector3(0, 0.02, 0), Vector3(width, 0.02, length_value), mat)
	strip.rotation.y = angle
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_terminal() -> void:
	# Local center: (7457.5, -1641.5)
	terminal = MountainTerminal3D.new()
	terminal.name = "VillageTerminal"
	terminal.position = _at_local(Vector2(7457.5, -1641.5))
	add_child(terminal)

func _build_shop() -> void:
	# Local center: (7790, -1640)
	shop = VillageShopfront3D.new()
	shop.name = "VillageOutfittersShop"
	shop.position = _at_local(Vector2(7790, -1640))
	add_child(shop)

func _build_chalets() -> void:
	var centers := [
		Vector2(7405, -1480), # Chalet 1
		Vector2(7545, -1480), # Chalet 2
		Vector2(7725, -1440), # Chalet 3
		Vector2(7870, -1440)  # Chalet 4
	]
	for i in centers.size():
		var chalet := MountainChalet3D.new()
		chalet.name = "VillageChalet_%d" % (i + 1)
		chalet.variant_index = i
		chalet.position = _at_local(centers[i])
		add_child(chalet)
		chalets.append(chalet)

func _build_plaza_and_brazier() -> void:
	# Community Brazier at (7650, -1553)
	var brazier_pos := _at_local(Vector2(7650, -1553))
	brazier = Node3D.new()
	brazier.name = "VillageCommunityBrazier"
	brazier.position = brazier_pos
	brazier.add_to_group("heat_source")
	add_child(brazier)
	
	var stone_mat := MountainMaterials.stone_river()
	var iron_mat := MountainMaterials.metal_iron()
	var ember_mat := MountainMaterials.brazier_coals()
	
	# Solid StaticBody3D for brazier base
	var body := StaticBody3D.new()
	body.name = "BrazierCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.65
	cyl.height = 1.3
	col.shape = cyl
	col.position = Vector3(0, 0.65, 0)
	body.add_child(col)
	brazier.add_child(body)
	
	# Chiseled stone pedestal
	_add_box_to(brazier, "Pedestal", Vector3(0, 0.20, 0), Vector3(1.10, 0.40, 1.10), stone_mat)
	
	# Cast iron brazier bowl
	_add_cylinder_to(brazier, "IronBowl", Vector3(0, 0.65, 0), 0.58, 0.50, iron_mat)
	
	# Glowing embers and charcoal
	_add_cylinder_to(brazier, "Embers", Vector3(0, 0.88, 0), 0.50, 0.12, ember_mat)
	
	# Subtle non-shadow warm point light for campfire illumination
	var fire_light := OmniLight3D.new()
	fire_light.name = "BrazierGlow"
	fire_light.light_color = Color("#f39c12")
	fire_light.light_energy = 1.6
	fire_light.omni_range = 7.5
	fire_light.shadow_enabled = false # Strictly no dynamic shadows
	fire_light.position = Vector3(0, 1.1, 0)
	brazier.add_child(fire_light)

func _build_amenities() -> void:
	# 1. Village Street Lamps at 4 original points
	var lamp_points := [
		Vector2(7384, -1570),
		Vector2(7578, -1532),
		Vector2(7908, -1565),
		Vector2(7650, -1364)
	]
	for idx in lamp_points.size():
		var l_pos := _at_local(lamp_points[idx])
		_build_street_lamp(l_pos, idx)
	
	# 2. Wood Storage Shelters at 3 original points
	var wood_store_points := [
		Vector2(7334, -1502),
		Vector2(7932, -1358),
		Vector2(7613, -1390)
	]
	for idx in wood_store_points.size():
		var w_pos := _at_local(wood_store_points[idx])
		_build_wood_store(w_pos, idx)
	
	# 3. Wooden Plaza Benches at original points (7646, -1508) and (7678, -1560)
	for b_pt in [Vector2(7646, -1508), Vector2(7678, -1560)]:
		var b_pos := _at_local(b_pt)
		_build_plaza_bench(b_pos)

func _build_street_lamp(pos: Vector3, idx: int) -> void:
	var lamp_root := Node3D.new()
	lamp_root.name = "VillageLamp_%d" % idx
	lamp_root.position = pos
	add_child(lamp_root)
	
	var pole_mat := MountainMaterials.wood_beam()
	var iron_mat := MountainMaterials.metal_iron()
	var glow_mat := MountainMaterials.glass_warm()
	var snow_mat := MountainMaterials.snow_fresh()
	
	# Solid collision
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.25, 3.4, 0.25)
	col.shape = box
	col.position = Vector3(0, 1.7, 0)
	body.add_child(col)
	lamp_root.add_child(body)
	
	# Wooden post
	_add_box_to(lamp_root, "LampPost", Vector3(0, 1.6, 0), Vector3(0.16, 3.2, 0.16), pole_mat)
	# Wrought iron lantern housing
	_add_box_to(lamp_root, "LanternFrame", Vector3(0, 3.25, 0), Vector3(0.42, 0.48, 0.42), iron_mat)
	# Amber glowing glass
	var glass := _add_box_to(lamp_root, "LanternGlass", Vector3(0, 3.25, 0), Vector3(0.34, 0.40, 0.34), glow_mat)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Snow cap on lantern
	_add_box_to(lamp_root, "LanternSnow", Vector3(0, 3.55, 0), Vector3(0.52, 0.12, 0.52), snow_mat)

func _build_wood_store(pos: Vector3, idx: int) -> void:
	var store_root := Node3D.new()
	store_root.name = "VillageWoodStore_%d" % idx
	store_root.position = pos
	add_child(store_root)
	
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.85, 1.25, 0.95)
	col.shape = box
	col.position = Vector3(0, 0.62, 0)
	body.add_child(col)
	store_root.add_child(body)
	
	# Rustic wooden shed bin
	_add_box_to(store_root, "WoodBin", Vector3(0, 0.55, 0), Vector3(1.75, 1.10, 0.85), MountainMaterials.wood_beam())
	# Stacked logs inside
	for i in 6:
		var lx: float = -0.55 + float(i % 3) * 0.55
		# Whole-number grouping/index; preserve integer truncation and precision.
		@warning_ignore("integer_division")
		var ly: float = 0.25 + float(i / 3) * 0.40
		_add_box_to(store_root, "Log", Vector3(lx, ly, 0), Vector3(0.50, 0.28, 0.80), MountainMaterials.wood_log())
	# Snow layer on roof
	_add_box_to(store_root, "StoreSnow", Vector3(0, 1.15, 0), Vector3(1.90, 0.14, 1.00), MountainMaterials.snow_fresh())

func _build_plaza_bench(pos: Vector3) -> void:
	var bench_root := Node3D.new()
	bench_root.name = "PlazaBench"
	bench_root.position = pos
	add_child(bench_root)
	
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 0.8, 0.6)
	col.shape = box
	col.position = Vector3(0, 0.4, 0)
	body.add_child(col)
	bench_root.add_child(body)
	
	var b_mat := MountainMaterials.wood_bench()
	_add_box_to(bench_root, "Seat", Vector3(0, 0.45, 0), Vector3(1.75, 0.08, 0.48), b_mat)
	_add_box_to(bench_root, "Back", Vector3(0, 0.75, -0.22), Vector3(1.75, 0.38, 0.06), b_mat)
	for side in [-1.0, 1.0]:
		_add_box_to(bench_root, "Leg", Vector3(side * 0.72, 0.22, 0), Vector3(0.10, 0.44, 0.42), MountainMaterials.wood_beam())

func _build_fences() -> void:
	fences = Node3D.new()
	fences.name = "VillageFences"
	add_child(fences)
	
	# Perimeter fences along the slopes and clearing boundaries (derived from clearing outline):
	# (7315,-1510) -> (7340,-1720) [West slope]
	_add_fence_seg(Vector2(7315, -1510), Vector2(7340, -1720))
	# (7360,-1385) -> (7315,-1510) [Southwest boundary]
	_add_fence_seg(Vector2(7360, -1385), Vector2(7315, -1510))
	# (7640,-1345) -> (7360,-1385) [South slope below chalets]
	_add_fence_seg(Vector2(7640, -1345), Vector2(7360, -1385))
	# (7860,-1325) -> (7640,-1345) [Southeast slope]
	_add_fence_seg(Vector2(7860, -1325), Vector2(7640, -1345))
	# (7960,-1370) -> (7860,-1325) [East edge]
	_add_fence_seg(Vector2(7960, -1370), Vector2(7860, -1325))
	# (7955,-1600) -> (7960,-1370) [East forest barrier]
	_add_fence_seg(Vector2(7955, -1600), Vector2(7960, -1370))

func _add_fence_seg(a_m: Vector2, b_m: Vector2) -> void:
	var a := _at_local(a_m)
	var b := _at_local(b_m)
	var fence := MountainFence3D.new()
	fence.build_segment(a, b)
	fences.add_child(fence)

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
	cm.radial_segments = 14
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi
