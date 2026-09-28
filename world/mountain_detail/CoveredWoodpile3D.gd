extends Node3D
class_name MountainCoveredWoodpile3D

## Rustic covered firewood and log storage shelter with snow roof and splitting stump.
## Based on the original CoveredWoodpile3D setpiece used throughout Mountain Pass.
## Reconstructed in clean native 3D geometry using cached MountainMaterials.
## StaticBody3D collision on layer 1, mask 0.

@export var shelter_size: Vector2 = Vector2(2.4, 1.4)
@export var shelter_height: float = 1.85

func _ready() -> void:
	build()

func build() -> void:
	for child in get_children():
		child.queue_free()
	
	var beam_mat := MountainMaterials.wood_beam()
	var log_mat := MountainMaterials.wood_log()
	var end_mat := MountainMaterials.wood_cut_end()
	var roof_mat := MountainMaterials.wood_shingle()
	var snow_mat := MountainMaterials.snow_fresh()
	var iron_mat := MountainMaterials.metal_iron()
	
	var half_w := shelter_size.x * 0.5
	var half_d := shelter_size.y * 0.5
	
	# Solid StaticBody3D for the woodpile
	var body := StaticBody3D.new()
	body.name = "WoodpileCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(shelter_size.x, shelter_height, shelter_size.y)
	col.shape = box_shape
	col.position = Vector3(0, shelter_height * 0.5, 0)
	body.add_child(col)
	add_child(body)
	
	# Base skids lifting timber off ground
	for x in [-half_w * 0.8, 0.0, half_w * 0.8]:
		_add_box("BaseSkid", Vector3(x, 0.06, 0), Vector3(0.14, 0.12, shelter_size.y * 0.95), beam_mat)
	
	# 4 Corner Posts
	var front_h := shelter_height - 0.15
	var back_h := shelter_height - 0.45
	for x in [-half_w * 0.85, half_w * 0.85]:
		# Front posts
		_add_box("PostFront", Vector3(x, front_h * 0.5, half_d * 0.85), Vector3(0.12, front_h, 0.12), beam_mat)
		# Rear posts (shorter for roof slope)
		_add_box("PostBack", Vector3(x, back_h * 0.5, -half_d * 0.85), Vector3(0.12, back_h, 0.12), beam_mat)
	
	# Side and rear retaining rails
	for side in [-1.0, 1.0]:
		var sx: float = side * half_w * 0.85
		_add_box("SideRailLow", Vector3(sx, 0.50, 0), Vector3(0.08, 0.10, shelter_size.y * 0.85), beam_mat)
		_add_box("SideRailMid", Vector3(sx, 1.05, 0), Vector3(0.08, 0.10, shelter_size.y * 0.85), beam_mat)
	_add_box("BackRail", Vector3(0, 0.70, -half_d * 0.85), Vector3(shelter_size.x * 0.85, 0.10, 0.08), beam_mat)
	
	# Stacked cylindrical logs inside the shelter
	var log_radius := 0.09
	var log_len := shelter_size.y * 0.82
	var layers := 5
	for layer in layers:
		var count := 7 - (layer % 2)
		var ly := 0.22 + float(layer) * (log_radius * 1.85)
		var start_x := -half_w * 0.70 + (float(layer % 2) * log_radius)
		for i in count:
			var lx := start_x + float(i) * (log_radius * 2.1)
			if absf(lx) > half_w * 0.75:
				continue
			# Log bark cylinder
			var log_cyl := _add_cylinder("Log_%d_%d" % [layer, i], Vector3(lx, ly, 0), log_radius, log_len, log_mat, Vector3(90, 0, 0))
			# Cut ends
			for end_z in [-log_len * 0.5 - 0.005, log_len * 0.5 + 0.005]:
				_add_box("LogEnd", Vector3(lx, ly, end_z), Vector3(log_radius * 1.8, log_radius * 1.8, 0.01), end_mat)
	
	# Sloped roof rafters and wood shake slab
	var roof_w := shelter_size.x + 0.35
	var roof_d := shelter_size.y + 0.35
	var roof_y := shelter_height - 0.12
	var roof_slab := _add_box("RoofSlab", Vector3(0, roof_y, 0), Vector3(roof_w, 0.08, roof_d), roof_mat)
	roof_slab.rotation.x = -0.15 # sloped toward rear (-Z)
	
	# Thick snow layer accumulating on roof
	var snow_slab := _add_box("RoofSnow", Vector3(0, roof_y + 0.08, 0), Vector3(roof_w + 0.06, 0.12, roof_d + 0.06), snow_mat)
	snow_slab.rotation.x = -0.15
	
	# Splitting stump beside the pile with axe
	var stump_pos := Vector3(half_w + 0.55, 0.25, half_d * 0.4)
	_add_cylinder("SplittingStump", stump_pos, 0.24, 0.50, log_mat)
	_add_box("StumpEnd", stump_pos + Vector3(0, 0.255, 0), Vector3(0.44, 0.01, 0.44), end_mat)
	
	# Iron splitting axe embedded in stump
	var axe_pos := stump_pos + Vector3(0.02, 0.38, 0)
	_add_box("AxeBlade", axe_pos, Vector3(0.03, 0.16, 0.22), iron_mat)
	_add_box("AxeHandle", axe_pos + Vector3(0, 0.25, -0.22), Vector3(0.04, 0.70, 0.04), MountainMaterials.wood_pole(), Vector3(25, 0, 0))
	
	# Split firewood pieces on the ground near stump
	for f in 3:
		var f_pos := stump_pos + Vector3(-0.35 + float(f) * 0.25, 0.06, 0.35 + float(f % 2) * 0.12)
		_add_box("FirewoodPiece", f_pos, Vector3(0.12, 0.12, 0.38), log_mat, Vector3(0, float(f) * 40.0, 0))

func _add_box(node_name: String, pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi

func _add_cylinder(node_name: String, pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi
