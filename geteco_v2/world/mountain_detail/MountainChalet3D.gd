extends Node3D
class_name MountainChalet3D

## High-detail 3D Alpine Chalet model for the Mountain Pass village residences.
## Features stone foundation plinths, rustic horizontal cedar log walls, gabled snow roof with dormers,
## fieldstone chimney with snow cap, entrance porch steps, and firewood storage.
## Native StaticBody3D collision on layer 1, mask 0.

@export var variant_index: int = 0
@export var chalet_size: Vector2 = Vector2(6.5, 4.2) # ~104 x 62 px
@export var chalet_height: float = 3.6

const VARIANT_COLORS: Array[Color] = [
	Color("#775a43"), # Chalet 01 - Warm Cedar
	Color("#684645"), # Chalet 02 - Reddish Timber
	Color("#465e69"), # Chalet 03 - Alpine Slate Blue
	Color("#626747"), # Chalet 04 - Forest Moss Green
]

func _ready() -> void:
	build()

func build() -> void:
	for child in get_children():
		child.queue_free()
	
	var wall_color := VARIANT_COLORS[variant_index % VARIANT_COLORS.size()]
	var wall_mat := MountainMaterials.get_mat("chalet_wall_%d" % variant_index, wall_color, 0.86)
	var trim_mat := MountainMaterials.wood_beam()
	var stone_mat := MountainMaterials.stone_river()
	var roof_mat := MountainMaterials.wood_shingle()
	var snow_mat := MountainMaterials.snow_fresh()
	var glass_mat := MountainMaterials.glass_warm()
	var brass_mat := MountainMaterials.metal_brass()
	
	var half_w := chalet_size.x * 0.5
	var half_d := chalet_size.y * 0.5
	var body_h := 2.6
	
	# Solid StaticBody3D for chalet body
	var body := StaticBody3D.new()
	body.name = "ChaletCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(chalet_size.x, body_h, chalet_size.y)
	col.shape = box_shape
	col.position = Vector3(0, body_h * 0.5 + 0.15, 0)
	body.add_child(col)
	add_child(body)
	
	# 1. Fieldstone Foundation Plinth
	_add_box("FoundationPlinth", Vector3(0, 0.12, 0), Vector3(chalet_size.x + 0.4, 0.24, chalet_size.y + 0.4), stone_mat)
	
	# 2. Main Horizontal Log Wall Body
	_add_box("LogWalls", Vector3(0, body_h * 0.5 + 0.24, 0), Vector3(chalet_size.x, body_h, chalet_size.y), wall_mat)
	
	# Horizontal log seam grooves on front facade (+Z)
	var log_rows := 9
	var log_row_h := body_h / float(log_rows)
	for r in log_rows:
		var ry := 0.24 + float(r) * log_row_h
		_add_box("LogGroove", Vector3(0, ry, half_d + 0.02), Vector3(chalet_size.x - 0.1, 0.04, 0.04), trim_mat)
	
	# Corner timber pillars
	for cx in [-half_w, half_w]:
		_add_box("CornerPillar", Vector3(cx, body_h * 0.5 + 0.24, half_d), Vector3(0.18, body_h, 0.18), trim_mat)
		_add_box("CornerPillarRear", Vector3(cx, body_h * 0.5 + 0.24, -half_d), Vector3(0.18, body_h, 0.18), trim_mat)
	
	# 3. Entrance Porch & Door (Center front: +Z)
	var door_w := 1.10
	var door_h := 2.10
	
	# Stone porch step
	_add_box("PorchStep", Vector3(0, 0.08, half_d + 0.45), Vector3(1.6, 0.16, 0.70), stone_mat)
	
	# Recessed door frame and timber plank door
	_add_box("DoorFrame", Vector3(0, door_h * 0.5 + 0.24, half_d + 0.02), Vector3(door_w + 0.18, door_h + 0.12, 0.08), trim_mat)
	_add_box("DoorLeaf", Vector3(0, door_h * 0.5 + 0.24, half_d + 0.04), Vector3(door_w, door_h, 0.06), trim_mat)
	_add_box("DoorHandle", Vector3(door_w * 0.38, 1.05 + 0.24, half_d + 0.08), Vector3(0.04, 0.18, 0.06), brass_mat)
	
	# Flanking Windows with Decorative Alpine Shutters
	for side in [-1.0, 1.0]:
		var wx: float = side * (half_w * 0.55)
		var wy: float = 1.45 + 0.24
		# Frame
		_add_box("WinFrame", Vector3(wx, wy, half_d + 0.02), Vector3(1.25, 1.10, 0.08), trim_mat)
		# Lit Glass
		var glass := _add_box("WinGlass", Vector3(wx, wy, half_d + 0.04), Vector3(1.05, 0.90, 0.02), glass_mat)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Wooden shutters
		for s in [-1.0, 1.0]:
			var sx: float = wx + s * 0.68
			_add_box("Shutter", Vector3(sx, wy, half_d + 0.05), Vector3(0.28, 1.05, 0.06), wall_mat)
	
	# 4. Pitched Gable Roof with Overhangs and Snow Accumulation
	var roof_pitch := 0.45 # ~26 degrees
	var roof_overhang_w := chalet_size.x + 0.8
	var roof_overhang_d := chalet_size.y + 0.8
	var ridge_y := body_h + 0.24 + 1.25
	
	for side in [-1.0, 1.0]:
		var panel_w := roof_overhang_d * 0.56
		var offset_z: float = side * (roof_overhang_d * 0.26)
		var roof_y := body_h + 0.24 + 0.60
		
		var deck := _add_box("RoofDeck", Vector3(0, roof_y, offset_z), Vector3(roof_overhang_w, 0.12, panel_w), roof_mat)
		deck.rotation.x = -side * roof_pitch
		
		var snow := _add_box("RoofSnow", Vector3(0, roof_y + 0.08, offset_z), Vector3(roof_overhang_w + 0.06, 0.14, panel_w + 0.04), snow_mat)
		snow.rotation.x = -side * roof_pitch
	
	# Ridge cap
	_add_box("RidgeCap", Vector3(0, ridge_y + 0.12, 0), Vector3(roof_overhang_w + 0.08, 0.14, 0.35), snow_mat)
	
	# 5. Roof Dormer Window (Center front roof slope)
	var dormer_z := half_d * 0.35
	var dormer_y := body_h + 0.24 + 0.65
	_add_box("DormerBody", Vector3(0, dormer_y, dormer_z), Vector3(1.10, 0.80, 0.90), wall_mat)
	var dormer_glass := _add_box("DormerGlass", Vector3(0, dormer_y, dormer_z + 0.46), Vector3(0.70, 0.55, 0.04), glass_mat)
	dormer_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_box("DormerSnowCap", Vector3(0, dormer_y + 0.48, dormer_z), Vector3(1.25, 0.12, 1.05), snow_mat)
	
	# 6. Fieldstone Chimney with Snow Cap
	var chim_pos := Vector3(half_w * 0.65, body_h + 0.24 + 0.95, -half_d * 0.45)
	_add_box("StoneChimney", chim_pos, Vector3(0.55, 1.60, 0.55), stone_mat)
	_add_box("ChimneySnowCap", chim_pos + Vector3(0, 0.86, 0), Vector3(0.72, 0.14, 0.72), snow_mat)
	
	# 7. Stack of Firewood logs beside porch
	var wood_x := -half_w * 0.55
	for f in 4:
		var fy: float = 0.14 + float(f / 2) * 0.16
		var fz: float = half_d + 0.30 + float(f % 2) * 0.18
		_add_box("Firewood", Vector3(wood_x, fy, fz), Vector3(0.70, 0.15, 0.15), MountainMaterials.wood_log())

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
